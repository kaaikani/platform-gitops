# DR Phase 1, Step 8 -- AWS Backup for the two standalone production EC2s.
#
# Delivery-partner (hosts Delivery-PWA + www.kaaikanistore.com, pm2 deploys)
# and GK_Construction (client site) have NO rebuild path -- no IaC, no image
# pipeline. Their 50 GB root disks are the only copy of those apps. User
# confirmed 2026-07-31: production, DR required.
#
# Mechanism: daily EBS-level backup at 20:00 UTC (01:30 AM IST, matches the
# RDS backup window -- our established low-traffic slot), kept 7 days locally,
# and every recovery point is COPIED to an ap-south-2 vault (also 7 days).
# DR restore: create AMI from the ap-south-2 recovery point -> launch -> DNS.
#
# Snapshots are incremental after the first; ~100 GB across both instances in
# both regions => roughly $8-12/mo.
#
# Monitoring PVCs (prometheus/grafana/loki/alertmanager, 75 GB) are deliberately
# NOT included -- metric history is accepted-loss (add their volume ARNs to the
# selection below if that decision changes).

# --- Vaults, one per region. Default AWS-managed backup KMS key in each.
resource "aws_backup_vault" "prod" {
  name = "vendure-prod-ec2"
  tags = { Project = var.project, Purpose = "dr" }
}

resource "aws_backup_vault" "dr" {
  provider = aws.dr
  name     = "vendure-dr-ec2"
  tags     = { Project = var.project, Purpose = "dr" }
}

# --- Service role AWS Backup assumes to snapshot and copy.
resource "aws_iam_role" "backup" {
  name = "vendure-aws-backup-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "backup.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = { Project = var.project, Purpose = "dr" }
}

resource "aws_iam_role_policy_attachment" "backup" {
  role       = aws_iam_role.backup.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
}

resource "aws_iam_role_policy_attachment" "backup_restore" {
  role       = aws_iam_role.backup.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForRestores"
}

# --- Plan: daily 01:30 AM IST, 7d local + 7d cross-region copy.
resource "aws_backup_plan" "ec2_dr" {
  name = "vendure-ec2-daily-dr"

  rule {
    rule_name         = "monthly-with-dr-copy"
    target_vault_name = aws_backup_vault.prod.name
    # 1st of every month, 20:00 UTC = 01:30 AM IST. Monthly is enough here:
    # app code redeploys from GitHub (GH Actions -> pm2); only the server
    # setup (nginx, pm2, SSL, site files) is unrecoverable, and it rarely
    # changes. User decision 2026-07-31 -- frequency barely moves the cost
    # anyway (snapshots are incremental), retention 35d keeps exactly one
    # (sometimes two) recovery points per region.
    schedule          = "cron(0 20 1 * ? *)"
    start_window      = 60
    completion_window = 300

    lifecycle {
      delete_after = 35
    }

    copy_action {
      destination_vault_arn = aws_backup_vault.dr.arn
      lifecycle {
        delete_after = 35
      }
    }
  }

  tags = { Project = var.project, Purpose = "dr" }
}

# --- Selection: exactly the two production instances (instance-level backup
# includes every attached volume).
resource "aws_backup_selection" "ec2_dr" {
  name         = "standalone-prod-ec2"
  plan_id      = aws_backup_plan.ec2_dr.id
  iam_role_arn = aws_iam_role.backup.arn

  resources = [
    aws_instance.delivery_partner.arn,
    aws_instance.gk_const.arn,
  ]
}
