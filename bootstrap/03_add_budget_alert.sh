#!/usr/bin/env bash
# 03_add_budget_alert.sh: one-time script that adds a budget alert to your Google Cloud project.
# Usage: ./bootstrap/03_add_budget_alert.sh   (override inline: BUDGET_AMOUNT=100USD BUDGET_NAME=my-budget ...)
# Run this after ./bootstrap/02_setup_env.sh, and after you have a Google Cloud account and billing set up.
# Run this script once per new Google Cloud project. Safe to re-run: it skips if the budget already exists.
# A budget only sends alerts. It does not stop spending.

set -euo pipefail

source "$(dirname "$0")/00_env.sh"
: "${PROJECT_ID:?No project set. Run 02_setup_env.sh first}"
: "${BILLING_ID:?No billing account linked to ${PROJECT_ID}}"
BUDGET_NAME="${BUDGET_NAME:-vitals-lab}"
BUDGET_AMOUNT="${BUDGET_AMOUNT:-50USD}"

gcloud services enable billingbudgets.googleapis.com

if [[ -n "$(gcloud billing budgets list --billing-account="$BILLING_ID" \
      --filter="displayName=${BUDGET_NAME}" --format='value(name)')" ]]; then
  echo "Budget ${BUDGET_NAME} already exists on ${BILLING_ID}, skipping"
else
  gcloud billing budgets create --billing-account="$BILLING_ID" \
    --display-name="$BUDGET_NAME" --budget-amount="$BUDGET_AMOUNT" \
    --threshold-rule=percent=0.5 --threshold-rule=percent=0.9 --threshold-rule=percent=1.0 \
    --filter-projects="projects/$PROJECT_ID"
fi
