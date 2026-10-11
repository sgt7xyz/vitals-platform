# 00_env.sh: the shared config for the bootstrap scripts

## What it is

`bootstrap/00_env.sh` is a sourced library, not a program. The `00_` prefix makes it sort first and tells you to read it first. Every later script runs `source 00_env.sh` and gets the same variables. That way the project ID, region and similar values live in one place instead of being copy-pasted and drifting apart.

You can also run `source ./bootstrap/00_env.sh` in your own terminal to get the same variables for ad-hoc `gcloud` or `terraform` commands.

## The core pattern: layered defaults

Almost every line follows this shape:

```bash
export REGION="${REGION:-us-east1}"
```

`${VAR:-default}` means "use `$VAR` if it's set and non-empty, otherwise use the default." You can override anything at call time without editing the file:

```bash
REGION=us-central1 ./bootstrap/04_bootstrap.sh
```

The precedence order is: **caller's environment, then a saved value, then an auto-detected value or hardcoded default.** That makes the file predictable and safe to re-run.

## Line by line

**`PROJECT_ID` from a saved file**
- `${BASH_SOURCE[0]:-$0}` is the path of *this* file even when it's sourced. Plain `$0` would give you the caller's name. `dirname` of that finds the `.project_id` file next to it.
- `[[ -z "${PROJECT_ID:-}" && -s file ]]` means: only read the file if the caller didn't already set `PROJECT_ID`, and the file exists and is non-empty (`-s`).
- `$(<file)` is a bash builtin way to read a file without spawning `cat`.
- `02_setup_env.sh` writes the file, so your project ID survives across days and shells. Without it you'd depend on whatever `gcloud config` is set to, which is a classic way to run commands against the wrong project.

**The fallback to gcloud**
`gcloud config get-value project` is the last resort. `2>/dev/null || true` silences errors and keeps the script from dying if gcloud isn't configured yet.

**Region and zone**
Hardcoded defaults (`us-east1`, `us-east1-b`), overridable. Keep region and zone consistent. Cross-region traffic costs money and adds latency.

**`GH_USER`**
Asks the GitHub CLI who you're logged in as. Falls back to empty if `gh` isn't authenticated.

**`ADMIN_CIDR`**
Looks up your public IPv4 (`curl -4 ifconfig.me`, 5 second timeout) and appends `/32`, meaning exactly one address. If the lookup fails it stays empty, so `-z "$ADMIN_CIDR"` checks work. This is the kind of value you use to allowlist your IP on the GKE API server (master authorized networks) or a firewall rule, so only you can reach the admin endpoint.

**`BILLING_ID`**
If the project exists, it asks GCP which billing account is linked and strips the `billingAccounts/` prefix with `sed`. It stays empty until `02_setup_env.sh` has linked one. The last line guarantees the variable is always *defined*, even if empty, which matters for scripts running with `set -u`.

## Things a mentor would flag

1. **Network calls on every `source`.** It shells out to `gcloud`, `gh` and `curl` each time. That's slow, and failures are swallowed by `|| true`, so a broken lookup gives you an empty variable, not an error.
2. **`ifconfig.me` is a third-party dependency, and your IP changes** (home ISP, VPN). An allowlist built from it goes stale. Re-source and re-apply when it does.
3. **Dynamic IP allowlisting is a security decision.** Make sure whatever consumes `ADMIN_CIDR` never falls back to `0.0.0.0/0`.
4. **`.project_id` is gitignored.** Verified: `bootstrap/.project_id` is in `.gitignore`. Good, since it's local state.
5. **No `set -euo pipefail` here, and that's correct.** A sourced file that sets `-e` changes your *interactive shell's* behavior and can close your terminal on the first error. Strict mode belongs in the scripts that source it.
6. **`PROJECT_ID` can silently pick up the wrong project.** On a first run with no `.project_id`, the gcloud fallback falls back to whatever project gcloud currently has active. See the matching warning in [02_setup_env.md](02_setup_env.md).

## Mental model

> Resolve environment-specific facts once, in one place, with sane precedence, and let everything else just read variables.
