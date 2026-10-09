# Zero-downtime right-sizing runbook

Source: utilization audit of 2026-09-23 (30 days of CloudWatch + Prometheus).
Goal: ~$68/mo less (~$85 with the RDS reservation), with no customer-visible
downtime. The only exception is the database switchover: about one minute.

Conventions
- kubectl context for prod is `prodc`. The default context is a local kind cluster.
- Kubernetes changes: commit to `main`, ArgoCD syncs. `karpenter-config` has prune + selfHeal.
- Terraform changes: PR -> CI plan -> merge -> CI apply. Every plan must read
  0 to destroy and never contain `forces replacement`.
- Dollar figures are billed, pre-GST, taken from the bill (EC2 and RDS instance
  hours bill ~18% above the public price list on this account).

Order matters. Do the phases in sequence.

---

## Phase 0 - config only, nothing moves (day 1)

### 0.1 Pin the node AMI
File `karpenter/ec2nodeclass.yaml`:
```yaml
  amiSelectorTerms:
    - alias: al2023@v20260917      # was al2023@latest
```
All four Karpenter nodes already run v20260917, so nothing drifts. From now on an
AMI bump is a deliberate PR (change the version string; expect one node
replacement per pool, handled exactly like Phase 2).

Verify:
```bash
kubectl --context prodc get ec2nodeclass default -o jsonpath='{.status.amis[*].name}'
kubectl --context prodc get nodeclaims -o custom-columns='NAME:.metadata.name,DRIFTED:.status.conditions[?(@.type=="Drifted")].status'
```

### 0.2 Connect the spot-interruption queue
The Karpenter controller is a plain Helm release (`helm list -n karpenter`), not
an ArgoCD app. EventBridge already sends spot / rebalance / health events to SQS
`vendure-prod`; Karpenter has never read it.
```bash
helm --kube-context prodc upgrade karpenter oci://public.ecr.aws/karpenter/karpenter \
  --version 1.10.0 -n karpenter --reuse-values \
  --set settings.interruptionQueue=vendure-prod
```
Verify:
```bash
kubectl --context prodc -n karpenter get deploy karpenter \
  -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="INTERRUPTION_QUEUE")].value}'
kubectl --context prodc -n karpenter logs deploy/karpenter --since=5m | grep -i -E 'interruption|sqs'
```
IAM: `terraform/policies/KarpenterControllerPolicy-vendure-prod.json` already
grants sqs:DeleteMessage / GetQueueUrl / ReceiveMessage. If the log shows
AccessDenied on `sqs:GetQueueAttributes`, add that action there.

Also save the release values in git (they only live in the cluster today):
`helm get values karpenter -n karpenter > karpenter/helm-values.yaml`.

### 0.3 Delete the dead test pools
They point at a node class that no longer validates and write ~1,100 error
lines each every 3 hours.
- `karpenter/kustomization.yaml`: remove `ec2nodeclass-test.yaml`,
  `nodepool-application-test.yaml`, `nodepool-monitoring-test.yaml`.
- `git rm` those three files. ArgoCD prunes the live objects.
- `aws sqs delete-queue --queue-url https://sqs.ap-south-1.amazonaws.com/149536454380/karpenter-vendure-test`

Verify: `kubectl --context prodc get nodepools,ec2nodeclass` lists only
application, application-spot, storefront, vendure-clients and `default`.

### 0.4 Allow the client pool to grow (prepares Phase 1, no effect yet)
File `karpenter/nodepool-vendure-clients.yaml`:
```yaml
  limits:
    cpu: 6        # was 2
    memory: 6Gi   # was 2Gi  (2 steady nodes + 1 surge node during a deploy)
```
Rewrite the "hard-capped at ONE" comment.

### 0.5 ExternalSecrets refresh 1m -> 15m
- `environments/production/vendure-values.yaml` line ~508: `refreshInterval: 15m`
- `monitoring-stack/exporters-externalsecret.yaml` line ~19: `refreshInterval: 15m`
Reloader only restarts pods when Secret data changes; it does not.

### 0.6 Delete the unused CloudWatch dashboard (330 metrics, billed)
```bash
aws cloudwatch delete-dashboards --dashboard-names cloudwatch_default
```

### 0.7 gp2 -> gp3 on the monitoring volumes (online, no pod restart)
```bash
for v in vol-09b90b25bd56e3635 vol-00a7c0433cc9f8d78 vol-0eec9210484c5786e; do
  aws ec2 modify-volume --volume-id $v --volume-type gp3
done
aws ec2 describe-volumes-modifications \
  --volume-ids vol-09b90b25bd56e3635 vol-00a7c0433cc9f8d78 vol-0eec9210484c5786e \
  --query 'VolumesModifications[].{id:VolumeId,state:ModificationState,progress:Progress}'
```
These PVC volumes are CSI-managed, not in Terraform.

### 0.8 Velero: stop snapshotting monitoring disks
`environments/production/velero-values.yaml`: `snapshotVolumes: false`.
Business data is in RDS + S3; these snapshots only covered Prometheus / Grafana /
Loki / Alertmanager. Old snapshots expire with the 7-day TTL.

### 0.9 Orphans
- Secret `vendure/test/env`: delete the `aws_secretsmanager_secret.vendure_test_env`
  block in `terraform/secrets.tf`. CI apply deletes it (30-day recovery window).
- ECR: `aws ecr delete-repository --repository-name vendure-test --force` and
  `aws ecr delete-repository --repository-name client_vendure`, then remove
  `aws_ecr_repository.vendure_test` from `terraform/ecr.tf`. The next plan's
  refresh drops it from state (same pattern as test-db-1).
- KMS keys `eks-vendure-test-secrets` (15e0e417-...) and `export_kk_dbs`
  (0c315c3d-...). Check first, then schedule deletion:
```bash
for k in 15e0e417-9410-47b1-814c-06c159cd1760 0c315c3d-3313-473b-bf6e-fe417f6c9119; do
  aws cloudtrail lookup-events \
    --lookup-attributes AttributeKey=ResourceName,AttributeValue=arn:aws:kms:ap-south-1:149536454380:key/$k \
    --start-time $(date -u -d '90 days ago' +%Y-%m-%dT%H:%M:%SZ) --max-items 5 \
    --query 'Events[].{t:EventTime,n:EventName}'
done
aws rds describe-export-tasks --query 'ExportTasks[].{id:ExportTaskIdentifier,kms:KmsKeyId}'
# nothing found ->
aws kms schedule-key-deletion --key-id <id> --pending-window-in-days 30
```
- S3: `vendure-velero-backups` and `vendure-velero-backups-local` are empty and
  not the live Velero location (that is `vendure-velero-backups-149536454380`):
  `aws s3 rb s3://<name>`. `ses-event-logs-example`: Firehose stream
  `ses-events-stream` exists, check its destination before touching the bucket
  (`aws firehose describe-delivery-stream --delivery-stream-name ses-events-stream`);
  if it is the destination, add a 30-day expiry rule instead of deleting.
  `vendure-test-images`: confirm the stopped test env does not use it.
- CloudTrail bucket has no expiry (4.9 GB and growing):
```bash
aws s3api put-bucket-lifecycle-configuration \
  --bucket aws-cloudtrail-logs-149536454380-27a2b24e \
  --lifecycle-configuration '{"Rules":[{"ID":"expire-90d","Status":"Enabled","Filter":{"Prefix":""},"Expiration":{"Days":90}}]}'
```

### 0.10 Clear the two stuck storefront rollouts
swadkerala and southmithai have new pods failing on a missing
`GOOGLE_MAPS_API_KEY` in their namespace secrets. Add the key to the AWS secret
those namespaces sync from, force the ExternalSecret sync, confirm both
Rollouts are Healthy. Every site must be healthy before Phase 2.

---

## Phase 1 - client API to 2 replicas (prerequisite for anything that moves pods)

Today vendure-client is 1 pod, no surge, on a node that fits exactly one pod.
Every pod move is an outage. "No downtime" and "1 replica" cannot both be true.
Cost: one more t3a.small plus its public IP, about $15/mo.

File `environments/production/vendure-client-values.yaml`, server section:
```yaml
  replicaCount: 2
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0
  autoscaling:
    minReplicas: 2
    maxReplicas: 2
  podDisruptionBudget:
    enabled: true
    minAvailable: 1
  affinity:
    podAntiAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        - labelSelector:
            matchExpressions:
              - key: app
                operator: In
                values: ["vendure"]      # confirm: kubectl -n vendure-client-production get pods --show-labels
          topologyKey: kubernetes.io/hostname
```
Leave the worker at 1 replica. Update the comments that describe the
single-node design here and in `nodepool-vendure-clients.yaml`.

What happens: ArgoCD syncs, the required anti-affinity forces a second node,
Karpenter launches a second t3a.small (~90 s), the second pod becomes Ready,
the PDB is created. Deploys from now on: a surge pod needs a third node for a
few minutes; Karpenter adds it and consolidates it away 5 minutes after the
rollout. About $0.03 per deploy.

Verify:
```bash
kubectl --context prodc -n vendure-client-production get pods -o wide   # 2 API pods, 2 different nodes
kubectl --context prodc -n vendure-client-production get pdb
```

---

## Phase 2 - node swap, one Karpenter wave (off-peak, ~20 minutes)

Put all of these in ONE commit so every Karpenter node is replaced exactly
once. Karpenter launches each replacement before draining the old node, and
the PDBs (vendure minAvailable 1, client minAvailable 1, each storefront
minAvailable 1) guarantee at least one pod of every app stays Ready.

Pre-flight:
```bash
kubectl --context prodc get pods -A --field-selector status.phase!=Running   # only Succeeded jobs expected
kubectl --context prodc get applications -n argocd                            # all Synced / Healthy
```

### 2.1 `karpenter/nodepool-application-spot.yaml`
```yaml
        - key: karpenter.k8s.aws/instance-family
          operator: In
          values: ["t3a", "t3", "m5a", "m6a"]     # was ["c5a"]; four spot pools instead of one
        - key: karpenter.k8s.aws/instance-size
          operator: In
          values: ["large"]
  limits:
    cpu: 2
    memory: 8Gi                                   # one 8 GiB node (reports ~7.7Gi)
```

### 2.2 `karpenter/nodepool-application.yaml`
```yaml
          values: ["t3a"]                         # was ["c5a"]
          values: ["large"]
  limits:
    cpu: 2
    memory: 8Gi
```
Rewrite the c5a / "4Gi fits one node" comments.

Why t3a.large: same on-demand price as c5a.large, cheaper on spot, 8 GB instead
of 4. A Vendure surge pod (1800Mi) now fits next to the running one, and the
HPA can really reach 3-4 replicas. CPU on these nodes averages 6%, so
burstable credits never run out (the platform t3a.large runs 25% and keeps
~840 of 864 credits).

### 2.3 `karpenter/nodepool-storefront.yaml`
```yaml
          values: ["t3a", "t3"]                   # family
          values: ["medium"]
        - key: topology.kubernetes.io/zone
          operator: In
          values: ["ap-south-1a", "ap-south-1b", "ap-south-1c"]   # all 3 subnets carry the discovery tag
  disruption:
    consolidationPolicy: WhenEmptyOrUnderutilized
    consolidateAfter: 30m                         # was 5m; stops the spot->on-demand->spot flip
```
Storefronts do not talk to RDS, so leaving ap-south-1a costs nothing.

### 2.4 `karpenter/ec2nodeclass.yaml`
```yaml
        volumeSize: 20Gi                          # was 30Gi; nodes use 4-8 GB
```

Watch the wave:
```bash
kubectl --context prodc get nodeclaims -w
kubectl --context prodc -n vendure-production get pods -w
kubectl --context prodc -n vendure-client-production get pods -w
```
Expected: each pool gets a new nodeclaim, Ready in ~90 s, then the old node
drains pod by pod. Vendure runs on one replica for the ~60 s its second pod
takes to boot on the new node, same as every deploy today, never zero.

If a replacement does not launch within 2 minutes and the Karpenter log says
the pool "exceeds limits", raise that pool's memory limit to 16Gi, let the
wave finish, then set it back to 8Gi.

Rollback: revert the commit. Karpenter drifts back the same way.

### 2.5 After the wave: surge deploys for Vendure
`environments/production/vendure-values.yaml`:
```yaml
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0
```
Rewrite the comment block above it. Verify on the next deploy that the pod
count goes 2 -> 3 -> 2 and never below 2 Ready.

---

## Phase 3 - database: MySQL 8.4 + db.t4g.medium in one Blue/Green switchover

Why now: MySQL 8.0 left RDS standard support on 31 Jul 2026. The prod instance
is opted out of Extended Support, so AWS will force a major upgrade to 8.4 on
its own schedule. A plain `modify-db-instance` on single-AZ means 5-15 minutes
down. Blue/Green does both changes with about one minute of paused writes.

### 3.1 Terraform prep (PR 1)
`terraform/rds_support.tf`, add next to `aws_db_parameter_group.prod`:
```hcl
resource "aws_db_parameter_group" "prod_84" {
  name        = "aws-vendure-pg-84"
  family      = "mysql8.4"
  description = "Vendure prod MySQL 8.4"
  # copy the 8 parameter {} blocks from aws_db_parameter_group.prod unchanged:
  # long_query_time, log_output, max_allowed_packet, net_read_timeout,
  # net_write_timeout, slow_query_log, time_zone, wait_timeout
}
```
`terraform/db.tf` on `prod_db` (matches live, so plan shows no change):
```hcl
  engine_lifecycle_support = "open-source-rds-extended-support-disabled"
```
`terraform/live/aws-dr/rds.tf` on `aws_db_instance.dr`: the same line. A DR
restore of an 8.0 backup otherwise auto-enrols in Extended Support at
~$0.135 per vCPU-hour (~$197/mo if left running). That is what the August
drill was billed for.

Merge. Expected plan: 1 to add (the parameter group), 0 to change, 0 to destroy.

### 3.2 Compatibility check (mysql client from a pod or the bastion, admin user)
```sql
SELECT user, host, plugin FROM mysql.user;
```
8.4 ships `mysql_native_password` disabled. Any user still on it (typical for
the two VB.NET tools' MySQL Connector/NET) must either move:
`ALTER USER 'x'@'%' IDENTIFIED WITH caching_sha2_password BY '<same password>';`
(Connector/NET 8.0.x or newer on those PCs), or the new parameter group gets
`mysql_native_password = ON`. Vendure's mysql2 driver is fine either way. The 8
custom parameters all exist in 8.4.

### 3.3 Create the green environment
```bash
aws rds create-blue-green-deployment \
  --blue-green-deployment-name vendure-prod-84 \
  --source arn:aws:rds:ap-south-1:149536454380:db:vendure-prod-db \
  --target-engine-version 8.4.9 \
  --target-db-parameter-group-name aws-vendure-pg-84 \
  --target-db-instance-class db.t4g.medium
aws rds describe-blue-green-deployments \
  --query 'BlueGreenDeployments[].{id:BlueGreenDeploymentIdentifier,status:Status,target:Target}'
```
30-60 minutes to AVAILABLE. Green is a live read-only replica of prod on
8.4.9 / t4g.medium. It costs about $2.50/day while it exists; plan 2-3 days of
testing, not weeks.

### 3.4 Test against green
```bash
GREEN=$(aws rds describe-blue-green-deployments --query 'BlueGreenDeployments[0].Target' --output text | sed 's/.*://')
aws rds describe-db-instances --db-instance-identifier $GREEN --query 'DBInstances[0].Endpoint.Address' --output text
```
- `SELECT VERSION();` -> 8.4.9. `SHOW VARIABLES LIKE 'time_zone';` -> Asia/Calcutta.
- Run both VB.NET report tools against the green host. This is the auth test.
- Optional: point the stopped test env's Vendure at green with a read-only account.
- Replica lag must be 0 before switchover: CloudWatch `ReplicaLag` on the green instance.

### 3.5 Switchover
When: Tuesday 03:10 IST (Monday 21:40 UTC). After the :00/:30 abandoned-cart
sweep tick, outside the backup window (01:30-02:00 IST) and the maintenance
window (03:00-04:00 IST Wednesday). No deploy in progress. Have the Grafana
ALB 5xx panel and `kubectl -n vendure-production get pods -w` open.
```bash
aws rds switchover-blue-green-deployment \
  --blue-green-deployment-identifier <id> --switchover-timeout 300
```
What happens: writes pause, replication drains, names swap. Green becomes
`vendure-prod-db` with the SAME endpoint
`vendure-prod-db.cbq8i48yyklk.ap-south-1.rds.amazonaws.com`, so the secret
`vendure/prod/database` is not touched. The old instance becomes
`vendure-prod-db-old1`. Under a minute.

App side: connection pools reconnect on the next query. Requests in flight
during that minute fail. Readiness needs 6 failed probes (60 s) before a pod
leaves the ALB, so pods most likely stay in service; if one restarts, it is
back in ~60 s while the other serves.

Post checks:
```bash
aws rds describe-db-instances --db-instance-identifier vendure-prod-db \
  --query 'DBInstances[0].{v:EngineVersion,c:DBInstanceClass,pg:DBParameterGroups[0].DBParameterGroupName,pi:PerformanceInsightsEnabled,logs:EnabledCloudwatchLogsExports,dp:DeletionProtection,br:BackupRetentionPeriod}'
```
Everything as before, plus 8.4.9 / db.t4g.medium / aws-vendure-pg-84. If
`dp` is false, re-enable deletion protection. Place a test order.

Rollback (first minutes only, hard failure): point the app at the
`vendure-prod-db-old1` endpoint via the secret. Writes made after switchover
are lost, so decide within minutes or not at all.

### 3.6 Terraform after (PR 2, same day)
`terraform/db.tf`:
```hcl
  engine_version       = "8.4.9"
  instance_class       = "db.t4g.medium"
  parameter_group_name = aws_db_parameter_group.prod_84.name
```
Plan must be 0 / 0 / 0 with no `forces replacement`. Terraform's ID for the
resource is the identifier, which the new instance now carries. Do NOT remove
`aws_db_parameter_group.prod` yet; it is still attached to -old1.

### 3.7 DR backup replication (tied to the instance's resource ID, not its name)
```bash
aws rds describe-db-instances --db-instance-identifier vendure-prod-db --query 'DBInstances[0].DbiResourceId' --output text
aws rds describe-db-instance-automated-backups --region ap-south-2 \
  --query 'DBInstanceAutomatedBackups[].{db:DBInstanceIdentifier,res:DbiResourceId,status:Status}'
```
If the new DbiResourceId is not `replicating`:
```bash
cd terraform && terraform apply -replace=aws_db_instance_automated_backups_replication.prod_db
aws rds stop-db-instance-automated-backups-replication --region ap-south-2 \
  --source-db-instance-arn arn:aws:rds:ap-south-1:149536454380:db:vendure-prod-db-old1
```
The nightly drift job will otherwise flag it.

### 3.8 One week later
```bash
aws rds delete-blue-green-deployment --blue-green-deployment-identifier <id>      # instances stay
aws rds modify-db-instance --db-instance-identifier vendure-prod-db-old1 --no-deletion-protection --apply-immediately
aws rds delete-db-instance --db-instance-identifier vendure-prod-db-old1 \
  --final-db-snapshot-identifier vendure-prod-db-mysql80-final-$(date +%Y%m%d)
```
The old instance bills $84/mo while it lives. Then remove
`aws_db_parameter_group.prod` (mysql8.0) from Terraform.

Reservation (your decision, only once you are sure t4g.medium stays a year):
offering `7d7bf484-1bf1-48b4-881a-6547287b192f` = db.t4g.medium, MySQL, 1 year,
no upfront, $0.066/h against $0.084/h on demand.
```bash
aws rds purchase-reserved-db-instances-offering \
  --reserved-db-instances-offering-id 7d7bf484-1bf1-48b4-881a-6547287b192f --db-instance-count 1
```

---

## Phase 4 - Delivery-partner and GK_Construction (t3a.medium, <1% CPU)

Pre-check on both over SSH (keys "new one" / "client_key_pair"):
`free -m`, `df -h /`, `pm2 ls`. Go to t3a.small only if used RAM stays under
~1.2 GB including any `next build` that runs on the box.

Option A - about 3 minutes, at 03:00 IST, Terraform-native
- `terraform/ec2.tf`: `instance_type = "t3a.small"` on `delivery_partner`
  and/or `gk_const`. Terraform stops, modifies, starts. `prevent_destroy` is
  fine; this is in-place. Merge at night.
- GK has no Elastic IP, so its public IP changes on stop/start: update the
  Cloudflare A record for gkc.avsecomhub.com right after. Delivery-partner keeps
  52.66.51.238.

Option B - seconds of impact, more bookkeeping
```bash
aws ec2 create-image --instance-id i-0857191705f5e582e --name delivery-partner-clone-$(date +%F) --no-reboot
aws ec2 run-instances --image-id <ami> --instance-type t3a.small \
  --subnet-id subnet-0b33bcf3c79fccd75 \
  --security-group-ids sg-0ca478578323cda2c sg-0237a8c1f4902ec50 sg-08f72232f33cb4ff4 sg-0b65e3e71f183b97a \
  --key-name "new one" \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=Delivery-partner}]'
# ssh in, confirm the app answers on localhost, then move the EIP:
aws ec2 associate-address --allocation-id eipalloc-06a5a33e7469a77b2 --instance-id <new-id> --allow-reassociation
```
Stop the old instance, keep it 7 days, terminate. Then:
`terraform state rm aws_instance.delivery_partner`, update `ec2.tf` (ami,
instance_type) with an `import {}` block for the new id, let CI import, remove
the block after one apply. AWS Backup selection `standalone-prod-ec2` lists
instances by ARN: add a selection with the new ARN, delete the old.
GK: same steps with security groups sg-0ca478578323cda2c sg-0ba5c7c8f76401d4b
sg-08acbcb27549a1e75 sg-08f72232f33cb4ff4 sg-0b65e3e71f183b97a and key
client_key_pair; instead of the EIP step, point the Cloudflare A record
gkc.avsecomhub.com at the new IP.

---

## Phase 5 - optional, later
- Storefront requests 256Mi / 150m -> 192Mi / 100m, limits unchanged. Not
  lower: the HPAs target 75-80% of the memory request and p95 usage is
  ~100 Mi, so 128Mi would pin them at 3 replicas. Blue-green rollouts, no impact.
- Managed node groups still run AMI v20260304 (March). Bump `release_version`
  in `modules/node_group` via Terraform: storefront NG rolls inside the PDBs,
  no impact; platform NG means ~3 minutes without Grafana / ArgoCD, no
  customer impact (both ALB-controller pods sit there, so ingress changes pause,
  traffic does not).
- mysql-exporter nodeSelector `node-group: app` matches no pool; cloudflare-exporter
  image + secret are broken. Not cost, but both are Pending forever.

---

## Done-checklist
- Daily bill: EC2-Instances ~$5.2 -> ~$4.4, RDS ~$3.0 -> ~$2.6 (RI: ~$2.0),
  EC2-Other, CloudWatch, Secrets Manager, KMS lines all lower.
- `kubectl get nodeclaims`: all Ready, none Drifted; 7 nodes (6 + second client node).
- Karpenter log: no "ignoring nodepool" / "no subnets" lines.
- Prometheus `count(count_over_time(up{job="node-exporter"}[7d]))` ~7-9 (was 15-20).
- `terraform plan` (prod root) = No changes; nightly drift job green.
