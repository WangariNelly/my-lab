#!/usr/bin/env bash
# AWS Budgets guard-rails for the course (run in the account that pays —
# the management/payer account sees consolidated spend for the whole org).
#
#   bash budget.sh                 # create/update "opslab-monthly" ($BUDGET_USD, alerts at 50/80/100 %)
#   bash budget.sh --test          # create "opslab-budget-test" ($1 limit, alert at 1 % actual) to prove alerting works
#   bash budget.sh --delete-test   # remove the test budget once the e-mail arrived
#
# Env: BUDGET_EMAIL (required), BUDGET_USD (default 50), AWS_PROFILE/AWS_REGION.
# Budgets are account-level guard-rails and are NOT torn down by `task down`.
set -euo pipefail

: "${BUDGET_EMAIL:?set BUDGET_EMAIL to the address that should receive alerts}"
BUDGET_USD="${BUDGET_USD:-50}"
account_id="$(aws sts get-caller-identity --query Account --output text)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

notification() { # threshold-percent type
  cat <<EOF
{"Notification":{"NotificationType":"$2","ComparisonOperator":"GREATER_THAN","Threshold":$1,"ThresholdType":"PERCENTAGE"},
 "Subscribers":[{"SubscriptionType":"EMAIL","Address":"$BUDGET_EMAIL"}]}
EOF
}

budget_exists() {
  aws budgets describe-budget --account-id "$account_id" --budget-name "$1" >/dev/null 2>&1
}

put_budget() { # name amount notifications-json
  local name="$1" amount="$2" notifs="$3"
  cat >"$tmp/budget.json" <<EOF
{"BudgetName":"$name","BudgetLimit":{"Amount":"$amount","Unit":"USD"},
 "TimeUnit":"MONTHLY","BudgetType":"COST",
 "CostTypes":{"IncludeCredit":false,"IncludeRefund":false}}
EOF
  printf '%s' "$notifs" >"$tmp/notifs.json"
  if budget_exists "$name"; then
    aws budgets update-budget --account-id "$account_id" --new-budget "file://$tmp/budget.json"
    echo "updated budget $name (limit \$$amount). Notifications are left as they are; delete and re-run to reset them."
  else
    aws budgets create-budget --account-id "$account_id" \
      --budget "file://$tmp/budget.json" \
      --notifications-with-subscribers "file://$tmp/notifs.json"
    echo "created budget $name (limit \$$amount) -> alerts to $BUDGET_EMAIL"
  fi
}

case "${1:-}" in
  "")
    notifs="[$(notification 50 ACTUAL),$(notification 80 ACTUAL),$(notification 100 ACTUAL),$(notification 100 FORECASTED)]"
    put_budget opslab-monthly "$BUDGET_USD" "$notifs"
    ;;
  --test)
    # Any spend over $0.01 this month crosses 1 % of $1. Budgets are evaluated
    # a few times a day, so the e-mail can take several hours to arrive.
    put_budget opslab-budget-test 1 "[$(notification 1 ACTUAL)]"
    ;;
  --delete-test)
    aws budgets delete-budget --account-id "$account_id" --budget-name opslab-budget-test
    echo "deleted opslab-budget-test"
    ;;
  *) sed -n '2,9p' "$0"; exit 2 ;;
esac

aws budgets describe-budgets --account-id "$account_id" \
  --query 'Budgets[].{name:BudgetName,limit:BudgetLimit.Amount,actual:CalculatedSpend.ActualSpend.Amount}' --output table
