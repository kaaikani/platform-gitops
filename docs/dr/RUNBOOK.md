# DR Runbook — ap-south-1 regional failover → ap-south-2

**Targets:** RTO 45–90 min · RPO 15–30 min
**Last drill:** NEVER — this runbook is UNTESTED until the first drill. Treat every step as suspect until then.

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

## Drill teardown

```bash
cd terraform/live/aws-dr && terraform destroy
# deletion_protection on the restored DB blocks destroy — that is intentional;
# disable it via CLI first ONLY in a drill:
aws rds modify-db-instance --db-instance-identifier vendure-dr-db \
  --no-deletion-protection --apply-immediately --region ap-south-2
```
Drill-day cost: ~$10–15.
