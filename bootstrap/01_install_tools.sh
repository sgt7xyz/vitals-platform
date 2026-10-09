#!/usr/bin/env bash
# install_tools.sh: one-time script that installs the tools needed to run this repo.
# Usage: ./bootstrap/install_tools.sh
set -euo pipefail

# version-managed CLIs, through mise
mise use -g go terraform kubectl gh kustomize jq
mise use -g aqua:bridgecrewio/checkov

# the two things mise doesn't cleanly manage: the gcloud SDK bundle and Docker
brew install --cask google-cloud-sdk
gcloud components install gke-gcloud-auth-plugin
# Docker: Docker Desktop, OrbStack, or colima, whichever you already run

mise doctor
terraform -version && kubectl version --client && go version && gh --version && checkov --version