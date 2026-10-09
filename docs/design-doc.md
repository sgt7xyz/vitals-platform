# Design: Vitals Platform (dev)

**Author:** Steven Tardonia  **Status:** Implemented (lab)  **Last updated:** YYYY-MM-DD

## 1. Context
Product teams handling health data need a paved road to run containerized services on GCP
that is secure by default, observable, and compliant with HIPAA safeguards, without each
team re-solving networking, identity, CI/CD, and monitoring.

## 2. Goals
- Every piece of infrastructure is declared in Terraform and changed through pull requests.
- No long-lived credentials: CI uses Workload Identity Federation, pods use Workload Identity.
- Deployments are GitOps: Git is the source of truth, Argo CD reconciles, rollback is `git revert`.
- The API has a 99.9% availability SLO with burn-rate alerting and a runbook.
- Teams onboard themselves (namespace, quota, RBAC) through a self-service workflow.

## 3. Non-goals
- Multi-region active/active (see DR section for the path there).
- Real PHI. The lab uses synthetic records only.

## 4. Architecture
```
GitHub (PR) ──► Actions: checkov, terraform plan ──merge──► terraform apply ──► GCP
     │                                                                          │
     └─ app/ change ─► test, build, trivy, push to Artifact Registry            │
                          └─ commit new tag to k8s/overlays/dev                 │
                                                                                ▼
 Argo CD (in cluster) pulls k8s/ ─► GKE private cluster (Dataplane V2, Workload Identity)
                                       ├─ ns vitals: Deployment, HPA, PDB, NetworkPolicy
                                       ├─ ns team-*: self-service tenants
                                       └─ Managed Prometheus ─► Cloud Monitoring SLO + alerts
```

| Concern | Choice | Why |
|---|---|---|
| Compute | GKE Standard, zonal, private nodes, spot pool | Teaches node-level ops (CKA); Autopilot is the production default for most teams |
| Network | Custom VPC, secondary ranges, Cloud NAT, logged deny-all | No public node IPs; egress is centralized and auditable |
| Identity | WIF for CI, Workload Identity for pods, dedicated node SA | Removes key sprawl, the top GCP credential-leak cause |
| Delivery | GitHub Actions for CI, Argo CD for CD | CI never holds cluster credentials; drift is auto-corrected |
| Data protection | CMEK (90-day rotation), uniform access, PAP enforced, Data Access audit logs | Maps to HIPAA §164.312 encryption and audit controls |
| Observability | Managed Prometheus, uptime check, request-based SLO, multi-window burn-rate alerts | Pages on user impact, not on CPU |

## 5. Security and compliance
- **Least privilege:** node SA has five monitoring/logging/registry roles; image builder can only push to one repository.
- **Guardrails in Git:** Pod Security Admission `restricted`, default-deny NetworkPolicy, Checkov in CI.
- **Supply chain:** immutable image tags, distroless runtime, Trivy gate before push.
- **Known gap:** Terraform CI identity is broad. Next step: separate plan (viewer) and apply (main branch only) identities, plus VPC Service Controls around the PHI bucket and Binary Authorization on GKE.

## 6. Reliability
- SLO 99.9% over 28 days, error budget about 40 minutes.
- Fast burn 14.4x over 1 hour and slow burn 6x over 6 hours page on-call.
- PDB and `maxUnavailable: 0` keep capacity through upgrades and spot preemption.

## 7. Disaster recovery
| Scenario | Recovery | RTO / RPO |
|---|---|---|
| Namespace or workload deleted | Argo CD self-heal recreates from Git | minutes / 0 |
| Cluster lost | `terraform apply` + re-bootstrap Argo CD | about 30 min / 0 for stateless |
| Bad state write | GCS object versioning on the state bucket | minutes / last version |
| Region outage | Not covered in dev. Path: second regional cluster + multi-cluster gateway | n/a |

## 8. Alternatives considered
- **Atlantis or Terraform Cloud instead of Actions for Terraform:** better locking UX and PR-driven apply; adds a server to run. Config included as `atlantis.yaml`.
- **Cloud Deploy instead of Argo CD:** managed, but push-based and GCP-only.
- **GKE Autopilot:** less to operate; chosen against here only to practice node-level skills.

## 9. Rollout and open questions
- Who approves tenant PRs, and what default quota fits a typical team?
- Should production require a manual approval on the Terraform `apply` environment?
