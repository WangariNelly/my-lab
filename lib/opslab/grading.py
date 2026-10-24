"""Tiny grading framework shared by convergence and scenario graders.

A grader is a list of named checks. Each check returns (passed, detail).
The runner prints a report, writes JSON evidence, and exits non-zero on
any failure so `task grade:all` and CI can gate on it.

    from opslab.grading import Grader

    g = Grader("S1 — DB incident auto-remediation")

    @g.check("Incident created on the right CI")
    def _():
        inc = sn.wait_for("incident", "cmdb_ci.name=shop-postgres^stateNOT IN6,7,8")
        return inc is not None, inc and inc["number"]

    g.run()
"""

from __future__ import annotations

import json
import sys
import time
import traceback
from collections.abc import Callable
from dataclasses import dataclass, field
from pathlib import Path

CheckFn = Callable[[], "tuple[bool, object]"]


@dataclass
class Result:
    name: str
    passed: bool
    detail: str
    seconds: float

    @property
    def skipped(self) -> bool:
        """A check that passed only because its prerequisite service was absent."""
        return self.passed and self.detail.lower().startswith("skipped")


@dataclass
class Grader:
    title: str
    evidence_dir: Path = Path("evidence")
    checks: list[tuple[str, CheckFn]] = field(default_factory=list)

    def check(self, name: str) -> Callable[[CheckFn], CheckFn]:
        def register(fn: CheckFn) -> CheckFn:
            self.checks.append((name, fn))
            return fn

        return register

    def evaluate(self) -> list[Result]:
        results: list[Result] = []
        for name, fn in self.checks:
            start = time.monotonic()
            try:
                passed, detail = fn()
            except Exception as exc:  # a crashing check is a failing check, with the reason
                passed, detail = False, f"{type(exc).__name__}: {exc}\n{traceback.format_exc(limit=2)}"
            results.append(Result(name, bool(passed), str(detail), round(time.monotonic() - start, 1)))
        return results

    def run(self, *, exit: bool = True) -> int:
        results = self.evaluate()
        print(f"\n== {self.title} ==")
        for r in results:
            mark = "PASS" if r.passed else "FAIL"
            print(f"[{mark}] {r.name} ({r.seconds}s)")
            if r.detail and r.detail != "None":
                print(f"       {r.detail}")
        failed = [r for r in results if not r.passed]
        skipped = [r for r in results if r.skipped]
        verified = len(results) - len(failed) - len(skipped)
        # The first line keeps the format convergence/C7-capstone/scripts/regression.py parses.
        print(f"\n{len(results) - len(failed)}/{len(results)} checks passed")
        print(f"verified: {verified}, skipped: {len(skipped)}, failed: {len(failed)}")
        if skipped and not verified:
            print("NOTHING WAS VERIFIED: every passing check was skipped. Configure the services above and re-run.")
        self.evidence_dir.mkdir(parents=True, exist_ok=True)
        slug = "".join(c if c.isalnum() else "-" for c in self.title.lower()).strip("-")
        out = self.evidence_dir / f"{slug}-{time.strftime('%Y%m%dT%H%M%S')}.json"
        out.write_text(json.dumps([r.__dict__ for r in results], indent=2))
        print(f"evidence: {out}")
        code = 1 if failed else 0
        if exit:
            sys.exit(code)
        return code
