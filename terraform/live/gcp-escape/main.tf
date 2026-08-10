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
    "container.googleapis.com", # GKE
    "sqladmin.googleapis.com",  # Cloud SQL
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

resource "google_storage_transfer_job" "s3_assets" {
  for_each = var.aws_transfer_access_key_id != "" ? toset(["cdn.kaaikani.co.in", "avsecomhub-clients-s3-images"]) : toset([])

  description = "daily pull of product images from s3://${each.key}"

  transfer_spec {
    aws_s3_data_source {
      bucket_name = each.key
      aws_access_key {
        access_key_id     = var.aws_transfer_access_key_id
        secret_access_key = var.aws_transfer_secret_key
      }
    }
    gcs_data_sink {
      bucket_name = google_storage_bucket.assets.name
      path        = "${each.key}/"
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
      ipv4_enabled = true
      # authorized networks added AT DRILL TIME scoped to the GKE egress IP --
      # never 0.0.0.0/0, this instance holds real production data
    }
  }
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
output "escape_db_ip" {
  value = var.escape_active ? google_sql_database_instance.escape[0].public_ip_address : null
}
