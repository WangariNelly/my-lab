"""Unit tests for lib/opslab — no network: HTTP is stubbed."""

from __future__ import annotations

import json

import pytest
from opslab import grading, servicenow
from opslab.config import MissingConfig, env
from opslab.http import basic_auth


def test_basic_auth_header():
    assert basic_auth("a", "b") == "Basic YTpi"


def test_env_required_raises(monkeypatch):
    monkeypatch.delenv("OPSLAB_TEST_VAR", raising=False)
    with pytest.raises(MissingConfig):
        env("OPSLAB_TEST_VAR")
    assert env("OPSLAB_TEST_VAR", "x") == "x"


class FakeRequest:
    def __init__(self, responses):
        self.calls = []
        self.responses = list(responses)

    def __call__(self, method, url, **kwargs):
        self.calls.append((method, url, kwargs))
        return self.responses.pop(0)


def test_upsert_creates_when_missing(monkeypatch):
    fake = FakeRequest([{"result": []}, {"result": {"sys_id": "1", "number": "INC1"}}])
    monkeypatch.setattr(servicenow, "request", fake)
    sn = servicenow.ServiceNow("https://dev.example", "u", "p")
    out = sn.upsert("incident", "correlation_id", {"correlation_id": "W02-T1", "short_description": "x"})
    assert out["number"] == "INC1"
    assert [c[0] for c in fake.calls] == ["GET", "POST"]


def test_upsert_updates_when_present(monkeypatch):
    fake = FakeRequest([{"result": [{"sys_id": "abc"}]}, {"result": {"sys_id": "abc"}}])
    monkeypatch.setattr(servicenow, "request", fake)
    sn = servicenow.ServiceNow("https://dev.example", "u", "p")
    sn.upsert("incident", "correlation_id", {"correlation_id": "W02-T1"})
    method, url, _ = fake.calls[1]
    assert method == "PATCH" and url.endswith("/incident/abc")


def test_grader_reports_failures_and_writes_evidence(tmp_path):
    g = grading.Grader("unit test", evidence_dir=tmp_path)

    @g.check("passes")
    def _ok():
        return True, "fine"

    @g.check("crashes")
    def _boom():
        raise RuntimeError("nope")

    assert g.run(exit=False) == 1
    files = list(tmp_path.glob("*.json"))
    assert len(files) == 1
    results = json.loads(files[0].read_text())
    assert [r["passed"] for r in results] == [True, False]
    assert "RuntimeError" in results[1]["detail"]


def test_grader_does_not_count_skipped_checks_as_verified(tmp_path, capsys):
    g = grading.Grader("skip test", evidence_dir=tmp_path)

    @g.check("needs servicenow")
    def _skipped():
        return True, "skipped: set SN_INSTANCE"

    @g.check("offline logic")
    def _ok():
        return True, "ok"

    assert g.run(exit=False) == 0
    out = capsys.readouterr().out
    assert "2/2 checks passed" in out
    assert "verified: 1, skipped: 1, failed: 0" in out
    assert "NOTHING WAS VERIFIED" not in out


def test_grader_warns_when_everything_was_skipped(tmp_path, capsys):
    g = grading.Grader("all skipped", evidence_dir=tmp_path)

    @g.check("needs azure")
    def _skipped():
        return True, "skipped: no subscription"

    assert g.run(exit=False) == 0
    out = capsys.readouterr().out
    assert "1/1 checks passed" in out
    assert "verified: 0, skipped: 1, failed: 0" in out
    assert "NOTHING WAS VERIFIED" in out
