# GCP Escape Hatch — account-level DR

**Scope decision (2026-08-03): COLD escape hatch, not warm standby.**
Protects against the one failure AWS-internal DR cannot: the AWS ACCOUNT
itself dying (root compromise, billing lockout, org-wide IAM disaster).
Standing cost target: <$10/mo. RTO if the account dies: ~half a day.
Rationale: idle-GKE warm standby (~$200/mo) contradicts every cost decision
this platform runs on; upgrade only if a client contract demands it.

## What lives in GCP (asia-south1, Mumbai)

| Piece | Mechanism | RPO |
|---|---|---|
| Database dumps | nightly mysqldump CronJob (prod cluster) → S3 escape bucket → GCP Storage Transfer daily pull → GCS | ≤24 h |
| Product images | daily S3→GCS transfer, one GCS bucket per source bucket, keys identical to S3 | ≤24 h |
| Container images | Artifact Registry; **daily** mirror of the newest tag AND the tag production has pinned | ≤24 h |
| Secrets | **daily** AWS Secrets Manager → GCP Secret Manager sync (7 secrets) | ≤24 h |
| Asset write credentials | GCS HMAC key, so the unmodified app image can PUT new uploads | standing |
| TLS | self-signed certificate for all 4 zones, valid to 2041, in Secret Manager | standing |
| Network | VPC, subnet and private-services range, standing and free | standing |
| Compute skeleton | GKE Autopilot + Cloud SQL at `count = 0` in terraform/live/gcp-escape/ | live |
| Deployment config | environments/gcp/ overlays for all six workloads | live |

Everything with an hourly meter (GKE, Cloud SQL, Cloud NAT) stays at zero until
`escape_active = true`.

---

## Coverage — what is actually proven

Read this table before assuming the platform is portable. "Wired" means it
renders and the credentials exist; only "drilled" means it has served a real
request from Google.

| Capability | Status |
|---|---|
| vendure-production (wow_vendure) | **drilled** 2026-08-04 — shop-api served real data |
| vendure-client (client_vendure) | wired, never drilled — the DB had no copy outside AWS until c4b7792 |
| kaaikanistore / southmithai / swadkerala / prabhasaaridesigns | wired, never drilled |
| Database restore | **drilled** — 859 MB in 13m42s |
| Product image reads | wired — bucket layout fixed 2026-08-13, needs a real image fetch to confirm |
| Product image writes (uploads) | wired via GCS HMAC + S3 XML API, never drilled |
| Secret delivery (external-secrets → GCP Secret Manager) | wired, never drilled — drill #1 hand-fed env vars |
| TLS / HTTPS | ✅ certificate stored 2026-08-13; needs Cloudflare mode `Full` on escape day |
| Outbound internet from pods (Razorpay, MSG91, Shiprocket) | wired via Cloud NAT, never drilled |
| All 7 production S3 buckets | replicated daily, keys identical to S3 |
| Transactional email (SES) | **out of scope** — accepted 2026-08-13, see Accepted risks |
| Delivery-partner / GK_Construction EC2 | **out of scope** — accepted 2026-08-13, see Accepted risks |
| Prometheus / Grafana / Loki / Velero / Karpenter / ArgoCD | deliberately out of scope — see environments/gcp/bootstrap/README.md |

## ESCAPE DRILL #1 — 2026-08-04 — PASSED (single app)

Proven end to end with real production data, AWS in no part of the request path:
- Cloud SQL built 4m39s; **859 MB nightly dump imported in 13m42s, ZERO errors**
- Data verified inside GCP: **1,099 products · 48,844 orders · 29,707 customers**
- Vendure ran on GKE Autopilot from Artifact Registry: `/health` 200,
  shop-api returned 675 products (Pomegranate, Guava...)
- Total ~2h wall clock including 7 live-debugged findings; clean-run estimate
  60-90 min. Cost ~₹500 of trial credit.

**What drill #1 did not touch:** the other five workloads, TLS, image bodies,
uploads, secret delivery, outbound internet, and the second database. Drill #2
exists to close that list.

### Traps found while wiring the rest (2026-08-13) — none of these were drillable in #1

1. **Asset keys were wrong.** Both S3 buckets mirrored into one GCS bucket
   under a bucket-name prefix, so `assets/x.jpg` arrived as
   `cdn.kaaikani.co.in/assets/x.jpg`. Every product image would have 404'd.
   Drill #1 could not have seen it: it read JSON from shop-api and never
   fetched an image body. Fixed — one GCS bucket per source bucket, no prefix.
2. **DNS would have died cluster-wide.** The charts' default-deny NetworkPolicy
   permits DNS only to a namespace labelled `name: kube-system`. EKS has that
   label; GKE does not. Applied unchanged on Autopilot, every pod loses name
   resolution and it presents as the app hanging on the database. The GCP
   overlays disable NetworkPolicies and document the re-enable path.
3. **No outbound internet.** Autopilot nodes have no public IPs. Pods could
   reach Google APIs but not Razorpay, MSG91, Shiprocket or Bluedart — checkout
   and OTP would fail while the app looked healthy. Cloud NAT added.
4. **vendure-client's secrets would have silently reverted.** The chart extracts
   five secret keys in a fixed order and later extracts overwrite earlier ones.
   Overriding just `database` with Cloud SQL coordinates would have been undone
   two extracts later by the all-in-one secret, restoring the dead RDS endpoint.
   Hence the single merged `vendure_client_gcp_all`.
5. **Storefronts would have deployed nothing.** Their chart emits an Argo
   Rollout when `blueGreen.enabled`, and Argo Rollouts is not installed on the
   escape cluster — the object applies, nothing reconciles it, no pods appear,
   no error. Overlay switches them to plain Deployments.
6. **The watchman was dead.** `.github/workflows/dr-readiness.yml` was invalid
   YAML (a multi-line issue body ended the `run:` block scalar), so the weekly
   check that guards every one of these channels had never run. `drift.yml` and
   `outage-detector.yml` had the identical defect. All three fixed.

---

## ESCAPE DRILL #2 — plan (not yet run)

Goal: walk the full six-workload path end to end, in GCP, with production
untouched. Budget 3–4 hours. Expect findings; that is the point.

**Prerequisites — the drill cannot start without these:**

1. `terraform apply` in `terraform/live/gcp-escape/` (plan must show zero destroys)
2. Cloudflare Origin CA cert issued and uploaded (bootstrap README step 1)
3. Drill secrets built (step 2 below)

### Step 1 — read the four isolation rules

docs/dr/RUNBOOK.md "DRILL MODE". They apply here with one change: on GCP the
asset writes land in the DR mirror bucket rather than the production CDN
bucket, so uploads are safe — just delete the stray objects afterwards.

**The rule that matters most is Redis.** The escape overlay points at the real
Redis Cloud credentials, which is correct on escape day and catastrophic in a
drill: production and the drill cluster would share one job queue, and jobs the
drill worker consumed would never run in production. `drill-values.yaml` and
`bootstrap/drill-redis.yaml` exist to prevent exactly this.

### Step 2 — build the drill secrets

Three GCP secrets with DUMMY external keys. The `DUMMY-` prefix is deliberate:
if one ever reaches a real API the failure is obvious in a log line.

```bash
# redis -> the throwaway in-namespace instance, NOT Redis Cloud
jq -n '{REDIS_HOST:"drill-redis.vendure-production.svc.cluster.local",
        REDIS_PORT:"6379",REDIS_USERNAME:"default",
        REDIS_PASSWORD:"drill-only-not-a-secret"}' \
  | gcloud secrets create vendure_gcp_drill_redis --data-file=- --replication-policy=automatic

# integrations / smtps -> real shape, dummy values
gcloud secrets versions access latest --secret=vendure_prod_integrations \
  | jq 'with_entries(.value = "DUMMY-" + (.key))' \
  | gcloud secrets create vendure_gcp_drill_integrations --data-file=- --replication-policy=automatic
gcloud secrets versions access latest --secret=vendure_prod_smtps \
  | jq 'with_entries(.value = "DUMMY-" + (.key))' \
  | gcloud secrets create vendure_gcp_drill_smtps --data-file=- --replication-policy=automatic
```

`vendure_gcp_drill_database` is created in escape step 4, pointing at the
drill's Cloud SQL instance.

### Step 3 — run escape steps 1–6 with the drill overlay appended

Every helm command gets `-f environments/gcp/drill-values.yaml` last, and
`kubectl apply -f environments/gcp/bootstrap/drill-redis.yaml` runs before the
apps. Use a fresh `escape_db_suffix` (d2).

### Step 4 — PRE-FLIGHT, before the worker is allowed to start

A rule without a check is a hope. All four must pass:

```bash
# 1. Redis is the throwaway. Anything containing "redis.cloud" => ABORT, teardown.
kubectl exec deploy/vendure-production-vendure-stack -n vendure-production -- \
  env | grep REDIS_HOST

# 2. External keys are dummies
kubectl get secret vendure-app-secrets -n vendure-production \
  -o jsonpath='{.data.RAZORPAY_KEY_ID}' | base64 -d     # expect DUMMY-

# 3. DB_HOST is the drill Cloud SQL private IP, not RDS
kubectl get secret vendure-secrets -n vendure-production \
  -o jsonpath='{.data.DB_HOST}' | base64 -d             # expect 10.x

# 4. The worker really is at zero (this silently failed until 2026-08-13)
kubectl get deploy -n vendure-production -l app.kubernetes.io/component=worker \
  -o jsonpath='{.items[*].spec.replicas}'               # expect 0
```

Only then: `kubectl scale deploy ... --replicas=1`.

### Step 5 — pass criteria, per workload

Not "the pod is Running". Each of these is a thing a previous drill or review
found broken:

| Check | Proves |
|---|---|
| `/health` 200 on all six | scheduling, secrets, DB connectivity |
| shop-api returns real product counts for **both** databases | `client_vendure` restored — never tested before |
| An **image body** loads, `content-type: image/*` | the asset key layout fix |
| Admin upload of a new image succeeds | GCS HMAC write path |
| A pod can reach `https://api.razorpay.com` | Cloud NAT — checkout would fail without it |
| `https://gcp-drill.kaaikani.co.in` valid TLS in a browser | Origin CA cert + nginx |
| Storefront pages render with images | full stack, end to end |
| Worker processes one job against drill Redis | queue isolation held |

### Step 6 — teardown and write-up

```bash
terraform apply -var escape_active=false
gcloud storage rm -r gs://kaaikani-escape-assets/<drill-upload-prefix>
```

Delete the `gcp-drill` Cloudflare record. Record every finding in this document
the way drill #1's were recorded — a drill whose findings are not written down
has to be run again.

---

## Regional DR vs account-level DR — what each one actually covers

Two different failures, two different answers. ap-south-2 handles a REGION
dying while the AWS account lives. GCP handles the ACCOUNT dying, which takes
ap-south-2 with it. Regional DR is more complete and far better drilled;
account-level DR is the thinner, last-resort branch. That is a deliberate
trade, not neglect — but the difference should be known before an outage, not
discovered during one.

### Standing replication — always running

| Production resource | ap-south-2 | GCP |
|---|---|---|
| RDS database | automated backup replication, continuous, PITR | nightly logical dump, ≤24 h |
| Container images | ECR replication, all repos, per push | Artifact Registry, 6 repos, daily |
| Secrets | Secrets Manager replicas, continuous | Secret Manager sync, daily |
| `cdn.kaaikani.co.in` | S3 CRR | Storage Transfer, daily |
| `avsecomhub-clients-s3-images` | S3 CRR | Storage Transfer, daily |
| `vendure-images-backup` | S3 CRR | Storage Transfer, daily (added 2026-08-13) |
| `kaaikani-tfstate-…` | S3 CRR | ❌ **not replicated** |
| wow-vendure / order-reports / prabhasaaridesigns | skipped — empty | mirrored anyway, ~10 MB |
| EC2 AMIs | AWS Backup vault + DR copy | ❌ out of scope, accepted |
| TLS certificates | ACM pre-issued in ap-south-2 | self-signed, stored |
| Email | SES identity in ap-southeast-1 | ❌ out of scope, accepted |
| DNS | Cloudflare, one-record flip | Cloudflare, one-record flip |

### Built at failover time — code that exists but is not running

| | ap-south-2 (terraform/live/aws-dr) | GCP (terraform/live/gcp-escape) |
|---|---|---|
| Network | VPC, subnets, IGW, route tables, SGs | VPC, subnet, PSA — already built, standing |
| Compute | EKS cluster + addons + managed node group | GKE Autopilot, `count = 0` |
| Database | RDS instance restored from replicated backup | Cloud SQL, `count = 0` |
| Identity | IAM roles, OIDC provider, IRSA, KMS | Workload Identity service accounts |
| Ingress | ALB via AWS Load Balancer Controller | ingress-nginx + Origin CA cert |
| GitOps | ArgoCD bootstrap — drilled Synced/Healthy | ❌ six helm commands by hand |
| Observability | full stack via app-of-apps | ❌ Cloud Logging only |
| Velero / Karpenter / Kyverno | present | ❌ not installed |

### The two differences that matter most

**RPO.** ap-south-2 replicates database backups continuously — minutes of loss.
GCP is a nightly dump — **up to 24 hours of orders gone**. In an account-level
disaster that is the accepted price; it is not a general DR posture.

**Maturity.** ap-south-2 has been drilled three times, the third a clean 17-minute
run with all four storefronts serving real pages. GCP has been drilled once,
with one application and one of two databases. Code that renders is not the
same as a platform that has recovered.

---

## ESCAPE-DAY PROCEDURE

Assumes the decision to escape has been made: the AWS **account** is gone, not
just a region. For a regional event use docs/dr/RUNBOOK.md — ap-south-2 is
faster and better drilled.

### 1. Bring up the infrastructure

```bash
cd terraform/live/gcp-escape
terraform apply -var escape_active=true -var escape_db_suffix=dN \
  -var aws_transfer_access_key_id=... -var aws_transfer_secret_key=...
```

- **Bump `dN` every time** — Cloud SQL tombstones deleted instance names ~1 week.
- ⚠ **The two AWS-key vars are NOT optional.** All three S3→GCS transfer jobs
  are gated on `aws_transfer_access_key_id != ""`, so an apply without them
  reads as "3 to destroy" and silently tears down the replication that feeds
  this whole plan. Already-replicated data in GCS survives, but nothing new
  arrives. Read the plan before confirming: **the only destroys should be ones
  you intended.**
- Expect 403s if APIs were recently enabled: **retry, propagation takes minutes.**
- Note the outputs: `escape_db_ip` (private, 10.x) and `escape_cluster_endpoint`.

### 2. Restore both databases

Wait for each import to FINISH before touching users or networks — the instance
**locks during import** and every config call returns 409.

There are **TWO** databases (`wow_vendure` and `client_vendure`; the client
storefronts live in the second, DRILL FINDING #10). Terraform creates them
empty because the dumps are single-database mysqldumps carrying no
`CREATE DATABASE` — importing into a missing database fails with "No database
selected".

```
POST /v1/projects/kaaikani-escape/instances/<inst>/import
{"fileType":"SQL","uri":"gs://kaaikani-escape-db-dumps/<DB>-<newest>.sql.gz","database":"<DB>"}
```

The Cloud SQL service account's read access to the dumps bucket is granted by
terraform now — no longer a manual step.

### 3. Create the app user

**Use POST, never PUT.** A user created or updated via PUT gets only
`GRANT USAGE` (powerless); POST-created users get full privileges.

**The import restores DATA but NOT GRANTS.** After import, grant on **both**:

```sql
GRANT ALL PRIVILEGES ON `wow_vendure`.* TO 'admin'@'%';
GRANT ALL PRIVILEGES ON `client_vendure`.* TO 'admin'@'%';
FLUSH PRIVILEGES;
```

Symptom if skipped: `ER_DBACCESS_DENIED_ERROR 1044` and the app crash-loops
(or, if only the first is granted, the client storefronts crash alone).

### 4. Point the secrets at Cloud SQL

The mirrored `vendure_prod_database` holds the RDS endpoint, which no longer
exists. Two GCP-native secrets replace it (containers already created by
terraform):

```bash
DB_IP=$(terraform output -raw escape_db_ip)

# vendure-production
jq -n --arg h "$DB_IP" --arg p "$DB_PASSWORD" \
  '{DB_HOST:$h,DB_PORT:"3306",DB_NAME:"wow_vendure",DB_USERNAME:"admin",DB_PASSWORD:$p}' \
  | gcloud secrets versions add vendure_gcp_database --project kaaikani-escape --data-file=-

# vendure-client: ONE merged secret, because the chart's five extracts
# overwrite each other in order and the all-in-one secret would put the dead
# RDS endpoint back. Merge GCP values OVER the mirrored copy.
gcloud secrets versions access latest --secret=vendure_client_prod_all --project kaaikani-escape \
  | jq --arg h "$DB_IP" --arg p "$DB_PASSWORD" \
       --arg ak "$(gcloud secrets versions access latest --secret=vendure_gcp_assets \
                    --project kaaikani-escape | jq -r .AWS_ACCESS_KEY_ID)" \
       --arg sk "$(gcloud secrets versions access latest --secret=vendure_gcp_assets \
                    --project kaaikani-escape | jq -r .AWS_SECRET_ACCESS_KEY)" \
       '. + {DB_HOST:$h,DB_NAME:"client_vendure",DB_PASSWORD:$p,
             AWS_ACCESS_KEY_ID:$ak,AWS_SECRET_ACCESS_KEY:$sk}' \
  | gcloud secrets versions add vendure_client_gcp_all --project kaaikani-escape --data-file=-
```

### 5. Bootstrap the cluster

Follow **environments/gcp/bootstrap/README.md** — kubeconfig, TLS secret,
external-secrets + ClusterSecretStore, ingress-nginx, storefront secrets.

Do not skip the ClusterSecretStore readiness check. An unhealthy store means
every app below starts with no environment and crash-loops in a way that looks
exactly like a database problem.

### 6. Deploy all six workloads

```bash
helm upgrade --install vendure-production ./vendure-stack -n vendure-production --create-namespace \
  -f vendure-stack/values.yaml -f vendure-stack/values-production.yaml \
  -f environments/production/vendure-values.yaml -f environments/gcp/vendure-values.yaml

helm upgrade --install vendure-client-production ./vendure-stack -n vendure-client-production --create-namespace \
  -f vendure-stack/values.yaml \
  -f environments/production/vendure-client-values.yaml -f environments/gcp/vendure-client-values.yaml

for a in storefront southmithai swadkerala; do
  helm upgrade --install ${a}-production ./storefront -n ${a}-production --create-namespace \
    -f storefront/values.yaml \
    -f environments/production/${a}-values.yaml -f environments/gcp/storefronts-values.yaml
done

helm upgrade --install prabasaari-production ./prabasaari -n prabasaari-production --create-namespace \
  -f prabasaari/values.yaml \
  -f environments/production/prabasaari-values.yaml -f environments/gcp/prabasaari-values.yaml
```

The overlays layer ON TOP of the production values, so every production tuning
decision is inherited and only the AWS-specific parts are replaced. Image tags
come from the production values — the version whose behaviour is known.

**How to run the image**, if anything must be done by hand (this was
undocumented until drill #1 had to read it off the live AWS cluster, which
would not exist on escape day):
- command: `node --max-old-space-size=2048 dist/src/index.js`
- container port: **80** (`PORT=80`, `APP_ENV=production`)

### 7. Flip Cloudflare

Cloudflare is outside AWS and survives the account loss.

```bash
kubectl -n ingress-nginx get svc ingress-nginx-controller \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
```

Point every hostname at that one address, proxied, SSL mode **Full (strict)**:
kaaikani.co.in · kaaikanistore.com · southmithai.com · www.swadkerala.com ·
prabhasaaridesigns.com

### 8. Verify before declaring recovery

Check the things drills have historically missed, not just `/health`:

```bash
curl -sI https://kaaikani.co.in/health                       # 200
curl -s https://kaaikani.co.in/shop-api -d '{"query":"{products(options:{take:1}){totalItems}}"}' \
     -H 'content-type: application/json'                     # real totals
curl -sI "https://kaaikani.co.in/assets/<known-image-key>"   # 200 + image/*, NOT 404
```

Then a real order path: add to cart, reach payment (Razorpay must be reachable
— that is the Cloud NAT check), and confirm an admin upload succeeds (that is
the HMAC check). **Email will fail — see below.**

### 9. Teardown

```bash
terraform apply -var escape_active=false
```

Buckets, registry, secrets, network and transfer jobs all stay. Only the
metered resources go away.

---

## Accepted risks and scope boundaries

Decisions, not oversights. Each one is a thing an account-level loss takes
away, that the business has chosen not to pay to protect. Regional DR
(ap-south-2) still covers all of them — the exposure is specifically the
account-death branch, which is the rarest one.

### Transactional email (SES) — OUT OF SCOPE, accepted 2026-08-13

SES dies with the account. Order confirmations, password resets and OTP email
stop until a non-AWS sender is configured by hand.

The overlays still point at the mirrored SES credentials so the containers
start — every SMTP env var is a hard `secretKeyRef` and a missing key means the
pod will not boot at all. Nothing will send.

Partial mitigation, not by design: MSG91 SMS is third-party and keeps working,
so **OTP over SMS survives**. Order confirmation email does not.

If this is ever revisited, the work is small: choose an SMTP provider, store
the credentials as a GCP secret, and point `externalSecrets.awsSecrets.smtps`
at it. One line, once the account exists.

### Delivery-partner / GK_Construction EC2 — OUT OF SCOPE, accepted 2026-08-13

Both back up nightly to the ap-south-2 vault, which lives in the same AWS
account. Regional failure is covered; account loss takes the instances and
their backups together.

⚠ Understand what is being accepted: `Delivery-partner` is tagged in
terraform as **"client production server, serves www.kaaikanistore.com"** and
carries `prevent_destroy = true`. This is a live customer-facing host, not a
utility box. Accepting this risk means accepting that an account-level loss
takes it down with no copy anywhere, and that rebuilding it starts from
whatever knowledge exists outside AWS — which today is nothing written down.

If revisited, cheapest first: a nightly SSM-driven tar of the app directory
into the escape S3 bucket, which already flows through to GCS; or a full
VM Import/Export of the disk into a GCE image.

### swadkerala.com — OUT OF SCOPE (client-controlled domain)

**Decision 2026-08-13: not ours to fix.** The domain belongs to a client, not
to this platform. DR scope ends at the workload: the escape cluster runs
`swadkerala-production` like any other release, and repointing the domain is
the client's action on their own DNS. Do not spend escape-day minutes on it,
and do not treat the finding below as an open item — it is a boundary.

What that means concretely on escape day: bring the app up, notify the client
that their DNS must be repointed at the escape ingress IP, and move on. TLS for
that hostname is theirs to arrange; the Cloudflare Origin CA certificate does
not and cannot cover it.

The technical detail, kept because it is easy to forget and would otherwise be
rediscovered under pressure:

Found 2026-08-13 while querying the Cloudflare API. Four platform zones are on
Cloudflare (kaaikani.co.in, kaaikanistore.com, southmithai.com,
prabhasaaridesigns.com, plus avsecomhub.com). **swadkerala.com is not.**

```
$ dig +short NS swadkerala.com
ns31.domaincontrol.com.      # GoDaddy
$ dig +short www.swadkerala.com
k8s-vendureshared-....ap-south-1.elb.amazonaws.com.   # straight at the AWS ALB
```

Two consequences, both of which break stated assumptions:

1. **"Cloudflare repoints the domains" is false for this one.** Escape step 7
   and every AWS failover drill assume one Cloudflare record change moves
   traffic. swadkerala needs a GoDaddy login instead — an account whose
   credentials are not in the runbook, on a domain that points directly at an
   AWS load balancer that would no longer exist.
2. **The Origin CA certificate cannot cover it.** Origin CA certs are trusted
   only by Cloudflare's proxy. A hostname resolving straight to the origin
   needs a publicly-trusted certificate, so `www.swadkerala.com` would serve a
   TLS error on the escape cluster even with everything else working.

Note this applies to the **AWS** failover runbook too, not only the GCP
escape: every drill so far has assumed one Cloudflare record change moves all
traffic. For this brand it never did.

Drill #2 covers the four Cloudflare-fronted brands with TLS, and tests
swadkerala by Host-header override only.

### RPO

24 hours for everything: database, images, container images, secrets. A
rotation or a deploy after the nightly run is not in GCP. Acceptable for an
account-loss scenario that is expected roughly never; not acceptable as a
general DR posture, which is what ap-south-2 is for.

---

## YOUR one-time setup

Steps 1–6 are done. Steps 7–8 are outstanding and the readiness check will
open an issue every week until they are.

1. ~~https://console.cloud.google.com → create account~~
2. ~~Create project `kaaikani-escape` + enable billing~~
3. ~~Install CLI: `sudo snap install google-cloud-cli --classic`~~
4. ~~`gcloud auth application-default login`~~
4a. ~~`gcloud auth login`~~ — **a separate step, and easy to miss.**
   `application-default login` writes ADC, which is all terraform needs, but
   leaves `gcloud auth list` empty. Every `gcloud secrets` / `gcloud storage` /
   `gcloud container clusters get-credentials` in this runbook fails without
   it, and it needs a browser — not something to discover mid-outage.
   The account holding this project is **storekaaikani@gmail.com** (not the
   kaaikanimarketing address this document used to name).
5. ~~`gcloud config set project kaaikani-escape`~~
6. ~~terraform apply in terraform/live/gcp-escape/~~
7. **`terraform apply` again** for the new platform resources (VPC, NAT
   skeleton, HMAC key, service accounts, secret containers). Review the plan:
   it should be all creates plus two in-place transfer-job updates, and
   **zero destroys**.
8. **Issue the Cloudflare Origin CA certificate** and upload both halves —
   environments/gcp/bootstrap/README.md step 1. Until this is done there is no
   TLS on escape day.
   ⚠ Origin CA is the one Cloudflare API that does NOT accept a normal API
   token: `POST /certificates` returns `1016 User is not authorized`. It needs
   the account-wide **Origin CA Key** (dashboard → My Profile → API Tokens →
   Origin CA Key) sent as `X-Auth-User-Service-Key`, or an API token scoped
   **User → SSL and Certificates → Edit**.
9. **Org policy exception for the GCS HMAC key.** The org enforces
   `constraints/iam.disableServiceAccountKeyCreation`, which blocks the one
   static credential the escape genuinely needs — GCS speaks S3 only over an
   HMAC key, and Vendure's S3AssetStorageStrategy passes explicit credentials.
   Without it the app cannot read or write product images.
   Project owner is not enough; this needs `roles/orgpolicy.policyAdmin`, which
   the Organization Administrator grants. Full verified sequence:
   ```bash
   # policyAdmin is an ORG-level role -- roles/owner on the project cannot set
   # org policy, and the failure reads as a plain permission error.
   gcloud organizations add-iam-policy-binding <ORG_ID> \
     --member="user:<account>" --role="roles/orgpolicy.policyAdmin"

   # The v2 tooling needs this API, and without it `gcloud org-policies ...`
   # fails with PERMISSION_DENIED -- which looks like a missing role and sends
   # you chasing IAM instead of a disabled service.
   gcloud services enable orgpolicy.googleapis.com --project=kaaikani-escape

   # TWO constraints, and clearing one does not clear the other. Organizations
   # created after ~2024 get Google's secure-by-default managed constraints on
   # top of the legacy one; this org was created 2026-07-23.
   gcloud resource-manager org-policies disable-enforce \
     constraints/iam.disableServiceAccountKeyCreation --project=kaaikani-escape
   gcloud org-policies describe iam.managed.disableServiceAccountKeyCreation \
     --project=kaaikani-escape --effective     # want: enforce: false
   ```
   ⏱ Changes take up to ~15 minutes to propagate. An immediate retry still
   fails with the same 412 and looks like the change did not work.
   ⚠ **There are two organizations both named `storekaaikani-org`**
   (`28355858131` and `121308697772`). kaaikani-escape lives under
   **28355858131** — confirm with `gcloud projects get-ancestors kaaikani-escape`
   before touching any org-level policy, or the change lands on the wrong org
   and appears to do nothing.

After step 7, delete the stale prefixed copies left by the old asset layout:

```bash
gcloud storage rm -r gs://kaaikani-escape-assets/cdn.kaaikani.co.in/ \
                     gs://kaaikani-escape-assets/avsecomhub-clients-s3-images/
```

Then force one run of each transfer job so the buckets refill at the correct
keys, and re-run the readiness workflow.

## AWS-side bridge (in prod root, dr_gcp_bridge.tf)

- S3 bucket `kaaikani-escape-dumps` (dump landing zone, 7-day lifecycle)
- IAM user `gcp-storage-transfer` scoped to read that bucket only
  (access key goes into the GCP transfer job — the ONLY AWS credential
  that lives in GCP, and it can read nothing but dumps)
- CronJob manifest environments/production/db-dump-cronjob.yaml
  (nightly 02:15 IST mysqldump → S3; ⚠ APPLY TO PROD ONLY AFTER REVIEW)

## Fail-back from GCP

docs/dr/FAILBACK.md covers ap-south-1 ← ap-south-2 only. Returning from GCP is
a different and larger exercise — a new AWS account, re-created IAM, re-issued
ACM certificates, and a database that has diverged. It is not written up
because escaping to GCP is already the worst-case branch; write it during the
post-mortem of an escape that actually happens, when the real constraints are
known rather than guessed.
