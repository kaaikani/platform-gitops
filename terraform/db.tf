resource "aws_db_instance" "prod_db" {
  lifecycle {
    prevent_destroy = true # guard: Terraform refuses to destroy/replace prod DB
  }

  identifier                      = "vendure-prod-db"
  engine                          = "mysql"
  engine_version                  = "8.0.45"
  instance_class                  = "db.t3.medium"
  allocated_storage               = 20
  storage_type                    = "gp3"
  storage_encrypted               = true
  username                        = "admin"
  port                            = 3306
  multi_az                        = false
  publicly_accessible             = false
  db_subnet_group_name            = "vendure-prod-db-subnet"
  parameter_group_name            = "aws-vendure-pg"
  backup_retention_period         = 1
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

resource "aws_db_instance" "test_db" {
  publicly_accessible          = true
  identifier                   = "test-db-1"
  engine                       = "mysql"
  engine_version               = "8.0.44"
  instance_class               = "db.t3.micro"
  allocated_storage            = 20
  storage_type                 = "gp3"
  storage_encrypted            = true
  username                     = "admin"
  port                         = 3306
  multi_az                     = false
  db_subnet_group_name         = "test_db_sn"
  parameter_group_name         = "test"
  backup_retention_period      = 0
  vpc_security_group_ids       = [aws_security_group.test_sg.id, "sg-0389219fe7a2bddbb"]
  copy_tags_to_snapshot        = true
  performance_insights_enabled = false
  skip_final_snapshot          = true
  apply_immediately            = false
  tags = {
    vendure = "RDS"
  }

}