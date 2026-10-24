#!/usr/bin/env bash
# Run a hidden fault injector without revealing what it does.
#
#   faults/run.sh <MODULE> <N> [inject|revert|describe]
#
# Injectors live in faults/<MODULE>/<N>-<slug>.sh and must implement the
# three verbs. `describe` prints the root cause; only use it after you've
# finished the drill (or `task break:reveal`).
set -euo pipefail

module="${1:?usage: faults/run.sh <MODULE> <N> [inject|revert|describe]}"
n="${2:?usage: faults/run.sh <MODULE> <N> [inject|revert|describe]}"
verb="${3:-inject}"

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
shopt -s nullglob
matches=("$here/$module"/"$n"-*.sh)
if [[ ${#matches[@]} -ne 1 ]]; then
  echo "expected exactly one injector at faults/$module/$n-*.sh, found ${#matches[@]}" >&2
  exit 1
fi

case "$verb" in
  inject)
    started="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    bash "${matches[0]}" inject >/dev/null
    mkdir -p "$here/../evidence"
    printf '{"module":"%s","fault":%s,"injected_at":"%s"}\n' "$module" "$n" "$started" \
      >> "$here/../evidence/drills.jsonl"
    echo "Fault $module/$n injected at $started. Start the clock: diagnose from telemetry only."
    ;;
  revert)   bash "${matches[0]}" revert ;;
  describe) bash "${matches[0]}" describe ;;
  *) echo "unknown verb $verb" >&2; exit 2 ;;
esac
