# =============================================================================
# ESCAPE PLATFORM -- everything drill #1 had to do BY HAND, plus the pieces
# drill #1 never exercised at all.
#
# Drill #1 proved ONE app (vendure-prod / wow_vendure) could serve from GKE.
# It did not prove: the other five workloads, TLS, outbound internet, asset
# WRITES, or secret delivery. This file closes those.
#
# Standing cost: network resources only (VPC, subnet, PSA range) = FREE.
# Everything with an hourly meter (NAT, GKE, Cloud SQL) stays count=0 until
# escape_active flips. Cost target of <$10/mo is unchanged.
#
# ⚠ NOT YET DRILLED. Drill #1 used the default VPC and a public-IP Cloud SQL.
# This file moves the database to a PRIVATE ip and the cluster into its own
# VPC -- correct, but unproven. Escape drill #2 must run before this is
# trusted. `escape_db_public_ip = true` restores the drill-#1 topology if the
# private path misbehaves on the day.
# =============================================================================

data "google_project" "this" {}

# -----------------------------------------------------------------------------
# FULL S3 PARITY -- every remaining production bucket.
#
# The escape hatch replicated three buckets: the dumps and the two the app's
# `s3.bucket` values named. That was the wrong test. The question is not "what
# does the app read at runtime" but "what production data exists only in AWS".
# Four buckets failed that test and had NO copy outside the account:
#
#   vendure-images-backup      5,682 objects / 525 MB  -- the image backup set
#   prabhasaaridesigns             8 objects / 9.9 MB
#   wow-vendure                    1 object  / 641 B
#   daily-order-sales-reports      1 object  / 227 B
#
# Regional DR already covers them by S3 CRR to ap-south-2. Account-level DR did
# not, so losing the account lost them permanently. ~535 MB total; the entire
# gap costs about $0.06 of egress to close.
#
# One GCS bucket per source bucket with no path prefix, so object keys stay
# identical to S3 -- the same fidelity rule the asset buckets now follow.
# -----------------------------------------------------------------------------
locals {
  mirrored_buckets = {
    "vendure-images-backup"     = "kaaikani-escape-images-backup"
    "prabhasaaridesigns"        = "kaaikani-escape-prabhasaaridesigns"
    "wow-vendure"               = "kaaikani-escape-wow-vendure"
    "daily-order-sales-reports" = "kaaikani-escape-order-reports"
    # ⚠ CONTAINS PLAINTEXT SECRETS. Terraform state records every resource
    # attribute, including database passwords and keys that were never meant to
    # leave AWS. It is mirrored because it is the only record of what the AWS
    # platform actually was -- the .tf code on GitHub has no resource ids and no
    # imported settings. Treat this bucket as a credential store: uniform
    # bucket-level access, no public reader, no broad IAM grant. Nothing in the
    # escape path reads it; it is reference material for rebuilding later.
    "kaaikani-tfstate-149536454380" = "kaaikani-escape-tfstate"
  }
}

resource "google_storage_bucket" "mirror" {
  for_each = local.mirrored_buckets
  name     = each.value
  location = var.region
  versioning {
    enabled = true
  }
  uniform_bucket_level_access = true
}

resource "google_storage_bucket_iam_member" "mirror_writer" {
  for_each = local.mirrored_buckets
  bucket   = google_storage_bucket.mirror[each.key].name
  role     = "roles/storage.admin"
  member   = "serviceAccount:${data.google_storage_transfer_project_service_account.default.email}"
}

# Gated on the AWS key like every other job: no credentials means no job, and
# an apply without them must not look like a reason to tear replication down.
resource "google_storage_transfer_job" "mirror" {
  for_each    = var.aws_transfer_access_key_id != "" ? local.mirrored_buckets : {}
  description = "daily pull from s3://${each.key}"

  transfer_spec {
    aws_s3_data_source {
      bucket_name = each.key
      aws_access_key {
        access_key_id     = var.aws_transfer_access_key_id
        secret_access_key = var.aws_transfer_secret_key
      }
    }
    gcs_data_sink {
      bucket_name = google_storage_bucket.mirror[each.key].name
    }
  }

  schedule {
    schedule_start_date {
      year  = 2026
      month = 8
      day   = 13
    }
    start_time_of_day {
      hours   = 23 # 04:30 IST, alongside the image mirrors
      minutes = 30
      seconds = 0
      nanos   = 0
    }
  }

  depends_on = [google_storage_bucket_iam_member.mirror_writer]
}

# -----------------------------------------------------------------------------
# NETWORK -- standing and free. Exists so escape day does not also have to be
# network-design day.
# -----------------------------------------------------------------------------
resource "google_compute_network" "escape" {
  name                    = "kaaikani-escape"
  auto_create_subnetworks = false
  depends_on              = [google_project_service.apis]
}

resource "google_compute_subnetwork" "escape" {
  name          = "kaaikani-escape-${var.region}"
  ip_cidr_range = "10.10.0.0/20"
  region        = var.region
  network       = google_compute_network.escape.id

  # Autopilot is VPC-native and REQUIRES both secondary ranges.
  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = "10.20.0.0/14"
  }
  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = "10.24.0.0/20"
  }

  # Lets nodes reach Artifact Registry / GCS / Secret Manager without egressing
  # to the internet -- image pulls keep working even before NAT is up.
  private_ip_google_access = true
}

# Private Services Access: the peering range Cloud SQL's private IP is carved
# from. Reserving it costs nothing; creating it ON escape day costs ~10 min.
resource "google_compute_global_address" "psa" {
  name          = "kaaikani-escape-psa"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = google_compute_network.escape.id
}

resource "google_service_networking_connection" "psa" {
  network                 = google_compute_network.escape.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.psa.name]
  depends_on              = [google_project_service.apis]
}

# -----------------------------------------------------------------------------
# EGRESS -- metered, so escape-only.
#
# GAP FOUND WHILE WIRING THIS: Autopilot nodes have no public IPs. Without NAT
# the pods can reach Google APIs (private access, above) but NOT Razorpay,
# MSG91, Shiprocket or Bluedart. Checkout and OTP would fail on escape day
# with the app otherwise looking perfectly healthy -- drill #1 never noticed
# because it only ran read-only shop-api queries.
# -----------------------------------------------------------------------------
resource "google_compute_router" "escape" {
  count   = var.escape_active ? 1 : 0
  name    = "kaaikani-escape-router"
  region  = var.region
  network = google_compute_network.escape.id
}

resource "google_compute_router_nat" "escape" {
  count                              = var.escape_active ? 1 : 0
  name                               = "kaaikani-escape-nat"
  router                             = google_compute_router.escape[0].name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# -----------------------------------------------------------------------------
# IAM -- the two grants drill #1 had to discover live, now pre-wired.
# -----------------------------------------------------------------------------

# DRILL FINDING #6: without this NO pod can pull ANY image. It was found by
# watching ImagePullBackOff for several minutes on the day.
resource "google_project_iam_member" "gke_nodes_pull" {
  project = var.project_id
  role    = "roles/artifactregistry.reader"
  member  = "serviceAccount:${data.google_project.this.number}-compute@developer.gserviceaccount.com"
}

# ESCAPE PROCEDURE step 3: Cloud SQL's per-instance service account must be
# able to read the dump objects or the import fails. The SA only exists once
# the instance does, hence the count gate.
resource "google_storage_bucket_iam_member" "sql_reads_dumps" {
  count  = var.escape_active ? 1 : 0
  bucket = google_storage_bucket.db_dumps.name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_sql_database_instance.escape[0].service_account_email_address}"
}

# -----------------------------------------------------------------------------
# SECRET DELIVERY -- external-secrets on GKE reads GCP Secret Manager through
# Workload Identity. Closes the gap where drill #1 hand-fed env vars, which is
# not a thing anyone should be doing during an outage.
# -----------------------------------------------------------------------------
resource "google_service_account" "external_secrets" {
  account_id   = "external-secrets"
  display_name = "external-secrets operator (GKE escape cluster)"
}

resource "google_project_iam_member" "external_secrets_accessor" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.external_secrets.email}"
}

# Binds the KSA external-secrets/external-secrets to the GSA above. Applied
# standing so escape day is a plain `helm install`, no IAM archaeology.
resource "google_service_account_iam_member" "external_secrets_wi" {
  service_account_id = google_service_account.external_secrets.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[external-secrets/external-secrets]"
}

# -----------------------------------------------------------------------------
# ASSET WRITES -- the gap that would have surfaced on escape day the first time
# a customer or admin uploaded a product photo.
#
# The mirrored buckets are a one-way READ copy. Vendure's S3AssetStorageStrategy
# needs somewhere to PUT new objects. GCS speaks the S3 XML API, so an HMAC key
# makes the existing, unmodified app code write to GCS with no image rebuild --
# the app never learns it left AWS.
# -----------------------------------------------------------------------------
resource "google_service_account" "assets" {
  account_id   = "vendure-assets"
  display_name = "Vendure asset read/write (S3-interop HMAC)"
}

resource "google_storage_bucket_iam_member" "assets_rw" {
  bucket = google_storage_bucket.assets.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.assets.email}"
}

resource "google_storage_bucket_iam_member" "assets_client_rw" {
  bucket = google_storage_bucket.assets_client.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.assets.email}"
}

resource "google_storage_hmac_key" "assets" {
  service_account_email = google_service_account.assets.email
}

# Shaped to match the AWS secret vendure/prod/aws-s3 KEY FOR KEY, because the
# chart's ExternalSecret does `dataFrom: extract` and the deployment reads
# AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY / AWS_REGION out of the result.
# Pointing externalSecrets.awsSecrets.awsS3 at this secret is the entire
# app-side change. AWS_REGION is unused by GCS but must exist -- the container
# has a secretKeyRef on it and would fail to start if the key were absent.
resource "google_secret_manager_secret" "assets_s3" {
  secret_id = "vendure_gcp_assets"
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "assets_s3" {
  secret = google_secret_manager_secret.assets_s3.id
  secret_data = jsonencode({
    AWS_ACCESS_KEY_ID     = google_storage_hmac_key.assets.access_id
    AWS_SECRET_ACCESS_KEY = google_storage_hmac_key.assets.secret
    AWS_REGION            = var.region
  })
}

# -----------------------------------------------------------------------------
# TLS -- containers only; the material is uploaded out of band (see
# docs/dr/GCP-ESCAPE.md "TLS on escape day").
#
# A Cloudflare Origin CA certificate is used rather than a Google-managed one
# because managed certs only provision AFTER dns already points at the load
# balancer -- 15-60 min of TLS errors in the middle of an outage. The origin
# cert is issued NOW, is valid 15 years, and is trusted by Cloudflare the
# instant traffic flips. It is also cloud-neutral: the same secret works in
# AWS, GCP or anywhere else.
# -----------------------------------------------------------------------------
# -----------------------------------------------------------------------------
# DATABASE CONNECTION SECRETS -- containers only.
#
# The mirrored vendure_prod_database points at the AWS RDS endpoint, which is
# exactly the thing that no longer exists on escape day. These hold the Cloud
# SQL coordinates instead and are populated in ESCAPE PROCEDURE step 5, once
# the instance has an address and the app user has been created.
# -----------------------------------------------------------------------------
resource "google_secret_manager_secret" "db_wow" {
  secret_id = "vendure_gcp_database"
  replication {
    auto {}
  }
}

# vendure-client keeps EVERYTHING in one secret (vendure-client/prod/all), and
# the chart's ExternalSecret extracts the five keys in a fixed order where
# later extracts overwrite earlier ones. Pointing only `database` at a GCP
# secret would therefore be undone two lines later when `smtps` re-extracted
# the all-secret and put the dead RDS endpoint back. So the client gets ONE
# merged secret instead; GCP-ESCAPE.md step 5 has the jq one-liner that builds
# it from the mirrored copy.
resource "google_secret_manager_secret" "client_all" {
  secret_id = "vendure_client_gcp_all"
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret" "tls_cert" {
  secret_id = "cf_origin_tls_crt"
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret" "tls_key" {
  secret_id = "cf_origin_tls_key"
  replication {
    auto {}
  }
}

output "assets_hmac_access_id" {
  value = google_storage_hmac_key.assets.access_id
}

output "escape_network" {
  value = google_compute_network.escape.name
}
