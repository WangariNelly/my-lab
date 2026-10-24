#!/usr/bin/env bash
# W01/3 — Git is pointed at an empty hooks directory, silently bypassing pre-commit.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
empty="$root/.git/opslab-empty-hooks"
case "${1:-}" in
  inject)
    mkdir -p "$empty"
    git -C "$root" config --local core.hooksPath "$empty"
    ;;
  revert)
    if [[ "$(git -C "$root" config --local --get core.hooksPath || true)" == "$empty" ]]; then
      git -C "$root" config --local --unset core.hooksPath
    fi
    rm -rf "$empty"
    echo "reverted"
    ;;
  describe) cat <<'EOT'
Root cause: `git config core.hooksPath` points at an empty directory, so
.git/hooks/pre-commit (installed by `pre-commit install`) never runs.
Signals: commits with trailing whitespace or secrets go through locally; CI (which
runs the same checks) fails; `git config --show-origin --get core.hooksPath`.
Prevention: CI runs the same gates as pre-commit (never rely on client-side hooks
alone); scripts/up.sh warns when core.hooksPath is set.
EOT
  ;;
  *) echo "usage: $0 inject|revert|describe" >&2; exit 2 ;;
esac
