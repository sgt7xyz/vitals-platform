# 04_bootstrap.sh: solve Terraform's chicken-and-egg problem

## What it is

Terraform needs two things to exist *before* it can do its job, and it can't create them for itself:

1. **A place to store its state file** (a GCS bucket).
2. **A few core APIs enabled**, so it can enable all the other APIs.

This script creates both with plain `gcloud`. That's the "bootstrap" problem: something has to exist before the automation can run, so you create it by hand (or script) once.

## Walkthrough

### Setup

```bash
set -euo pipefail
source "$(dirname "$0")/00_env.sh"
: "${PROJECT_ID:?No project set. Run 02_setup_env.sh first}"
STATE_BUCKET="${STATE_BUCKET:-${PROJECT_ID}-tfstate}"
log() { printf '\n==> %s\n' "$*"; }
```
Strict mode, shared config, and a guard clause (see [03](03_add_budget_alert.md) for how `:?` works). The bucket name defaults to `<project-id>-tfstate`. Bucket names are globally unique across all of GCS, and prefixing with the globally unique project ID makes a collision unlikely. `log` is a tiny helper that prints readable `==>` section headers.

### Point gcloud at the project

```bash
gcloud config set project "${PROJECT_ID}" >/dev/null
```
Makes sure every following command targets the right project, even if your gcloud default had drifted.

### Enable the bootstrap APIs

```bash
gcloud services enable serviceusage... cloudresourcemanager... iam... storage...
```
| API | Why |
|---|---|
| serviceusage | lets Terraform enable *other* APIs. This is the key chicken-and-egg API. |
| cloudresourcemanager | project-level operations and IAM bindings |
| iam | create service accounts and roles |
| storage | the state bucket itself |

Enabling is idempotent, so re-runs are fine.

### Create the state bucket, only if missing

```bash
if gcloud storage buckets describe "gs://${STATE_BUCKET}" ... ; then skip
else gcloud storage buckets create ... \
  --location="${REGION}" --uniform-bucket-level-access --public-access-prevention
```
Same check-then-create pattern as `02`. The flags matter:
- `--location=$REGION`: a regional bucket, matching your other resources.
- `--uniform-bucket-level-access`: permissions are controlled only by IAM, with no legacy per-object ACLs. Easier to reason about and audit.
- `--public-access-prevention`: the bucket can never be made public, even by accident. State files can contain secrets, so this is non-negotiable.

### Turn on versioning

```bash
gcloud storage buckets update "gs://${STATE_BUCKET}" --versioning
```
Every overwrite of the state file keeps the old version. If a bad `apply` corrupts state, you can roll back. It runs outside the `if`, so it's applied on every run, which is fine.

### Expire old state versions

A lifecycle rule (written to a temp file and applied with `--lifecycle-file`) deletes noncurrent versions 30 days after they are replaced. Rollback stays possible for a month, and old versions don't pile up forever.

### Print next steps

The heredoc tells you the bucket name and the exact next command:
`cd terraform && terraform init -backend-config="bucket=${STATE_BUCKET}"`.

## Why remote state at all?

A local `terraform.tfstate` lives on one laptop, can be lost, can't be shared, and has no locking. A GCS backend gives you durability, a shared source of truth, and state locking so two applies can't collide. That's also why `*.tfstate` is in `.gitignore`: state must never go in git.

## Things a mentor would flag

1. **The bucket is outside Terraform's management.** That's by design, but it means deleting the project or bucket is manual and you must not `terraform destroy` your way into your own state.
2. **`--backend-config="bucket=..."` assumes a partial backend block** in `terraform/` (a `backend "gcs" {}` with no bucket set). I haven't checked that file, so confirm it matches.
3. **The bucket name embeds the project ID**, and the project ID is date-based. A new project means a new bucket and fresh state, which is probably what you want, but remember the old one still exists.
4. **No `prefix` for state in the output.** If you later have several environments, use separate prefixes (or buckets) so they don't share a state file.
5. **Run order.** This must come after `02` (project and billing) and needs your ADC login. It does not depend on `03`, but `03` first is wise.
6. **Cost.** A tiny state bucket costs pennies, so this is the cheap part.

## Mental model

> Every automation has a seed it can't plant itself. Keep the seed small, scripted, idempotent and boring, then hand everything else to Terraform.
