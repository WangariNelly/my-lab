#!/usr/bin/env python3
"""Seed the shop's CMDB into your ServiceNow PDI (idempotent).

    python itsm/seed-cmdb.py --dry-run      # validate itsm/cmdb/shop.yaml, print the plan
    python itsm/seed-cmdb.py                # create/update groups, services, CIs, relationships
    python itsm/seed-cmdb.py --file other.yaml

What it creates (from itsm/cmdb/shop.yaml):

- assignment groups      -> sys_user_group
- business services      -> cmdb_ci_service_business (fallback cmdb_ci_service)
- configuration items    -> the class named per CI (e.g. cmdb_ci_linux_server,
                            cmdb_ci_db_postgresql_instance), falling back to
                            `fallback_class`, then cmdb_ci, if your instance
                            lacks the class
- relationships          -> cmdb_rel_ci, type "Depends on::Used by"

Re-running is safe: every record is matched by name and updated in place.
Requires SN_INSTANCE, SN_USER, SN_PASSWORD (see lib/README.md).
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "lib"))

import yaml  # noqa: E402
from opslab.http import HttpError  # noqa: E402
from opslab.servicenow import ServiceNow  # noqa: E402

DEFAULT_FILE = Path(__file__).resolve().parent / "cmdb" / "shop.yaml"
SERVICE_CLASSES = ["cmdb_ci_service_business", "cmdb_ci_service"]
REL_TYPE = "Depends on::Used by"
OPERATIONAL = "1"


def load(path: Path) -> dict[str, Any]:
    doc = yaml.safe_load(path.read_text())
    for key in ("groups", "business_services", "cis"):
        if not isinstance(doc.get(key), list):
            raise ValueError(f"{path.name}: '{key}' must be a list")
    groups = {g["name"] for g in doc["groups"]}
    names = [s["name"] for s in doc["business_services"]] + [c["name"] for c in doc["cis"]]
    dupes = {n for n in names if names.count(n) > 1}
    if dupes:
        raise ValueError(f"{path.name}: duplicate names {sorted(dupes)}")
    for item in doc["business_services"] + doc["cis"]:
        group = item.get("support_group")
        if group and group not in groups:
            raise ValueError(f"{path.name}: {item['name']} references unknown group {group!r}")
    for rel in doc.get("relationships", []):
        if len(rel) != 2 or any(n not in names for n in rel):
            raise ValueError(f"{path.name}: bad relationship {rel!r} (both ends must be defined)")
    return doc


class Seeder:
    def __init__(self, sn: ServiceNow):
        self.sn = sn
        self._exists: dict[str, bool] = {}
        self.group_ids: dict[str, str] = {}
        self.ci_ids: dict[str, str] = {}

    def table_exists(self, table: str) -> bool:
        if table not in self._exists:
            try:
                self.sn.query(table, "sys_idISNOTEMPTY", fields=["sys_id"], limit=1)
                self._exists[table] = True
            except HttpError as exc:
                if exc.status in (400, 403, 404):
                    self._exists[table] = False
                else:
                    raise
        return self._exists[table]

    def resolve_class(self, candidates: list[str]) -> str:
        for table in [*candidates, "cmdb_ci"]:
            if table and self.table_exists(table):
                return table
        raise RuntimeError(f"none of {candidates} exist on this instance")

    def upsert_group(self, group: dict[str, Any]) -> None:
        record = {"name": group["name"], "description": group.get("description", "")}
        result = self.sn.upsert("sys_user_group", "name", record)
        self.group_ids[group["name"]] = result["sys_id"]
        print(f"group    {group['name']:18} {result['sys_id']}")

    def upsert_ci(self, item: dict[str, Any], candidates: list[str], extra: dict[str, Any]) -> None:
        record: dict[str, Any] = {
            "name": item["name"],
            "short_description": item.get("description", ""),
            "operational_status": OPERATIONAL,
            **extra,
        }
        if item.get("support_group"):
            record["support_group"] = self.group_ids[item["support_group"]]
        # Match on name across the whole CMDB, so a CI created earlier in a
        # fallback class is updated rather than duplicated.
        existing = self.sn.query("cmdb_ci", f"name={item['name']}", fields=["sys_id", "sys_class_name"], limit=1)
        if existing:
            table = existing[0]["sys_class_name"]
            result = self.sn.update(table, existing[0]["sys_id"], record)
            verb = "updated"
        else:
            table = self.resolve_class(candidates)
            result = self.sn.create(table, record)
            verb = "created"
        self.ci_ids[item["name"]] = result["sys_id"]
        print(f"ci       {item['name']:18} {verb:7} {table}")

    def relate(self, parent: str, child: str, rel_type_id: str) -> None:
        p, c = self.ci_ids[parent], self.ci_ids[child]
        query = f"parent={p}^child={c}^type={rel_type_id}"
        if self.sn.query("cmdb_rel_ci", query, fields=["sys_id"], limit=1):
            print(f"rel      {parent} -> {child} (exists)")
            return
        self.sn.create("cmdb_rel_ci", {"parent": p, "child": c, "type": rel_type_id})
        print(f"rel      {parent} -> {child} (created)")


def dry_run(doc: dict[str, Any]) -> None:
    for g in doc["groups"]:
        print(f"[dry-run] sys_user_group           {g['name']}")
    for s in doc["business_services"]:
        print(f"[dry-run] {SERVICE_CLASSES[0]:24} {s['name']}")
    for c in doc["cis"]:
        print(f"[dry-run] {c['class']:24} {c['name']}  (fallback {c.get('fallback_class', 'cmdb_ci')})")
    for parent, child in doc.get("relationships", []):
        print(f"[dry-run] cmdb_rel_ci              {parent} --{REL_TYPE}--> {child}")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--file", type=Path, default=DEFAULT_FILE, help="CMDB model (default: itsm/cmdb/shop.yaml)")
    ap.add_argument("--dry-run", action="store_true", help="validate and print, don't call ServiceNow")
    args = ap.parse_args()

    doc = load(args.file)
    if args.dry_run:
        dry_run(doc)
        return 0

    seeder = Seeder(ServiceNow.from_env())
    for group in doc["groups"]:
        seeder.upsert_group(group)
    for svc in doc["business_services"]:
        extra = {"busines_criticality": svc.get("busines_criticality", "")}  # sic: ServiceNow's field name
        seeder.upsert_ci(svc, SERVICE_CLASSES, extra)
    for ci in doc["cis"]:
        seeder.upsert_ci(ci, [ci["class"], ci.get("fallback_class", "")], {})

    rel_types = seeder.sn.query("cmdb_rel_type", f"name={REL_TYPE}", fields=["sys_id"], limit=1)
    if not rel_types:
        print(f"relationship type {REL_TYPE!r} not found; skipping relationships", file=sys.stderr)
        return 1
    for parent, child in doc.get("relationships", []):
        seeder.relate(parent, child, rel_types[0]["sys_id"])
    print("CMDB seeded.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
