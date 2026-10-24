#!/usr/bin/env bash
# Regression: run every grader listed in platform/unlocked.txt (one id per
# line, e.g. C1, S3, C2, S8). Add ids as you complete convergences.
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
list="$root/platform/unlocked.txt"

if [[ ! -f "$list" ]]; then
  echo "No $list yet — add C1 and S3 after your first convergence."
  exit 0
fi

failed=()
while read -r id; do
  [[ -z "$id" || "$id" == \#* ]] && continue
  dir="$(bash "$root/scripts/resolve.sh" "$id")" || { failed+=("$id"); continue; }
  echo "=== $id ==="
  PYTHONPATH="$root/lib" python "$dir/grader.py" || failed+=("$id")
done <"$list"

if ((${#failed[@]})); then
  echo "Regression failures: ${failed[*]}"
  exit 1
fi
echo "All unlocked graders pass."
