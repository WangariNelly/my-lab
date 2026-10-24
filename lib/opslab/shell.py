"""Run CLI tools (kubectl, aws, terraform) from graders and fault injectors."""

from __future__ import annotations

import json
import shutil
import subprocess
from typing import Any


class CommandFailed(RuntimeError):
    pass


def run(cmd: list[str], *, check: bool = True, timeout: int = 300) -> subprocess.CompletedProcess[str]:
    if shutil.which(cmd[0]) is None:
        raise CommandFailed(f"{cmd[0]} is not installed or not on PATH (it ships in the devcontainer)")
    proc = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)  # noqa: S603
    if check and proc.returncode != 0:
        raise CommandFailed(f"{' '.join(cmd)} exited {proc.returncode}: {proc.stderr.strip()}")
    return proc


def run_json(cmd: list[str], **kwargs: Any) -> Any:
    return json.loads(run(cmd, **kwargs).stdout or "null")


def kubectl_json(*args: str) -> Any:
    return run_json(["kubectl", *args, "-o", "json"])
