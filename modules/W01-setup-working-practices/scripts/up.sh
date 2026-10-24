#!/usr/bin/env bash
# W01 — verify the workstation, guard the AWS account, seed ServiceNow and
# start the shop locally. Idempotent: safe to re-run at any time.
#
# Env: OWNER, AWS_PROFILE, AWS_REGION, BUDGET_EMAIL, SN_INSTANCE/SN_USER/SN_PASSWORD
# Set SKIP_AWS=1 or SKIP_SN=1 to skip those stages while accounts are pending.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/../../.." && pwd)"

stage() { printf '\n==> %s\n' "$1"; }

stage "Toolchain"
missing=()
for tool in git docker task aws az gcloud kubectl helm kind terraform jq shellcheck pre-commit python3; do
  command -v "$tool" >/dev/null || missing+=("$tool")
done
if ((${#missing[@]})); then
  echo "missing: ${missing[*]} — rebuild the devcontainer or run .devcontainer/install-tools.sh" >&2
  exit 1
fi
echo "all tools present"
docker info --format 'Docker {{.ServerVersion}}, cgroup {{.CgroupVersion}}'

stage "Git hygiene"
git -C "$root" config --get core.hooksPath >/dev/null && echo "WARNING: core.hooksPath is set — pre-commit may be bypassed"
(cd "$root" && pre-commit install >/dev/null && echo "pre-commit hook installed")

if [[ "${SKIP_AWS:-0}" != 1 ]]; then
  stage "AWS identity and budgets"
  aws sts get-caller-identity --query '{account:Account,arn:Arn}' --output table
  if [[ -n "${BUDGET_EMAIL:-}" ]]; then
    bash "$here/budget.sh"
  else
    echo "BUDGET_EMAIL not set — skipping budget creation (it is mandatory before W02)"
  fi
fi

if [[ "${SKIP_SN:-0}" != 1 ]]; then
  stage "ServiceNow CMDB"
  python3 "$root/itsm/seed-cmdb.py"
fi

stage "Shop (local Docker Compose)"
bash "$root/apps/shop/shop.sh" up core

stage "W01 up complete"
echo "Storefront: http://localhost:8080   Flags: http://localhost:8080/feature/"
