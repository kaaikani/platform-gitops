# DR Phase 1, Step 2 -- RDS cross-region automated backup replication.
#
# Indha list la MOST IMPORTANT item. Unga orders, customers, Razorpay payment
# records -- ivai ellathukum vera copy kidaiyaadhu. S3 image pona thirumba
# upload pannalaam, ECR image pona GitHub la irundhu rebuild pannalaam, aana
# order table pona business pochu.
#
# Read replica ($55/mo) illa, backup replication ($1-2/mo). Vithiyaasam:
#   read replica       -> RPO few seconds, promote panna ~5 min
#   backup replication -> RPO 15-30 min,   restore panna ~30-45 min
# Multi-AZ vendam nu decide panna adhe logic -- idle standby ku panam illa.
#
# Source DB la backup ON irukanum (namma retention 3 nu vechirukom) -- illana
# indha resource create aagaadhu.
resource "aws_db_instance_automated_backups_replication" "prod_db" {
  provider = aws.dr # DESTINATION region la dhaan indha resource iruka vendum

  source_db_instance_arn = aws_db_instance.prod_db.arn
  retention_period       = aws_db_instance.prod_db.backup_retention_period
  kms_key_id             = aws_kms_key.dr_rds.arn
}
