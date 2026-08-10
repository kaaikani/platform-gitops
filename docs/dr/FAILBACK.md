# Fail-back — returning from ap-south-2 to Mumbai

**Status: OUTLINE, never drilled.** Fail-back is LESS urgent than failover
(the business is running in Hyderabad; Mumbai's return can wait days) but
MORE dangerous (two databases have diverged; pick wrong and you lose the
orders taken during the outage). Do not improvise this — slow is safe.

## Principles

1. **No hurry.** DR region serving = business alive. Fail-back on a quiet
   weekday night, planned, with this doc open.
2. **The DR database is now the truth.** Every order taken during the outage
   exists ONLY in Hyderabad. Mumbai's old database is HISTORY, not truth.
3. One-way traffic switch, again: no mixed-mode.

## Sequence (draft — refine before first use)

1. Confirm ap-south-1 healthy ≥ 24h (AWS status + spot checks).
2. Rebuild Mumbai stack if needed (same terraform that built prod; the
   cluster may have survived the outage — assess, don't assume).
3. **Data return — the dangerous step:**
   `mysqldump` the DR database (maintenance window, storefronts read-only)
   → restore into a FRESH Mumbai RDS instance → verify row counts + latest
   orders match. Never restore over the old instance; keep it as evidence.
4. Point Mumbai's secrets (DB_HOST) at the fresh instance; sync apps via
   ArgoCD; verify health + test order in Mumbai.
5. DNS: flip `active_alb_dns_name` back to the Mumbai ALB. 5-min TTL wait.
6. Watch prod dashboards 1h. Then:
   - re-enable RDS backup replication ap-south-1 → ap-south-2 (it broke when
     the source died)
   - re-verify secret replicas InSync, ECR replication, S3 CRR (S3 CRR
     survives; RDS replication must be re-created)
   - `terraform destroy` in live/aws-dr
7. Post-mortem within 48h: what did the outage cost, what did the runbook
   miss, what does the next drill need.

## Known unknowns (answer during the first fail-back drill)

- Exact downtime during the dump/restore cut-over (estimate: 15-45 min at
  current DB size; grows with data)
- Whether Delivery-partner/GK EC2s failed back by re-restore or were never
  failed over (their DR story is restore-on-demand, likely still in Mumbai
  unless the outage killed them)
- SES: switch sending back from ap-southeast-1 to ap-south-1 (secret change)
