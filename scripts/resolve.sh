#!/usr/bin/env bash
# Resolve a short id (W09, C3, S1, E1, platform) to its folder path.
set -euo pipefail
id="${1:?usage: resolve.sh <W09|C3|S1|E1|platform>}"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

case "$id" in
  platform) echo "$root/platform"; exit 0 ;;
  W*) pattern="$root/modules/$id-*" ;;
  C*) pattern="$root/convergence/$id-*" ;;
  S*) pattern="$root/scenarios/$id-*" ;;
  E*) pattern="$root/modules/electives/$id-*" ;;
  *) echo "unknown id '$id' (expected W09, C3, S1, E1 or platform)" >&2; exit 2 ;;
esac

shopt -s nullglob
# shellcheck disable=SC2206  # intentional glob expansion (nullglob set above)
matches=($pattern)
if [[ ${#matches[@]} -ne 1 ]]; then
  echo "expected exactly one folder for '$id', found ${#matches[@]}" >&2
  exit 1
fi
echo "${matches[0]}"
