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

Escape day: create GKE Autopilot (skeleton ready) → Cloud SQL import of the
latest GCS dump → deploy from Artifact Registry via the same charts →
Cloudflare (outside AWS) repoints domains. Untested until an escape drill.

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
