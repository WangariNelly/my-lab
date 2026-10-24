#!/usr/bin/env bash
# Destroy the cumulative platform, then report (or, with CONFIRM=yes,
# delete) anything still tagged program=opslab. This is the safety net
# behind per-module teardown — it is not a substitute for it.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ -x "$root/platform/scripts/down.sh" || -f "$root/platform/scripts/down.sh" ]]; then
  bash "$root/platform/scripts/down.sh"
fi

arns="$(aws resourcegroupstaggingapi get-resources \
  --tag-filters Key=program,Values=opslab \
  --query 'ResourceTagMappingList[].ResourceARN' --output text || true)"

if [[ -z "$arns" || "$arns" == "None" ]]; then
  echo "Nothing tagged program=opslab remains."
  exit 0
fi

echo "Still tagged program=opslab:"
tr '\t' '\n' <<<"$arns"

if [[ "${CONFIRM:-}" != "yes" ]]; then
  echo
  echo "Re-run with CONFIRM=yes to delete these with aws-nuke/cloud-nuke filtered to program=opslab,"
  echo "or remove them via the Terraform that created them (preferred)."
  exit 1
fi

if command -v cloud-nuke >/dev/null; then
  # cloud-nuke has no tag-include filter for every resource type, so we drive it by
  # an explicit config that only matches the program tag.
  cloud-nuke aws --config "$root/scripts/cloud-nuke.yaml" --force
else
  echo "cloud-nuke not installed (it ships in the devcontainer)." >&2
  exit 1
fi
