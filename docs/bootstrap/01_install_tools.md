# 01_install_tools.sh: install the toolchain

## What it is

A one-time, per-machine script that installs every CLI the rest of the repo needs. It's step zero: nothing else works until these tools exist. Run it as `./bootstrap/01_install_tools.sh`.

## Walkthrough

```bash
set -euo pipefail
```
Strict mode. `-e` exits on the first failed command, `-u` errors on unset variables, `-o pipefail` makes a pipeline fail if any stage fails. Standard opening for any script that *runs* things (as opposed to `00_env.sh`, which is sourced).

```bash
mise use -g go terraform kubectl gh kustomize jq
mise use -g aqua:bridgecrewio/checkov
```
[mise](https://mise.jdx.dev) is a version manager for dev tools (like asdf, but faster). `use -g` installs the tool *and* pins it in your **global** config (`~/.config/mise/config.toml`). What you get:

| Tool | Why this repo needs it |
|---|---|
| go | the app in `app/` |
| terraform | infrastructure in `terraform/` |
| kubectl, kustomize | working with the cluster and `k8s/` manifests |
| gh | GitHub CLI (used by `00_env.sh` to get `GH_USER`) |
| jq | JSON wrangling in shell |
| checkov | static security scanning of Terraform/K8s (installed through the `aqua` backend since it's a Python tool) |

```bash
brew install --cask google-cloud-sdk
gcloud components install gke-gcloud-auth-plugin
```
Two things mise doesn't manage well. The gcloud SDK is a big self-updating bundle, so it comes from Homebrew. `gke-gcloud-auth-plugin` is required by modern `kubectl` to authenticate to GKE. Without it, `kubectl` against a GKE cluster fails with an auth-plugin error.

The Docker line is only a comment. You bring your own runtime (Docker Desktop, OrbStack or colima).

```bash
mise doctor
terraform -version && kubectl version --client && go version && gh --version && checkov --version
```
A smoke test. If any tool isn't on the `PATH`, the script fails loudly here, not three scripts later.

## Things a mentor would flag

1. **Effectively macOS only.** Casks were historically macOS-only, and most still are. Recent Homebrew versions let a cask declare Linux support, but `google-cloud-sdk` is not guaranteed to be one of them, so `brew install --cask` may fail or be skipped on Linux. Fine for a personal lab, but note it in the README.
2. **Global pinning, no version numbers.** `mise use -g terraform` takes the latest and applies it to every project on your machine. For a team repo you'd commit a `.mise.toml` or `.tool-versions` with exact versions, so everyone (and CI) runs the same Terraform. Version drift is a common cause of "works on my machine."
3. **Not fully idempotent.** `brew install` on an already-installed cask will warn or error depending on the version, and with `set -e` that would stop the script. Re-running is mostly safe, but not guaranteed.
4. **mise must already be installed**, and so must Homebrew. The script doesn't check for either.

## Mental model

> Make the dev environment reproducible. A new laptop should be one command away from working.
