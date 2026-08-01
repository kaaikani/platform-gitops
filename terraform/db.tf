resource "aws_db_instance" "prod_db" {
  lifecycle {
    prevent_destroy = true # guard: Terraform refuses to destroy/replace prod DB
  }

  identifier        = "vendure-prod-db"
  engine            = "mysql"
  engine_version    = "8.0.45"
  instance_class    = "db.t3.medium"
  allocated_storage = 20
  # 20 GB la ~10 GB already use aagirukku (50%). Storage full aana RDS read-only
  # aagi production down aagum. Idhu adha thadukkum -- AWS thaana 30 GB varaikum
  # valarthidum. Grow aagala na cost ZERO. Aana kavanam: RDS storage kootha
  # mattum dhaan mudiyum, kammi panna mudiyadhu (dump/restore thaan vazhi).
  max_allocated_storage = 30
  storage_type          = "gp3"
  storage_encrypted     = true
  username              = "admin"
  port                  = 3306
  multi_az              = false
  publicly_accessible   = false
  # Resource references, not name strings -- Terraform now knows the dependency
  # graph, and the same code can build these in an empty region (DR).
  db_subnet_group_name = aws_db_subnet_group.prod.name
  parameter_group_name = aws_db_parameter_group.prod.name
  # 1 -> 3. Naal ku 1+ deploy pannurom, 42% Fri/Sat/Sun la. 1 naal vechirundha
  # velli deploy corruption ah thinkal kaalai kandupidichaalum restore point
  # illa. 3 naal andha weekend gap ah cover pannum -- adhu dhaan minimum.
  # Multi-AZ vendam nu decide panniruka, so backup dhaan namma ore recovery.
  # Non-zero se non-zero maathradhu la outage illa (0 <-> non-zero mattum reboot).
  # Data 10 GB, AWS free backup allowance 20 GB -> cost $0.
  backup_retention_period = 3

  # Windows UTC la. Munnadi maintenance "wed:02:36-wed:03:06" UTC = Buthan kaalai
  # 08:06 IST -- ecommerce ku business hours. Maintenance window la AWS OS patching
  # + minor engine auto-upgrade pannum, adhu single-AZ la REBOOT = downtime. Adhaan
  # rendayum India kammi-traffic neram (1-4 AM IST) ku nagarthirukom.
  #   backup      20:00-20:30 UTC = dhinam 01:30-02:00 AM IST
  #   maintenance tue:21:30-22:30 UTC = Buthan 03:00-04:00 AM IST
  # Rendum overlap aagakoodadhu -- AWS reject pannum. Window maathradhu zero downtime.
  backup_window      = "20:00-20:30"
  maintenance_window = "tue:21:30-tue:22:30"

  deletion_protection             = true
  vpc_security_group_ids          = [aws_security_group.rds.id]
  copy_tags_to_snapshot           = true
  enabled_cloudwatch_logs_exports = ["audit", "error", "slowquery"]
  performance_insights_enabled    = true
  skip_final_snapshot             = false
  apply_immediately               = false
  tags = {
    vendure = "RDS"
  }
}

# `test-db-1` 2026-07-30 varaikum AWS la illa (DBInstanceNotFound) -- console la
# irundhu delete pannirukku. Aana state la innum entry irundhadhaala Terraform
# adha "missing" nu paathu THIRUMBA CREATE panna plan panniduchu ($15/mo,
# publicly_accessible=true, test_sg la 3306 0.0.0.0/0 ku open).
#
# Adhaan indha resource block ah eduthittom. AWS la object illa + config la
# block illa = Terraform onnume pannaadhu, destroy um illa. `state rm` thevai illa.
#
# PAADAM: drift detection illaama, oru console-side delete apdiye ORE
# `terraform apply` la reverse aagum -- CI la auto-apply irukkurathunala
# sambandham illaadha oru PR merge pannina kooda idhu nadandhudum.
#
# resource "aws_db_instance" "test_db" {
#   publicly_accessible          = true
#   identifier                   = "test-db-1"
#   engine                       = "mysql"
#   engine_version               = "8.0.44"
#   instance_class               = "db.t3.micro"
#   allocated_storage            = 20
#   storage_type                 = "gp3"
#   storage_encrypted            = true
#   username                     = "admin"
#   port                         = 3306
#   multi_az                     = false
#   db_subnet_group_name         = "test_db_sn"
#   parameter_group_name         = "test"
#   backup_retention_period      = 0
#   vpc_security_group_ids       = [aws_security_group.test_sg.id, "sg-0389219fe7a2bddbb"]
#   copy_tags_to_snapshot        = true
#   performance_insights_enabled = false
#   skip_final_snapshot          = true
#   apply_immediately            = false
#   tags = {
#     vendure = "RDS"
#   }
# }