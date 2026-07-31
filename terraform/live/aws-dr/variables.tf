variable "dr_region" {
  description = "DR region"
  type        = string
  default     = "ap-south-2"
}

variable "project" {
  type    = string
  default = "vendure"
}

variable "vpc_cidr" {
  description = "Non-overlapping with prod 10.10.0.0/16 and test 10.0.0.0/16 so the VPCs can be peered later if needed."
  type        = string
  default     = "10.20.0.0/16"
}

variable "cluster_name" {
  type    = string
  default = "vendure-dr-cluster"
}

variable "kube_version" {
  description = "Keep aligned with prod (terraform/eks.tf) -- drill fails fast if they drift apart."
  type        = string
  default     = "1.35"
}

variable "replicated_backup_arn" {
  description = "ARN of vendure-prod-db's replicated automated backups in the DR region. Look up: aws rds describe-db-instance-automated-backups --region ap-south-2 --query 'DBInstanceAutomatedBackups[0].DBInstanceAutomatedBackupsArn' --output text"
  type        = string

  validation {
    condition     = startswith(var.replicated_backup_arn, "arn:aws:rds:")
    error_message = "Must be an RDS automated-backups ARN (arn:aws:rds:...:auto-backup:...)."
  }
}

variable "restore_use_latest" {
  description = "Restore the DB to the latest restorable time from the replicated backups. Set false + restore_time for point-in-time (e.g. before a corruption event)."
  type        = bool
  default     = true
}

variable "restore_time" {
  description = "RFC3339 UTC timestamp to restore to when restore_use_latest = false."
  type        = string
  default     = null
}
