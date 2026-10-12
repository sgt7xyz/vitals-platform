# 03_add_budget_alert.sh: a safety net for your wallet

## What it is

A short script that creates a **budget with email alerts** on your billing account, scoped to this project. It's your early-warning system. A GKE cluster you forget to tear down can quietly cost real money, and this is what tells you. Run it right after `02_setup_env.sh`.

## Walkthrough

```bash
set -euo pipefail
source "$(dirname "$0")/00_env.sh"
: "${PROJECT_ID:?No project set. Run 02_setup_env.sh first}"
: "${BILLING_ID:?No billing account linked to ${PROJECT_ID}}"
```
The `: "${VAR:?message}"` idiom is a **guard clause**. The leading `:` is a no-op command, and `${VAR:?msg}` aborts the script with `msg` if the variable is unset or empty. It's a compact way to say "fail fast with a helpful message if prerequisites are missing." Here it tells you which earlier script to run.

```bash
gcloud services enable billingbudgets.googleapis.com
```
GCP APIs are off by default. The Budgets API must be enabled on the project before you can call it. Enabling an already-enabled API is a no-op.

```bash
gcloud billing budgets create --billing-account="$BILLING_ID" \
  --display-name="$BUDGET_NAME" --budget-amount="$BUDGET_AMOUNT" \
  --threshold-rule=percent=0.5 --threshold-rule=percent=0.9 --threshold-rule=percent=1.0 \
  --filter-projects="projects/$PROJECT_ID"
```
This runs only if no budget with that name exists yet (it lists existing budgets with `gcloud billing budgets list --format='value(displayName)'` and looks for an exact name match with `grep -qxF`), so re-runs are safe. The match is done with `grep` rather than gcloud's `--filter` because `--filter` prints a harmless but confusing `filter keys were not present in any resource : displayName` warning when the billing account has no budgets yet. `BUDGET_NAME` and `BUDGET_AMOUNT` default to `vitals-lab` and `50USD` and can be overridden inline.
- Budgets belong to the **billing account**, not the project, which is why `--billing-account` is needed.
- `--budget-amount`: $50 by default.
- Three `--threshold-rule`s: alert at **50% ($25)**, **90% ($45)** and **100% ($50)** of the budget.
- `--filter-projects`: only count spend from this project, not everything on the billing account.

## Things a mentor would flag

1. **A budget is an alert, not a cap.** GCP will happily keep charging past $50. The alerts only email billing admins. If you need a hard stop, you'd wire budget notifications to Pub/Sub and a Cloud Function that disables billing. Know the difference before you rely on this.
2. **Who gets the email?** With no notification channel specified, alerts go to the billing account's admins and users by default. That's fine for a personal account, but check that it reaches an inbox you read.
3. **Alerts lag.** Billing data is delayed by hours, so a runaway resource can cost more than $50 before the first email.

## Mental model

> Before you create anything that costs money, set up the thing that tells you when it's costing too much.
