# Bootstrap scripts: a mentor's guide

These documents explain each script in [`bootstrap/`](../../bootstrap/). Read them in order, because the scripts depend on each other.

| Order | Script | Doc | One-line purpose |
|---|---|---|---|
| 0 | `00_env.sh` | [00_env.md](00_env.md) | Shared variables, sourced by the others (never run directly) |
| 1 | `01_install_tools.sh` | [01_install_tools.md](01_install_tools.md) | Install the CLI toolchain |
| 2 | `02_setup_env.sh` | [02_setup_env.md](02_setup_env.md) | Log in, create the GCP project, link billing |
| 3 | `03_add_budget_alert.sh` | [03_add_budget_alert.md](03_add_budget_alert.md) | $50 budget with 50%, 90% and 100% alerts |
| 4 | `04_bootstrap.sh` | [04_bootstrap.md](04_bootstrap.md) | Enable core APIs and create the Terraform state bucket |

## How the pieces connect

```
01 install tools
      |
02 login + create project + link billing --writes--> bootstrap/.project_id
      |                                                    |
03 budget alert        04 state bucket + APIs  <--reads-- 00_env.sh
                              |
                   cd terraform && terraform init
```

## Patterns that repeat across the scripts

- **`set -euo pipefail`** at the top of every executable script. Fail fast, don't continue on errors.
- **Check-then-create** (`describe` before `create`) to make scripts safe to re-run.
- **`: "${VAR:?message}"`** guard clauses so missing prerequisites fail with a clear message.
- **`${VAR:-default}`** layered defaults so any value can be overridden inline.
- **One source of truth** (`00_env.sh` and `.project_id`) instead of copy-pasted values.

## Fixed

- Header comments in `01`, `02` and `04` now use the numbered file names.
- `03` is idempotent (skips if the budget exists), has a 100% threshold, and takes `BUDGET_NAME` / `BUDGET_AMOUNT`.
- `ADMIN_CIDR` is empty, not `/32`, when the IP lookup fails.
- The state bucket expires noncurrent versions after 30 days.

## Still open

1. `00_env.sh` can pick up an unrelated active gcloud project, and `02` then saves it (see [02](02_setup_env.md)).
2. Tools are installed unpinned and globally (see [01](01_install_tools.md)).
