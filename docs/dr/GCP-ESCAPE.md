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
| Container images | Artifact Registry repo; CI pushes to BOTH registries (GitHub Actions is outside AWS) | per deploy |
| Secrets | quarterly gpg export (runbook step) uploaded to GCS | quarterly |
| Terraform | this repo is on GitHub (outside AWS) — includes GKE skeleton in terraform/live/gcp-escape/ | live |

## ESCAPE DRILL #1 — 2026-08-04 — PASSED

Proven end to end with real production data, AWS in no part of the request path:
- Cloud SQL built 4m39s; **859 MB nightly dump imported in 13m42s, ZERO errors**
- Data verified inside GCP: **1,099 products · 48,844 orders · 29,707 customers**
- Vendure ran on GKE Autopilot from Artifact Registry: `/health` 200,
  shop-api returned 675 products (Pomegranate, Guava...)
- Total ~2h wall clock including 7 live-debugged findings; clean-run estimate
  60-90 min. Cost ~₹500 of trial credit.

### ESCAPE-DAY PROCEDURE (corrected by the drill — follow exactly)

1. `terraform apply -var escape_active=true -var escape_db_suffix=dN`
   (**bump N every time** — Cloud SQL tombstones deleted instance names ~1 week)
   Expect 403s if APIs were recently enabled: **retry, propagation takes minutes**.
2. Wait for the import to FINISH before touching users/networks — the instance
   **locks during import** and every config call returns 409.
3. Import: `POST /v1/projects/kaaikani-escape/instances/<inst>/import` with
   `{"fileType":"SQL","uri":"gs://kaaikani-escape-db-dumps/<newest>.sql.gz",
   "database":"wow_vendure"}`. First grant the Cloud SQL service account
   `roles/storage.objectViewer` on the dumps bucket.
4. **Create the app user with POST, never PUT.** A user created/updated via PUT
   gets only `GRANT USAGE` (powerless); POST-created users get full privileges.
5. **The import restores DATA but NOT GRANTS.** After import:
   `GRANT ALL PRIVILEGES ON \`wow_vendure\`.* TO 'admin'@'%'; FLUSH PRIVILEGES;`
   Symptom if skipped: `ER_DBACCESS_DENIED_ERROR 1044` and the app crash-loops.
6. Grant the **GKE node service account** (`<projnum>-compute@developer...`)
   `roles/artifactregistry.reader` or **no pod can pull any image**.
7. Cloud SQL connectivity: Autopilot **rotates node egress IPs**, so a /32
   allowlist breaks mid-run. Authorize every current node IP, or better,
   switch to Private IP / Cloud SQL Auth Proxy in a future revision.
8. **How to run the image** (was undocumented — had to be read off the live AWS
   cluster, which would NOT exist on escape day):
   - command: `node --max-old-space-size=2048 dist/src/index.js`
   - container port: **80** (`PORT=80`, `APP_ENV=production`)
   - env: everything from the `vendure-secrets` copy in GCP Secret Manager
9. Cloudflare (outside AWS) repoints domains — same one-record switch drilled
   three times on AWS.
10. Teardown: `terraform apply -var escape_active=false`.

## YOUR one-time setup (~15 min, needs your card)

1. https://console.cloud.google.com → create account (kaaikanimarketing@gmail.com)
2. Create project `kaaikani-escape` + enable billing
3. Install CLI: `sudo snap install google-cloud-cli --classic`
4. `gcloud auth application-default login` (browser opens; terraform uses this)
5. `gcloud config set project kaaikani-escape`
6. Tell Claude "GCP ready" → terraform apply in terraform/live/gcp-escape/

## AWS-side bridge (in prod root, dr_gcp_bridge.tf)

- S3 bucket `kaaikani-escape-dumps` (dump landing zone, 7-day lifecycle)
- IAM user `gcp-storage-transfer` scoped to read that bucket only
  (access key goes into the GCP transfer job — the ONLY AWS credential
  that lives in GCP, and it can read nothing but dumps)
- CronJob manifest environments/production/db-dump-cronjob.yaml
  (nightly 02:15 IST mysqldump → S3; ⚠ APPLY TO PROD ONLY AFTER REVIEW)
