#!/usr/bin/env bash
# add-week.sh: unpacks a lesson's kit into this repository.
#
#   scripts/add-week.sh <ID> [--from FILE] [--dry-run] [--force]
#   scripts/add-week.sh --list
#
# A kit is a .tar.gz of one lesson's files. Download it from the course app (Downloads page): the browser saves it as
# <ID>.tar.gz. The script looks for it in $OPSLAB_KIT_DIR, the current folder, this repository's root and ~/Downloads;
# pass --from FILE for anywhere else. <ID> is a lesson (W09, C3), a scenario (S1) or a group name (applications, automation).
# Files that already exist and differ are kept unless you pass --force, so your own changes are never lost.
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: scripts/add-week.sh <ID> [--from FILE] [--dry-run] [--force]
       scripts/add-week.sh --list

  <ID>         W09, C3, S1 ... or a group name such as applications
  --from FILE  the kit you downloaded (default: <ID>.tar.gz in $OPSLAB_KIT_DIR, here, the repository root or ~/Downloads)
  --list       show the kit files found in those places
  --dry-run    show what would be written, change nothing
  --force      overwrite files that already exist and differ
USAGE
}

ID=""
FROM=""
LIST=0
DRY=0
FORCE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --list) LIST=1 ;;
    --dry-run) DRY=1 ;;
    --force) FORCE=1 ;;
    --from) FROM="${2:?--from needs the path of the kit file}"; shift ;;
    -h|--help) usage; exit 0 ;;
    -*) echo "add-week: unknown option $1" >&2; usage >&2; exit 2 ;;
    *) if [ -z "$ID" ]; then ID="$1"; else echo "add-week: unexpected argument $1" >&2; exit 2; fi ;;
  esac
  shift
done

root="$(git rev-parse --show-toplevel 2>/dev/null || (cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd))"
command -v tar >/dev/null 2>&1 || { echo "add-week: tar is required" >&2; exit 1; }

# Where a downloaded kit may be.
places=()
[ -n "${OPSLAB_KIT_DIR:-}" ] && places+=("$OPSLAB_KIT_DIR")
places+=("$PWD" "$root" "${HOME:-/nonexistent}/Downloads")

if [ "$LIST" -eq 1 ]; then
  found=0
  for dir in "${places[@]}"; do
    for f in "$dir"/*.tar.gz; do
      [ -f "$f" ] || continue
      case "$(basename "$f" .tar.gz)" in *[!A-Za-z0-9-]*) continue ;; esac
      printf '%-12s %s\n' "$(basename "$f" .tar.gz)" "$f"
      found=1
    done
  done
  [ "$found" -eq 1 ] || echo "No kit files found. Download them from the course app (Downloads page)."
  exit 0
fi

if [ -z "$ID" ]; then usage >&2; exit 2; fi
ID="$(printf '%s' "$ID" | tr '[:lower:]' '[:upper:]')"
case "$ID" in
  *[!A-Za-z0-9-]*) echo "add-week: '$ID' is not a kit id" >&2; exit 2 ;;
esac
lower="$(printf '%s' "$ID" | tr '[:upper:]' '[:lower:]')"

kit=""
if [ -n "$FROM" ]; then
  [ -f "$FROM" ] || { echo "add-week: $FROM does not exist" >&2; exit 1; }
  kit="$FROM"
else
  for dir in "${places[@]}"; do
    for name in "$ID" "$lower"; do
      if [ -f "$dir/$name.tar.gz" ]; then kit="$dir/$name.tar.gz"; break 2; fi
    done
  done
fi
if [ -z "$kit" ]; then
  echo "add-week: no kit file for '$ID' found." >&2
  echo "  Download it from the course app (Downloads page), then run this again," >&2
  echo "  or point at it with: scripts/add-week.sh $ID --from path/to/$ID.tar.gz" >&2
  exit 1
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# A kit only ever writes inside this repository: refuse anything with an absolute path or a ".." in it.
# (The archive is read from standard input so a Windows path with a drive letter is never mistaken for host:file.)
if ! tar -tzf - < "$kit" > "$tmp/list" 2>/dev/null; then
  echo "add-week: $kit is not a kit (it is not a readable .tar.gz)" >&2
  exit 1
fi
if grep -Eq '^/|(^|/)\.\.(/|$)' "$tmp/list"; then
  echo "add-week: $kit contains paths outside the repository; refusing to unpack it" >&2
  exit 1
fi
mkdir "$tmp/files"
tar -xzf - -C "$tmp/files" < "$kit"

wrote=0
same=0
kept=0
cd "$tmp/files"
while IFS= read -r path; do
  dest="$root/$path"
  if [ -e "$dest" ] && [ "$FORCE" -ne 1 ]; then
    if cmp -s "$path" "$dest"; then
      same=$((same + 1))
    else
      kept=$((kept + 1))
      echo "kept   $path (differs; use --force to replace it)"
    fi
    continue
  fi
  if [ "$DRY" -eq 1 ]; then
    echo "would write $path"
  else
    mkdir -p "$(dirname "$dest")"
    cp -p "$path" "$dest"
  fi
  wrote=$((wrote + 1))
done < <(find . -type f | sed 's|^\./||' | sort)

if [ "$DRY" -eq 1 ]; then
  echo "Dry run: $wrote to write, $same identical, $kept kept."
  exit 0
fi
echo "Added $ID from $kit: $wrote written, $same already identical, $kept kept."
echo "Next: git switch -c feat/$(printf '%s' "$ID" | tr '[:upper:]' '[:lower:]'), review with git status, commit, open a pull request."
