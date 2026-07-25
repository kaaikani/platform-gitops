# --- Supporting resources the prod RDS depends on ---

resource "aws_db_subnet_group" "prod" {
  name        = "vendure-prod-db-subnet"
  description = "Private subnets for Vendure RDS"
  subnet_ids  = [aws_subnet.private_1a.id, aws_subnet.private_2b.id, aws_subnet.private_3c.id]
}

resource "aws_db_parameter_group" "prod" {
  name        = "aws-vendure-pg"
  family      = "mysql8.0"
  description = "Time zone changes " # trailing space is intentional — matches AWS exactly

  parameter {
    name         = "long_query_time"
    value        = "1"
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
