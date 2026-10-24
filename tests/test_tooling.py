"""Validate repo-wide practice assets without network access."""

from __future__ import annotations

import importlib.util
import re
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[1]


def _load_seed_module():
    spec = importlib.util.spec_from_file_location("seed_tickets", ROOT / "itsm" / "seed-tickets.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def test_every_ticket_file_is_valid():
    seed = _load_seed_module()
    files = sorted((ROOT / "itsm" / "tickets").glob("*.yaml"))
    ids: set[str] = set()
    for path in files:
        tickets = seed.load(path)
        assert 3 <= len(tickets) <= 5, f"{path.name}: {len(tickets)} tickets"
        for t in tickets:
            assert t["id"].startswith(path.stem + "-"), f"{path.name}: id {t['id']} should start with {path.stem}-"
            assert t["id"] not in ids, f"duplicate ticket id {t['id']}"
            ids.add(t["id"])


def test_ticket_record_includes_acceptance_criteria():
    seed = _load_seed_module()
    rec = seed.to_record(
        None,
        {"id": "W99-T1", "type": "incident", "short_description": "x", "priority": 2, "acceptance_criteria": ["a"]},
    )
    assert rec["correlation_id"] == "W99-T1"
    assert "Acceptance criteria" in rec["description"]
    assert rec["impact"] == rec["urgency"] == "2"


def test_fault_injectors_follow_contract():
    for script in sorted((ROOT / "faults").glob("*/*.sh")):
        if script.name.startswith("_"):
            continue  # shared helper sourced by injectors, not an injector
        assert re.match(r"^\d+-[a-z0-9-]+\.sh$", script.name), f"bad injector name {script}"
        text = script.read_text()
        assert "set -euo pipefail" in text, f"{script} must use strict mode"
        for verb in ("inject)", "revert)", "describe)"):
            assert verb in text, f"{script} missing verb {verb}"


def test_cmdb_seed_names_are_canonical():
    cmdb = ROOT / "itsm" / "cmdb" / "shop.yaml"
    if not cmdb.exists():
        return
    text = cmdb.read_text()
    for name in ("shop-checkout", "shop-postgres", "shop-eks-prod", "Platform", "DBA", "SRE", "SecOps"):
        assert name in text, f"{name} missing from CMDB seed"
    yaml.safe_load(text)
