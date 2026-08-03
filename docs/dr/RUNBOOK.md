# DR Runbook — ap-south-1 regional failover → ap-south-2

**Targets:** RTO 45–90 min · RPO 15–30 min
**Last drill:** #1 on 2026-08-01 — **CORE PATH ONLY** (infra + DB restore + vendure API/worker).
Measured: first-run RTO 1h55m including 14 live-debugged findings; clean-run estimate 40–50 min.
**NOT yet drilled:** ALB/HTTPS ingress, storefronts, vendure-client, DNS flip, EC2 restore,
ArgoCD bootstrap, monitoring. Until drill #2 covers those, "we have DR" means the DATA and the
CORE APP — a customer could not yet reach the site. Do not overclaim.

## Drill #1 results (2026-08-01)

Proven: VPC/EKS/nodegroup/addons/IRSA build in ap-south-2 · RDS restore from replicated
backup (674 products, real order history) · secrets replicas + drill isolation (5/5 checks,
MSG91/SES untouched) · vendure server ×2 + worker + in-cluster redis · /health 200 + live
shop-api queries. Timeline: 14:30 start → 16:25 serving → 16:29 teardown start → 16:46 gone.

Findings (all fixed in code/runbook same day):
1. ACM regional — certs now PRE-ISSUED in ap-south-2 (dr_acm.tf)
2. EKS Auto-Mode API requires compute+storage+elasticLoadBalancing together
3. Interrupted apply orphans in-flight RDS restore → import + ignore_changes
4. final_snapshot_identifier required when skip_final_snapshot=false
5. **t3a family does not exist in ap-south-2** → DR uses t3
6. kubectl context defaults to prod → every DR command uses --context dr
7. **DR ECR was EMPTY** — replication only copies new pushes; all 6 repos backfilled;
   verify non-empty in the monthly readiness check
8. bootstrap_self_managed_addons=false + addons-after-nodegroup = CNI deadlock →
   vpc-cni/kube-proxy install BEFORE the node group (aws_eks_addon.boot)
9. Default gp2 StorageClass is legacy in-tree → PVCs hang; CSI SC needed (drill #2)
10. ClusterSecretStore `aws-secrets-manager` is cluster-scoped, chart doesn't create it →
    manifest now in this runbook (step 4a)
11. PriorityClasses (`vendure-critical`) required before any pod schedules →
    `kubectl apply -f cluster-config/priority-classes.yaml`
12. **Chart bug:** worker `replicaCount|default 1` — 0 is impossible via values;
    scale imperatively BEFORE unblocking pod creation
13. Prod values nodeSelector `node-group: vendure` → label DR nodes:
    `kubectl --context dr label nodes --all node-group=vendure`
14. ACM validation tokens are per-account-per-domain — existing prod CNAMEs validated
    the DR certs instantly; no new records needed (Cloudflare 81053 if you try)

Monthly DR readiness check (5 min): DR ECR repos non-empty · secret replicas InSync ·
RDS backup replication `replicating` · EC2 vault has a recovery point in ap-south-2 ·
DR cert status ISSUED.

---

## 0. Decide (human gate — never automated)

DB promotion is irreversible and split-brain is worse than downtime. Confirm ALL three before proceeding:

- [ ] ap-south-1 impact confirmed on https://health.aws.amazon.com/health/status — not just our cluster misbehaving
- [ ] Outage ongoing > 30 min with no AWS ETA, or AWS declares multi-hour impact
- [ ] You accept losing writes since the last replicated backup (RPO window)

If ap-south-1 API still answers, snapshot what you can first. **Say out loud: "we are failing over, writes to Mumbai are dead to us from now."** Mixed-mode (some traffic Mumbai, some Hyderabad) is forbidden.

## 1. State access

```bash
cd terraform/live/aws-dr
terraform init                      # normal path (Mumbai bucket up)
# Mumbai S3 down? Use the replica:
terraform init -reconfigure \
  -backend-config="bucket=kaaikani-tfstate-dr-149536454380" \
  -backend-config="region=ap-south-2"
```

## 2. Build the platform (~25 min)

```bash
BACKUP_ARN=$(aws rds describe-db-instance-automated-backups --region ap-south-2 \
  --query 'DBInstanceAutomatedBackups[0].DBInstanceAutomatedBackupsArn' --output text)

terraform apply -var "replicated_backup_arn=$BACKUP_ARN"
# Corruption event (not region loss)? Add:
#   -var restore_use_latest=false -var restore_time=2026-XX-XXTXX:XX:XXZ

aws eks update-kubeconfig --region ap-south-2 --name vendure-dr-cluster
```

EKS ~12 min and RDS restore ~15–20 min run in parallel.

## 3. Bootstrap ArgoCD (the installer robot died with Mumbai)

```bash
kubectl create namespace argocd
helm repo add argo https://argoproj.github.io/argo-helm
helm install argocd argo/argo-cd -n argocd --set configs.params."server\.insecure"=true
kubectl -n argocd apply -f argocd/            # app-of-apps from this repo
```

## 4. Point the platform at DR resources

**4a. Secrets** — replicas already exist in ap-south-2 (verified InSync). Two changes:
- ClusterSecretStore/SecretStore: `region: ap-south-2`
- Update `vendure/prod/database` secret's `DB_HOST` to the restored endpoint:
  `terraform output rds_address`
  ⚠️ Update the **ap-south-2 replica is read-only** — promote the replica secret first:
  ```bash
  aws secretsmanager stop-replication-to-replica --secret-id vendure/prod/database --region ap-south-2  # NO —
  ```
  **Correction (verify in first drill):** replica secrets must be promoted to standalone before they accept writes:
  `aws secretsmanager ... remove-regions-from-replication` on the primary is impossible if Mumbai is down; instead the replica in ap-south-2 can be **promoted** via `PromoteReplicaToPrimary` (console: "Promote to standalone secret"). Drill must nail this exact sequence.

**4b. ServiceAccount role ARNs** — annotate with DR roles (`terraform output irsa_role_arns`):
ALB controller, external-secrets, ebs-csi, both vendure apps.

**4c. Image registry** — values overlays: `imageRegistry: 149536454380.dkr.ecr.ap-south-2.amazonaws.com/`
(Kyverno already admits both regions' registries.)

**4d. StorageClass** — monitoring PVCs provision fresh (history accepted-loss).

## 5. Verify before DNS

- [ ] `kubectl get pods -A` — vendure server+worker Running, storefronts Running
- [ ] Vendure `/health` returns 200 via port-forward
- [ ] Test order placement against the DR DB (Razorpay test mode)
- [ ] ALB provisioned: `kubectl get ingress -A` shows an ap-south-2 ALB hostname

## 6. Flip DNS (the one-variable switch)

```bash
cd terraform   # prod root — Cloudflare lives here
terraform apply -var "active_alb_dns_name=<DR ALB dns name from kubectl get ingress>"
```
All 5 Cloudflare domains follow. **Manual extras:**
- `swadkerala.com` — GoDaddy, change its CNAME by hand
- `www.kaaikanistore.com` / Delivery-partner + GK_Construction — restore from AWS Backup vault `vendure-dr-ec2` (console → restore latest recovery point → note new IPs → update A records `web/www.kaaikanistore.com`, `deliverypartner.kaaikani.co.in`, `gkc.avsecomhub.com`)

## 7. Known gaps (accepted or deferred — decided 2026-07-31)

| Gap | Status |
|---|---|
| SES lives only in ap-south-1 | **Deferred by decision** — customer email is DOWN during regional failover. Revisit: pre-verify identities in ap-southeast-1 |
| VB.NET desktop tools + mysql-exporter | Hardcode the old DB endpoint — update connection strings manually |
| Monitoring history | Fresh PVCs, history lost — accepted |
| Loki S3 (was already broken — role trusts dead OIDC) | Fix in prod first; DR inherits the fix |
| Redis Cloud region | UNKNOWN — check which region our Redis Cloud instance runs in; if ap-south-1-hosted, it shares our failure domain |

## 8. Fail-back (after Mumbai recovers)

Not scripted yet — outline: mysqldump DR db → restore into Mumbai (or DMS reverse-replication), flip `active_alb_dns_name` back, `terraform destroy` in live/aws-dr, re-enable backup replication. **Design properly before the second drill.**

## DRILL MODE — mandatory deviations from the real-failover steps above

The drill builds a copy of production **with production's data and keys**. The
infra cannot touch prod (separate region/state), but a faithfully-booted DR
Vendure can reach OUT to real systems. These four rules make the drill inert:

1. **Secrets: use throwaway drill copies, never the real replicas.**
   Create `vendure/dr-drill/*` secrets in ap-south-2 containing the drill
   DB_HOST and **DUMMY** Razorpay / MSG91 / SMTP keys. Point the DR
   SecretStore at those. The restored DB holds 27K+ real customers — with
   real keys, the abandoned-cart sweep alone could SMS/email actual
   customers from a test environment.
   Never run `PromoteReplicaToPrimary` on a real replica in a drill (it
   detaches live replication). Practice promotion on a dummy secret.
2. **Redis: in-cluster helm redis, never Redis Cloud.** Prod and DR sharing
   Redis means the DR worker CONSUMES the production job queue.
3. **Exclude argocd-image-updater** from the DR app-of-apps — two ArgoCDs
   pushing tag commits to one repo fight each other.
4. **S3: expect drill uploads to land in prod buckets** (the app policies
   point at the real CDN bucket). Keep test orders imageless, or accept and
   delete the stray objects after.

In a REAL failover none of these apply: real secrets get promoted, Redis
Cloud is checked for its own region status, image-updater runs (prod's is
dead), S3 writes are legitimate.

### Drill isolation VERIFICATION (a rule without a check is a hope)

**Pre-flight — before any app pod starts. Deploy with worker replicas=0;
scale up only after these pass** (the worker is what consumes queues and
sends messages):

```bash
# 1. Synced k8s secrets contain DRILL values (dummy keys use a DUMMY- prefix
#    so any leak is obvious in logs):
kubectl get secret vendure-secrets -n vendure-production \
  -o jsonpath='{.data.DB_HOST}' | base64 -d      # vendure-dr-db... expected
kubectl get secret vendure-app-secrets -n vendure-production \
  -o jsonpath='{.data.RAZORPAY_KEY_ID}' | base64 -d   # DUMMY-... expected
# 2. Redis is in-cluster (anything *.redis.cloud => ABORT):
kubectl exec deploy/vendure-server -n vendure-production -- env | grep REDIS_HOST
# 3. No image-updater:
kubectl get deploy -n argocd | grep image-updater     # expect: nothing
```

**During — watch PRODUCTION, not just DR:** prod Grafana worker
job-processing rate unchanged (a drop = foreign consumer on the queue);
ALB 5xx flat; MSG91 dashboard + SES send metrics flat in the drill window
(the "did we message a real customer" ground truth).

**Post-drill — after terraform destroy:**

```bash
cd terraform && terraform plan                    # "No changes" = prod untouched
aws secretsmanager describe-secret --secret-id vendure/prod/database \
  --query 'ReplicationStatus[0].Status'           # "InSync" = replica never promoted
aws rds describe-db-instance-automated-backups --region ap-south-2 \
  --query 'DBInstanceAutomatedBackups[0].Status'  # "replicating"
git log --oneline --since="<drill start>"         # no stray image-updater commits
aws s3api list-objects-v2 --bucket cdn.kaaikani.co.in \
  --query 'Contents[?LastModified>=`<drill start>`].[Key]'  # no drill uploads
```

## Drill teardown

```bash
cd terraform/live/aws-dr && terraform destroy
# deletion_protection on the restored DB blocks destroy — that is intentional;
# disable it via CLI first ONLY in a drill:
aws rds modify-db-instance --db-instance-identifier vendure-dr-db \
  --no-deletion-protection --apply-immediately --region ap-south-2
```
Drill-day cost: ~$10–15.
