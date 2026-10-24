#!/usr/bin/env bash
# After `task down`, prove nothing tagged for the module is still running.
# Note: the tagging API sees most, not all, resource types — also check
# Cost Explorer the next day. Usage: verify-clean.sh W09
set -euo pipefail
module="${1:?usage: verify-clean.sh <MODULE>}"

left="$(aws resourcegroupstaggingapi get-resources \
  --tag-filters "Key=module,Values=$module" \
  --query 'ResourceTagMappingList[].ResourceARN' --output text)"

if [[ -n "$left" && "$left" != "None" ]]; then
  echo "Resources still tagged module=$module:"
  tr '\t' '\n' <<<"$left"
  exit 1
fi
echo "Clean: no AWS resources tagged module=$module in region ${AWS_REGION:-$(aws configure get region)}."
