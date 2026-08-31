# GCP escape hatch -- see docs/dr/GCP-ESCAPE.md. Cold: buckets + registry are
# the only standing resources (<$10/mo). GKE/CloudSQL exist here as SKELETON
# ONLY (count = 0) -- applied during an actual escape or escape drill.
#
# Prereq: user's one-time GCP setup (project + billing + ADC login), then:
#   terraform init && terraform apply
# State: LOCAL and GITIGNORED (repo-wide *.tfstate rule -- it contains the
# scoped AWS transfer key). Escape day does NOT depend on this state: every
# resource here is name-stable (buckets, registry, transfer job), so a fresh
# machine can re-import or simply use them directly via gcloud/console.

terraform {
  required_version = ">= 1.11"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }
}

variable "project_id" {
  type    = string
  default = "kaaikani-escape"
}

variable "region" {
  type    = string
  default = "asia-south1" # GCP Mumbai
}

variable "aws_transfer_access_key_id" {
  description = "Access key of the AWS iam user gcp-storage-transfer (created by dr_gcp_bridge.tf). Set when enabling the transfer job."
  type        = string
  default     = ""
}

variable "aws_transfer_secret_key" {
  type      = string
  default   = ""
  sensitive = true
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# APIs enabled by terraform itself -- avoids needing `gcloud auth login`
# (ADC from application-default login is all terraform needs).
resource "google_project_service" "apis" {
  for_each = toset([
    "storage.googleapis.com",
    "artifactregistry.googleapis.com",
    "storagetransfer.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "container.googleapis.com",         # GKE
    "sqladmin.googleapis.com",          # Cloud SQL
    "compute.googleapis.com",           # VPC / NAT / addresses
    "servicenetworking.googleapis.com", # private services access (Cloud SQL private IP)
    "secretmanager.googleapis.com",     # secret copies consumed by external-secrets
    "iamcredentials.googleapis.com",    # workload identity token minting
    # Not needed to RUN the escape -- needed to inspect and clear the org
    # policy that blocks the GCS HMAC key. A rebuilt project inherits the same
    # secure-by-default constraints, and without this API the v2 `gcloud
    # org-policies` commands fail with a misleading PERMISSION_DENIED that
    # reads like a missing IAM role rather than a disabled service.
    "orgpolicy.googleapis.com",
  ])
  service            = each.value
  disable_on_destroy = false
}

# --- DB dumps land here (pulled daily from the S3 escape bucket) ---
resource "google_storage_bucket" "db_dumps" {
  name     = "${var.project_id}-db-dumps"
  location = var.region

  versioning {
    enabled = true
  }
  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type = "Delete"
    }
  }
  uniform_bucket_level_access = true
}

# --- quarterly gpg secrets exports ---
resource "google_storage_bucket" "secrets_export" {
  name     = "${var.project_id}-secrets-export"
  location = var.region
  versioning {
    enabled = true
  }
  uniform_bucket_level_access = true
}

# --- container images (CI pushes here in addition to ECR) ---
resource "google_artifact_registry_repository" "images" {
  repository_id = "kaaikani"
  format        = "DOCKER"
  location      = var.region
}

# The Storage Transfer service runs as a Google-managed service account that
# needs write access on the sink bucket -- without this the job creates but
# every run fails with PERMISSION_DENIED.
data "google_storage_transfer_project_service_account" "default" {
  depends_on = [google_project_service.apis]
}

resource "google_storage_bucket_iam_member" "transfer_writer" {
  bucket = google_storage_bucket.db_dumps.name
  role   = "roles/storage.admin"
  member = "serviceAccount:${data.google_storage_transfer_project_service_account.default.email}"
}

# --- daily pull of dumps from S3 (enabled once AWS bridge keys are set) ---
resource "google_storage_transfer_job" "s3_dumps" {
  count       = var.aws_transfer_access_key_id != "" ? 1 : 0
  description = "daily pull of DB dumps from s3://kaaikani-escape-dumps"

  transfer_spec {
    aws_s3_data_source {
      bucket_name = "kaaikani-escape-dumps"
      aws_access_key {
        access_key_id     = var.aws_transfer_access_key_id
        secret_access_key = var.aws_transfer_secret_key
      }
    }
    gcs_data_sink {
      bucket_name = google_storage_bucket.db_dumps.name
    }
  }

  schedule {
    schedule_start_date {
      year  = 2026
      month = 8
      day   = 4
    }
    start_time_of_day {
      hours   = 22 # 03:30 IST, after the 02:15 dump lands in S3
      minutes = 0
      seconds = 0
      nanos   = 0
    }
  }
}


# --- product images: the photos behind every storefront page. Mumbai->Hyderabad
# S3 CRR is AWS->AWS only; account death would take all 25k photos with it.
resource "google_storage_bucket" "assets" {
  name     = "${var.project_id}-assets"
  location = var.region
  versioning {
    enabled = true
  }
  uniform_bucket_level_access = true
}

resource "google_storage_bucket_iam_member" "transfer_writer_assets" {
  bucket = google_storage_bucket.assets.name
  role   = "roles/storage.admin"
  member = "serviceAccount:${data.google_storage_transfer_project_service_account.default.email}"
}

# Second assets bucket. ONE bucket per SOURCE bucket, and no `path` prefix on
# either sink -- this is a correctness fix, not tidiness.
#
# The original single-bucket layout wrote to gs://...-assets/cdn.kaaikani.co.in/
# so a photo living at s3://cdn.kaaikani.co.in/assets/x.jpg arrived as
# cdn.kaaikani.co.in/assets/x.jpg. Vendure asks its asset bucket for
# `assets/x.jpg`. Every product image would have 404'd on escape day, and
# drill #1 could not have caught it: it queried shop-api over JSON and never
# fetched an image body.
resource "google_storage_bucket" "assets_client" {
  name     = "${var.project_id}-assets-client"
  location = var.region
  versioning {
    enabled = true
  }
  uniform_bucket_level_access = true
}

resource "google_storage_bucket_iam_member" "transfer_writer_assets_client" {
  bucket = google_storage_bucket.assets_client.name
  role   = "roles/storage.admin"
  member = "serviceAccount:${data.google_storage_transfer_project_service_account.default.email}"
}

# Addresses changed from the old for_each; `moved` keeps this an in-place
# update instead of a destroy+create of working replication.
moved {
  from = google_storage_transfer_job.s3_assets["cdn.kaaikani.co.in"]
  to   = google_storage_transfer_job.s3_assets_cdn[0]
}

moved {
  from = google_storage_transfer_job.s3_assets["avsecomhub-clients-s3-images"]
  to   = google_storage_transfer_job.s3_assets_client[0]
}

resource "google_storage_transfer_job" "s3_assets_cdn" {
  count       = var.aws_transfer_access_key_id != "" ? 1 : 0
  description = "daily pull of product images from s3://cdn.kaaikani.co.in"

  transfer_spec {
    aws_s3_data_source {
      bucket_name = "cdn.kaaikani.co.in"
      aws_access_key {
        access_key_id     = var.aws_transfer_access_key_id
        secret_access_key = var.aws_transfer_secret_key
      }
    }
    gcs_data_sink {
      bucket_name = google_storage_bucket.assets.name
    }
  }

  schedule {
    schedule_start_date {
      year  = 2026
      month = 8
      day   = 4
    }
    start_time_of_day {
      hours   = 23 # 04:30 IST
      minutes = 0
      seconds = 0
      nanos   = 0
    }
  }
}

resource "google_storage_transfer_job" "s3_assets_client" {
  count       = var.aws_transfer_access_key_id != "" ? 1 : 0
  description = "daily pull of product images from s3://avsecomhub-clients-s3-images"

  transfer_spec {
    aws_s3_data_source {
      bucket_name = "avsecomhub-clients-s3-images"
      aws_access_key {
        access_key_id     = var.aws_transfer_access_key_id
        secret_access_key = var.aws_transfer_secret_key
      }
    }
    gcs_data_sink {
      bucket_name = google_storage_bucket.assets_client.name
    }
  }

  schedule {
    schedule_start_date {
      year  = 2026
      month = 8
      day   = 4
    }
    start_time_of_day {
      hours   = 23 # 04:30 IST
      minutes = 0
      seconds = 0
      nanos   = 0
    }
  }
}

# =============================================================================
# ESCAPE-DAY SKELETON -- count=0 until an actual escape/drill flips it on.
# GKE Autopilot: no node management, fastest possible bring-up, pay-per-pod.
# =============================================================================
variable "escape_active" {
  type    = bool
  default = false
}

resource "google_container_cluster" "escape" {
  count            = var.escape_active ? 1 : 0
  name             = "kaaikani-escape"
  location         = var.region
  enable_autopilot = true

  # Own VPC (escape_platform.tf) rather than `default`: Cloud SQL is reachable
  # over a private address, so the /32 allowlist race in ESCAPE PROCEDURE
  # step 7 -- Autopilot rotating node egress IPs out from under the allowlist
  # mid-drill -- cannot happen.
  network    = google_compute_network.escape.id
  subnetwork = google_compute_subnetwork.escape.id

  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }

  deletion_protection = false
}

# Cloud SQL instance names are QUARANTINED ~1 week after deletion -- hence the
# suffix variable: every drill bumps it (d1, d2, ...) instead of fighting the
# tombstone (drill-learning from AWS applied proactively).
variable "escape_db_suffix" {
  type    = string
  default = "d1"
}

resource "google_sql_database_instance" "escape" {
  count            = var.escape_active ? 1 : 0
  name             = "kaaikani-escape-db-${var.escape_db_suffix}"
  database_version = "MYSQL_8_0"
  region           = var.region

  deletion_protection = false

  settings {
    tier = "db-custom-2-8192" # 2 vCPU / 8 GB -- import of a ~5 GB raw dump in minutes not hours
    ip_configuration {
      # Private by default: the GKE cluster sits in the same VPC, so pods reach
      # the database over 10.x with NO authorized-network list to maintain and
      # NO public surface on an instance holding real customer data.
      # `escape_db_public_ip = true` restores the drill-#1 topology if the
      # private path fails on the day -- then authorized networks must be added
      # by hand, scoped to the node egress IPs, never 0.0.0.0/0.
      ipv4_enabled    = var.escape_db_public_ip
      private_network = google_compute_network.escape.id
    }
  }

  # The peering must exist before an instance can be given a private address.
  depends_on = [google_service_networking_connection.psa]
}

variable "escape_db_public_ip" {
  description = "Fallback to the drill-#1 public-IP topology. Leave false; private IP removes the node-IP allowlist race entirely."
  type        = bool
  default     = false
}

# One database per DB dumped by environments/production/db-dump-cronjob.yaml.
# The dumps are single-database mysqldumps (no --databases), so they carry NO
# "CREATE DATABASE" -- the target must already exist or the import fails with
# "No database selected". DRILL FINDING #10 fixed the dump side; this is the
# restore side of the same gap. Any new tenant DB must be added to BOTH lists.
resource "google_sql_database" "escape" {
  for_each = var.escape_active ? toset(["wow_vendure", "client_vendure"]) : toset([])
  name     = each.key
  instance = google_sql_database_instance.escape[0].name
}

output "escape_cluster_endpoint" {
  value = var.escape_active ? google_container_cluster.escape[0].endpoint : null
}
output "escape_cluster_ca" {
  value     = var.escape_active ? google_container_cluster.escape[0].master_auth[0].cluster_ca_certificate : null
  sensitive = true
}
# DB_HOST for the overlay. Private address unless the public fallback is on.
output "escape_db_ip" {
  value = var.escape_active ? (
    var.escape_db_public_ip
    ? google_sql_database_instance.escape[0].public_ip_address
    : google_sql_database_instance.escape[0].private_ip_address
  ) : null
}
