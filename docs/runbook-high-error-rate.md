# Runbook: Vitals API error budget burn

**Alert:** "Vitals API burning error budget" or "Vitals API unreachable"
**Severity:** page (fast burn) / ticket (slow burn)
**SLO:** 99.9% of `/api/v1/vitals` requests return non-5xx over 28 days (about 40 minutes of full outage)

## 1. Triage (first 5 minutes)
1. Acknowledge the alert and open an incident channel. Name an Incident Commander.
2. Open the **Vitals API** dashboard in Cloud Monitoring. Is the error ratio rising, flat, or falling?
3. What changed? Check the most recent commits:
   ```bash
   git log --oneline -10 -- k8s/ app/
   kubectl -n argocd get applications
   ```

## 2. Diagnose
```bash
kubectl -n vitals get pods,svc,hpa
kubectl -n vitals describe deploy vitals-api | sed -n '/Events/,$p'
kubectl -n vitals logs deploy/vitals-api --since=10m | grep '"severity":"ERROR"' | head
kubectl -n vitals get configmap -l app.kubernetes.io/part-of=vitals-platform -o yaml | grep FAIL_RATE
```
Logs Explorer query:
```
resource.type="k8s_container" resource.labels.namespace_name="vitals" severity>=ERROR
```

## 3. Mitigate (restore service first, root-cause later)
Roll back through Git so Argo CD and Git stay in agreement:
```bash
git revert <bad-commit-sha> --no-edit && git push
kubectl -n argocd get application vitals-dev -w   # wait for Synced / Healthy
```
Break-glass only (Argo CD will revert this unless you pause auto-sync first):
```bash
kubectl -n vitals rollout undo deploy/vitals-api
```

## 4. Verify and close
- Error ratio back under 0.1% on the dashboard for 15 minutes.
- Burn-rate alert auto-resolves.
- Open a postmortem from `docs/postmortem-template.md` within 48 hours.
