# DR database: restored FROM the replicated automated backups that Phase 1
# streams into this region (dr_rds.tf in the prod root). RPO 15-30 min.

resource "aws_db_subnet_group" "dr" {
  name        = "${var.project}-dr-db-subnet"
  description = "Private subnets for the DR-restored RDS"
  subnet_ids  = aws_subnet.private[*].id
}

# Same tuning as prod's aws-vendure-pg (rds_support.tf), including the
# log_output=FILE fix.
resource "aws_db_parameter_group" "dr" {
  name        = "${var.project}-dr-pg"
  family      = "mysql8.0"
  description = "DR copy of aws-vendure-pg"

  parameter {
    name         = "long_query_time"
    value        = "1"
    apply_method = "immediate"
  }
  parameter {
    name         = "log_output"
    value        = "FILE"
    apply_method = "immediate"
  }
  parameter {
    name         = "max_allowed_packet"
    value        = "67108864"
    apply_method = "immediate"
  }
  parameter {
    name         = "net_read_timeout"
    value        = "120"
    apply_method = "immediate"
  }
  parameter {
    name         = "net_write_timeout"
    value        = "300"
    apply_method = "immediate"
  }
  parameter {
    name         = "slow_query_log"
    value        = "1"
    apply_method = "immediate"
  }
  parameter {
    name         = "time_zone"
    value        = "Asia/Calcutta"
    apply_method = "immediate"
  }
  parameter {
    name         = "wait_timeout"
    value        = "300"
    apply_method = "immediate"
  }
}

resource "aws_db_instance" "dr" {
  identifier     = "${var.project}-dr-db"
  instance_class = "db.t3.medium"

  restore_to_point_in_time {
    # No data source exists for replicated backups; the ARN is an input.
    # Look it up at failover/drill time (runbook step):
    #   aws rds describe-db-instance-automated-backups --region ap-south-2 \
    #     --query 'DBInstanceAutomatedBackups[0].DBInstanceAutomatedBackupsArn' --output text
    source_db_instance_automated_backups_arn = var.replicated_backup_arn
    use_latest_restorable_time               = var.restore_use_latest
    restore_time                             = var.restore_use_latest ? null : var.restore_time
  }

  db_subnet_group_name   = aws_db_subnet_group.dr.name
  parameter_group_name   = aws_db_parameter_group.dr.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false
  multi_az               = false

  # Post-restore posture: backups ON immediately -- the DR db IS prod while
  # the failover lasts.
  backup_retention_period = 3
  deletion_protection     = true
  copy_tags_to_snapshot   = true
  skip_final_snapshot     = false

  tags = { Project = var.project, Environment = "dr" }
}
