#!/usr/bin/env bash
# 03_add_budget_alert.sh: one-time script that adds a budget alert to your Google Cloud project.
# Usage: ./bootstrap/03_add_budget_alert.sh
# Run this after ./bootstrap/02_setup_env.sh, and after you have a Google Cloud account and billing set up.
# Run this script once per new machine, and once per new Google Cloud project.

set -euo pipefail

source "$(dirname "$0")/00_env.sh"
: "${PROJECT_ID:?No project set. Run 02_setup_env.sh first}"
: "${BILLING_ID:?No billing account linked to ${PROJECT_ID}}"

gcloud services enable billingbudgets.googleapis.com
gcloud billing budgets create --billing-account="$BILLING_ID" \
  --display-name="vitals-lab" --budget-amount=50USD \
  --threshold-rule=percent=0.5 --threshold-rule=percent=0.9 \
  --filter-projects="projects/$PROJECT_ID"