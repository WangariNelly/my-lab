#!/usr/bin/env python3
"""Fail if any YAML file in the repo does not parse.

Template files (Helm/Jinja/Backstage placeholders) are skipped: they are not
plain YAML until rendered. Needs pyyaml (already in requirements-dev.txt).
"""

from __future__ import annotations

import sys
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[1]
SKIP_DIRS = {".git", "node_modules", ".terraform", "__pycache__"}
TEMPLATE_MARKERS = ("{%", ".Values", "${{")


def is_template(text: str) -> bool:
    return any(marker in text for marker in TEMPLATE_MARKERS)


def main() -> int:
    failures: list[str] = []
    checked = skipped = 0
    for path in sorted(ROOT.rglob("*")):
        if path.suffix not in {".yaml", ".yml"} or SKIP_DIRS & set(path.parts):
            continue
        text = path.read_text(encoding="utf-8", errors="replace")
        if is_template(text):
            skipped += 1
            continue
        checked += 1
        try:
            list(yaml.safe_load_all(text))
        except yaml.YAMLError as exc:
            first = str(exc).splitlines()[0]
            failures.append(f"{path.relative_to(ROOT)}: {first}")
    if failures:
        print(f"Invalid YAML ({len(failures)}):")
        print("\n".join(failures))
        return 1
    print(f"YAML OK: {checked} files parsed, {skipped} template files skipped.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
