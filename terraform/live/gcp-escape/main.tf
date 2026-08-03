# GCP escape hatch -- see docs/dr/GCP-ESCAPE.md. Cold: buckets + registry are
# the only standing resources (<$10/mo). GKE/CloudSQL exist here as SKELETON
# ONLY (count = 0) -- applied during an actual escape or escape drill.
#
# Prereq: user's one-time GCP setup (project + billing + ADC login), then:
#   terraform init && terraform apply
# State: LOCAL on purpose (terraform.tfstate in this directory, committed to
# the PRIVATE repo). The whole point is surviving AWS-account death -- state
# in the S3 backend would die with it. GitHub is the off-cloud store.

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
  name                        = "${var.project_id}-secrets-export"
  location                    = var.region
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
