# vitals-platform

A small, production-shaped GCP platform built as interview prep for the Verily Cloud Engineer III role.
It deploys a Go API that serves synthetic patient vitals onto a private GKE cluster, using
Terraform, GitHub Actions with keyless auth, Argo CD GitOps, Managed Prometheus SLOs, and
HIPAA-style controls (CMEK, audit logs, least privilege).

| Path | What it is |
|---|---|
| `bootstrap/` | One-time, idempotent setup: tools, GCP project and billing, budget alert, state bucket and base APIs |
| `terraform/` | VPC, Cloud NAT, private GKE, Artifact Registry, KMS + PHI bucket, audit logs, WIF, SLO and alerts |
| `app/` | Go service with hand-rolled Prometheus metrics and a `FAIL_RATE` game-day knob |
| `k8s/` | Kustomize base + dev overlay, tenants, toolbox |
| `argocd/` | App-of-apps |
| `.github/workflows/` | Terraform plan/apply, app build/scan/push/bump, self-service tenant PRs |
| `tools/` | `new_tenant.py` and its tests |
| `docs/` | Design doc, runbook, postmortem template |

## Bootstrap

Run once, in order, on a new machine or a new GCP project:

```bash
./bootstrap/01_install_tools.sh      # mise-managed CLIs, plus the gcloud SDK and Docker via brew
./bootstrap/02_setup_env.sh          # creates (or reuses) the GCP project, links billing
./bootstrap/03_add_budget_alert.sh   # $50 budget alert at 50% and 90%
./bootstrap/05_bootstrap.sh          # Terraform state bucket and the APIs Terraform needs first
```

`02_setup_env.sh` writes the project ID to `bootstrap/.project_id` (gitignored), so every later
script, and every later terminal, picks it back up automatically. Each script is safe to re-run:
an existing project, bucket, or billing link is detected and skipped rather than recreated.
`bootstrap/00_env.sh` holds the shared variables (`PROJECT_ID`, `REGION`, `ZONE`, `GH_USER`,
`ADMIN_CIDR`, `BILLING_ID`) and is meant to be sourced, not run directly; every script above
sources it. In a fresh terminal, `source bootstrap/00_env.sh` restores those variables without
rerunning any setup.

Quick checks that need no cloud account:
```bash
(cd app && go test -race ./...)
python3 tools/test_new_tenant.py
kubectl kustomize k8s/overlays/dev | head
```

Teardown: delete the `root` Application, then `vitals-dev`, `toolbox` and `tenants` (their finalizers remove the load balancer), then `terraform destroy`.
