#!/usr/bin/env bash
# 00_env.sh: shared variables for the bootstrap scripts. Sourced by them, not run directly.
# Usage: source "$(dirname "$0")/00_env.sh"
# PROJECT_ID comes from, in order: the caller's environment, the saved bootstrap/.project_id file
# (written by 02_setup_env.sh), then the active gcloud project. That keeps it stable across days.
# To use these in your own shell: source ./bootstrap/00_env.sh

_saved_project_file="$(dirname "${BASH_SOURCE[0]:-$0}")/.project_id"
if [[ -z "${PROJECT_ID:-}" && -s "$_saved_project_file" ]]; then
  PROJECT_ID="$(<"$_saved_project_file")"
fi
export PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project 2>/dev/null || true)}"
export REGION="${REGION:-us-east1}"
export ZONE="${ZONE:-us-east1-b}"
export GH_USER="${GH_USER:-$(gh api user -q .login 2>/dev/null || true)}"
export ADMIN_CIDR="${ADMIN_CIDR:-$(curl -s -4 ifconfig.me 2>/dev/null)/32}"

# Billing account linked to the project; empty until 02_setup_env.sh has linked one.
if [[ -z "${BILLING_ID:-}" && -n "$PROJECT_ID" ]]; then
  BILLING_ID="$(gcloud billing projects describe "$PROJECT_ID" --format='value(billingAccountName)' 2>/dev/null | sed 's|^billingAccounts/||' || true)"
fi
export BILLING_ID="${BILLING_ID:-}"
