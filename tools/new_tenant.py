#!/usr/bin/env python3
"""Self-service tenant onboarding.

Generates a guard-railed Kubernetes namespace for a team (quota, limits,
default-deny networking, edit access for the owner) and registers it with
k8s/tenants/kustomization.yaml. Argo CD deploys it once the PR merges.

Replaces the ticket-driven toil of "please create a namespace for my team".

Usage:
    python3 tools/new_tenant.py --team genomics --owner alice@example.com
    python3 tools/new_tenant.py --team imaging --owner bob@example.com --cpu 4 --memory 8Gi
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path
from string import Template

REPO_ROOT = Path(__file__).resolve().parent.parent
TENANTS_DIR = REPO_ROOT / "k8s" / "tenants"

# DNS-1123 label, minus the prefix we add, so "team-<name>" stays <= 63 chars.
TEAM_RE = re.compile(r"^[a-z]([a-z0-9-]{0,40}[a-z0-9])?$")
EMAIL_RE = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")
CPU_RE = re.compile(r"^\d+(\.\d+)?$|^\d+m$")
MEM_RE = re.compile(r"^\d+(Mi|Gi)$")

TEMPLATES: dict[str, str] = {
    "namespace.yaml": """\
apiVersion: v1
kind: Namespace
metadata:
  name: $ns
  labels:
    team: $team
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/warn: restricted
  annotations:
    platform/owner: $owner
""",
    "resourcequota.yaml": """\
apiVersion: v1
kind: ResourceQuota
metadata:
  name: team-quota
  namespace: $ns
spec:
  hard:
    requests.cpu: "$cpu"
    requests.memory: $memory
    limits.memory: $memory
    pods: "20"
    services.loadbalancers: "0"
""",
    "limitrange.yaml": """\
apiVersion: v1
kind: LimitRange
metadata:
  name: defaults
  namespace: $ns
spec:
  limits:
    - type: Container
      defaultRequest:
        cpu: 50m
        memory: 64Mi
      default:
        memory: 256Mi
""",
    "networkpolicy.yaml": """\
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-ingress
  namespace: $ns
spec:
  podSelector: {}
  policyTypes: ["Ingress"]
""",
    "rolebinding.yaml": """\
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: team-owner-edit
  namespace: $ns
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: edit
subjects:
  - apiGroup: rbac.authorization.k8s.io
    kind: User
    name: $owner
""",
}

KUSTOMIZATION_HEADER = """\
# Managed by tools/new_tenant.py. Do not edit by hand.
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
"""


def validate(args: argparse.Namespace) -> list[str]:
    errors = []
    if not TEAM_RE.match(args.team):
        errors.append(f"team {args.team!r} must be lowercase letters, digits and dashes (max 42 chars)")
    if not EMAIL_RE.match(args.owner):
        errors.append(f"owner {args.owner!r} is not an email address")
    if not CPU_RE.match(args.cpu):
        errors.append(f"cpu {args.cpu!r} must look like 2, 0.5 or 500m")
    if not MEM_RE.match(args.memory):
        errors.append(f"memory {args.memory!r} must look like 512Mi or 4Gi")
    return errors


def write_tenant(team: str, owner: str, cpu: str, memory: str, tenants_dir: Path) -> Path:
    tenant_dir = tenants_dir / team
    tenant_dir.mkdir(parents=True)
    values = {"ns": f"team-{team}", "team": team, "owner": owner, "cpu": cpu, "memory": memory}
    for filename, body in TEMPLATES.items():
        (tenant_dir / filename).write_text(Template(body).substitute(values))
    resources = "".join(f"  - {name}\n" for name in TEMPLATES)
    (tenant_dir / "kustomization.yaml").write_text(
        "apiVersion: kustomize.config.k8s.io/v1beta1\nkind: Kustomization\nresources:\n" + resources
    )
    return tenant_dir


def rebuild_index(tenants_dir: Path) -> list[str]:
    """Regenerate the tenants kustomization from the directories that exist."""
    teams = sorted(p.name for p in tenants_dir.iterdir() if p.is_dir())
    if teams:
        resources = "resources:\n" + "".join(f"  - {t}\n" for t in teams)
    else:
        resources = "resources: []\n"
    (tenants_dir / "kustomization.yaml").write_text(KUSTOMIZATION_HEADER + resources)
    return teams


def main(argv: list[str] | None = None, tenants_dir: Path = TENANTS_DIR) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--team", required=True, help="team name, e.g. genomics")
    parser.add_argument("--owner", required=True, help="Google identity email that gets edit access")
    parser.add_argument("--cpu", default="2", help="CPU request quota (default 2)")
    parser.add_argument("--memory", default="4Gi", help="memory quota (default 4Gi)")
    args = parser.parse_args(argv)

    errors = validate(args)
    if errors:
        for e in errors:
            print(f"error: {e}", file=sys.stderr)
        return 2

    if (tenants_dir / args.team).exists():
        print(f"error: tenant {args.team!r} already exists", file=sys.stderr)
        return 1

    path = write_tenant(args.team, args.owner, args.cpu, args.memory, tenants_dir)
    teams = rebuild_index(tenants_dir)
    print(f"created {path}")
    print(f"tenants now: {', '.join(teams)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
