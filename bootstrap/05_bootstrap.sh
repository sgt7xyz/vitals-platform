#!/usr/bin/env bash
# bootstrap.sh: one-time setup that Terraform cannot do for itself.
# Creates the remote-state bucket and enables the APIs Terraform needs to enable the rest.
# Usage: ./bootstrap/05_bootstrap.sh   (PROJECT_ID and REGION come from 00_env.sh; override by setting them inline)
set -euo pipefail

source "$(dirname "$0")/00_env.sh"
: "${PROJECT_ID:?No project set. Run 02_setup_env.sh first}"
STATE_BUCKET="${STATE_BUCKET:-${PROJECT_ID}-tfstate}"

log() { printf '\n==> %s\n' "$*"; }

log "Pointing gcloud at ${PROJECT_ID}"
gcloud config set project "${PROJECT_ID}" >/dev/null

log "Enabling the APIs Terraform needs before it can manage other APIs"
gcloud services enable \
  serviceusage.googleapis.com \
  cloudresourcemanager.googleapis.com \
  iam.googleapis.com \
  storage.googleapis.com

if gcloud storage buckets describe "gs://${STATE_BUCKET}" >/dev/null 2>&1; then
  log "State bucket gs://${STATE_BUCKET} already exists, skipping"
else
  log "Creating state bucket gs://${STATE_BUCKET}"
  gcloud storage buckets create "gs://${STATE_BUCKET}" \
    --location="${REGION}" \
    --uniform-bucket-level-access \
    --public-access-prevention
fi

log "Turning on object versioning so every state write can be rolled back"
gcloud storage buckets update "gs://${STATE_BUCKET}" --versioning

cat <<EOF

Bootstrap complete.
  State bucket : gs://${STATE_BUCKET}
  Next step    : cd terraform && terraform init -backend-config="bucket=${STATE_BUCKET}"
EOF
