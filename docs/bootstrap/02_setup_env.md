# 02_setup_env.sh: create the GCP project and link billing

## What it is

The script that turns "I have a Google account" into "I have a GCP project with billing attached, and my local tools point at it." Run it once per machine and once per new project, after `01_install_tools.sh`. It is **interactive**: it opens browser logins and may prompt you.

## Walkthrough

### Resolve the project ID

```bash
source "$(dirname "$0")/00_env.sh"
if [[ -z "$PROJECT_ID" ]]; then
  export PROJECT_ID="vitals-lab-$(date +%m%d)"
fi
echo "$PROJECT_ID" > "$(dirname "$0")/.project_id"
```
It loads the shared config first. If that produced a project ID (from your environment, the saved file, or gcloud), it reuses it. Otherwise it invents one like `vitals-lab-1009` from today's month and day. Then it **writes the ID to `bootstrap/.project_id`**, which `00_env.sh` reads in every later script. This is how state carries across scripts and days. The comment says to delete that file to start over with a new project.

GCP project IDs are globally unique across all of Google, so the generated name can collide. The comment tells you to edit it if taken.

### Authenticate

```bash
gcloud auth login
gcloud auth application-default login
```
These are two separate credentials, and mixing them up is a classic confusion:
- `auth login` authenticates the **gcloud CLI** (what you type in the terminal).
- `auth application-default login` creates **Application Default Credentials (ADC)**, the file that libraries and tools like **Terraform** use. The comment on that line says so.

### Create the project, idempotently

```bash
if gcloud projects describe "$PROJECT_ID" >/dev/null 2>&1; then ... skip
else gcloud projects create ...
```
The check-then-create pattern. If `describe` succeeds, the project exists and it skips. This is what makes a re-run safe.

### Find a billing account

It lists open billing accounts and strips the `billingAccounts/` prefix. Then there are three cases:
- **None:** print an error to stderr and `exit 1`. You must set up billing in the console first.
- **More than one:** show them and `read` your choice.
- **Exactly one:** use it automatically.

`wc -l <<< "$BILLING_ACCOUNTS"` counts lines using a here-string.

### Link and set defaults

```bash
gcloud billing projects link "$PROJECT_ID" --billing-account="$BILLING_ID"
gcloud config set project "$PROJECT_ID"
```
Billing must be linked before most APIs can be enabled. The last line makes `gcloud` default to this project. Linking an already-linked project is harmless.

## Things a mentor would flag

1. **The wrong-project trap.** `00_env.sh` falls back to gcloud's currently active project. On a first run with no `.project_id`, if gcloud is already pointed at some *other* project, this script treats that as yours and **saves it to `.project_id`**. The "generate a new ID" branch is only reached when gcloud has no project at all. If you want a fresh project, check `gcloud config get-value project` first, or set `PROJECT_ID=...` inline.
2. **The project ID is date-based.** `vitals-lab-1008` was saved yesterday, and today the generator would say `1009`. Because of `.project_id`, it keeps reusing `1008`. That's the intended behavior, but it can surprise you.
3. **It always logs in again.** Both `gcloud auth` commands run every time, even when you're already authenticated, so it's annoying on re-runs. You could guard them with `gcloud auth list`.
4. **Billing selection ignores `BILLING_ID` from the environment.** Even if you pass `BILLING_ID=...`, line 26 recomputes and may prompt. It also isn't non-interactive-friendly (for CI you'd want flags).
5. **Org policy and permissions.** `projects create` fails in some Workspace organizations unless you have the Project Creator role. Personal Gmail accounts are generally fine.
6. **Billing is where money starts.** Run `03_add_budget_alert.sh` immediately after.

## Mental model

> Establish identity (who am I), a container (project), and a payment method (billing), then record the answer so every other script agrees.
