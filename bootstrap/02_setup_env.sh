#!/usr/bin/env bash
# setup_env.sh: one-time script that sets up your local environment for this repo.
# Usage: ./bootstrap/setup_env.sh
# Run this after ./bootstrap/install_tools.sh, and after you have a Google Cloud account and billing set up.
# Run this script once per new machine, and once per new Google Cloud project.

set -euo pipefail

# Reuse the saved project if there is one; otherwise generate a new ID (must be globally unique, edit if taken).
# To start over with a new project, delete bootstrap/.project_id first.
source "$(dirname "$0")/00_env.sh"
if [[ -z "$PROJECT_ID" ]]; then
  export PROJECT_ID="vitals-lab-$(date +%m%d)"
fi
echo "$PROJECT_ID" > "$(dirname "$0")/.project_id"

gcloud auth login
gcloud auth application-default login            # credentials Terraform uses locally
if gcloud projects describe "$PROJECT_ID" >/dev/null 2>&1; then
  echo "Project $PROJECT_ID already exists, skipping create"
else
  gcloud projects create "$PROJECT_ID" --name="Vitals Lab"
fi

# Capture the billing account ID (open accounts only), e.g. XXXXXX-XXXXXX-XXXXXX
BILLING_ACCOUNTS=$(gcloud billing accounts list --filter="open=true" --format="value(name)" | sed 's|^billingAccounts/||')

if [[ -z "$BILLING_ACCOUNTS" ]]; then
  echo "No open billing accounts found. Set up billing in the Google Cloud console first." >&2
  exit 1
elif [[ $(wc -l <<< "$BILLING_ACCOUNTS") -gt 1 ]]; then
  gcloud billing accounts list --filter="open=true"
  read -r -p "Multiple billing accounts found. Enter the ACCOUNT_ID to use: " BILLING_ID
else
  BILLING_ID="$BILLING_ACCOUNTS"
fi
export BILLING_ID
echo "Using billing account: $BILLING_ID"

gcloud billing projects link "$PROJECT_ID" --billing-account="$BILLING_ID"
gcloud config set project "$PROJECT_ID"
