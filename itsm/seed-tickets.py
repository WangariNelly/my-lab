#!/usr/bin/env python3
"""Seed a module's ticket queue into your ServiceNow PDI.

    python itsm/seed-tickets.py --module W02          # one module
    python itsm/seed-tickets.py --all                 # every tickets/*.yaml
    python itsm/seed-tickets.py --module W02 --dry-run

Ticket files live in itsm/tickets/<MODULE>.yaml:

    module: W02
    tickets:
      - id: W02-T1                 # stable id -> correlation_id (idempotent re-runs)
        type: request              # request | incident | change
        short_description: "Add a systemd timer that rotates the shop's export files"
        description: |
          Free text, written the way a real requester would write it.
        priority: 4                # 1-5 (incident/change); ignored for requests
        assignment_group: Platform # must exist (see itsm/seed-cmdb.py)
        cmdb_ci: shop-vm-1         # optional, CI name
        acceptance_criteria:
          - "Timer runs daily and is visible in systemctl list-timers"

Requests are created as catalog tasks (sc_task), incidents in `incident`,
changes in `change_request`. Requires SN_INSTANCE, SN_USER, SN_PASSWORD.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "lib"))

import yaml  # noqa: E402
from opslab.servicenow import ServiceNow  # noqa: E402

TABLES = {"request": "sc_task", "incident": "incident", "change": "change_request"}
TICKETS_DIR = Path(__file__).resolve().parent / "tickets"


def load(path: Path) -> list[dict]:
    doc = yaml.safe_load(path.read_text())
    tickets = doc.get("tickets", [])
    for t in tickets:
        missing = {"id", "type", "short_description"} - t.keys()
        if missing:
            raise ValueError(f"{path.name}: ticket {t.get('id', '?')} missing {sorted(missing)}")
        if t["type"] not in TABLES:
            raise ValueError(f"{path.name}: ticket {t['id']} has unknown type {t['type']!r}")
    return tickets


def to_record(sn: ServiceNow | None, ticket: dict) -> dict:
    criteria = "\n".join(f"- {c}" for c in ticket.get("acceptance_criteria", []))
    description = ticket.get("description", "").rstrip()
    if criteria:
        description += f"\n\nAcceptance criteria:\n{criteria}"
    record = {
        "correlation_id": ticket["id"],
        "short_description": f"[{ticket['id']}] {ticket['short_description']}",
        "description": description,
    }
    if ticket["type"] != "request" and "priority" in ticket:
        # Impact and urgency drive priority on a default instance.
        level = str(min(max(int(ticket["priority"]), 1), 3))
        record.update({"impact": level, "urgency": level})
    if sn and ticket.get("assignment_group"):
        groups = sn.query("sys_user_group", f"name={ticket['assignment_group']}", fields=["sys_id"], limit=1)
        if groups:
            record["assignment_group"] = groups[0]["sys_id"]
    if sn and ticket.get("cmdb_ci"):
        cis = sn.query("cmdb_ci", f"name={ticket['cmdb_ci']}", fields=["sys_id"], limit=1)
        if cis:
            record["cmdb_ci"] = cis[0]["sys_id"]
    return record


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    group = ap.add_mutually_exclusive_group(required=True)
    group.add_argument("--module", help="e.g. W02 or C1")
    group.add_argument("--all", action="store_true")
    ap.add_argument("--dry-run", action="store_true", help="validate and print, don't call ServiceNow")
    args = ap.parse_args()

    files = sorted(TICKETS_DIR.glob("*.yaml")) if args.all else [TICKETS_DIR / f"{args.module}.yaml"]
    sn = None if args.dry_run else ServiceNow.from_env()
    for path in files:
        if not path.exists():
            print(f"no ticket file {path}", file=sys.stderr)
            return 1
        for ticket in load(path):
            table = TABLES[ticket["type"]]
            record = to_record(sn, ticket)
            if args.dry_run:
                print(f"[dry-run] {table:15} {record['short_description']}")
                continue
            created = sn.upsert(table, "correlation_id", record)
            print(f"{table:15} {created.get('number', created.get('sys_id'))}  {record['short_description']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
