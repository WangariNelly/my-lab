#!/usr/bin/env bash
# W01 teardown: stop the local shop. Budgets, the AWS Organization, Identity
# Center and the ServiceNow CMDB are permanent guard-rails/foundations and are
# deliberately left in place. W01 creates no AWS resources tagged module=W01,
# so `task verify-clean MODULE=W01` must report clean.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/../../.." && pwd)"

bash "$root/apps/shop/shop.sh" down
bash "$here/shell-check.sh" clean
echo "W01 down complete."
