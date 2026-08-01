# Secrets Manager — CONTAINERS ONLY. The secret VALUES live in a separate resource
# (aws_secretsmanager_secret_version) which we deliberately do NOT declare, so no
# credential ever enters Terraform state. Values stay managed out-of-band.
#
# DR (2026-07-31): every PROD secret has a replica in var.dr_region — AWS keeps
# the ap-south-2 copy in sync automatically, INCLUDING values updated out-of-band
# (replication happens at the service level, not through Terraform). This is the
# only copy of the generated values (COOKIE_SECRET, TOTP) outside ap-south-1.
# vendure/test/env deliberately NOT replicated — no DR value. ~$0.40/secret/mo.

resource "aws_secretsmanager_secret" "vendure_test_env" {
  name = "vendure/test/env"
}

resource "aws_secretsmanager_secret" "vendure_prod_database" {
  name = "vendure/prod/database"

  replica {
    region = var.dr_region
  }
}

resource "aws_secretsmanager_secret" "vendure_prod_redis" {
  name = "vendure/prod/redis"

  replica {
    region = var.dr_region
  }
}

resource "aws_secretsmanager_secret" "vendure_prod_aws_s3" {
  name = "vendure/prod/aws-s3"

  replica {
    region = var.dr_region
  }
}

resource "aws_secretsmanager_secret" "vendure_prod_smtps" {
  name = "vendure/prod/smtps"

  replica {
    region = var.dr_region
  }
}

resource "aws_secretsmanager_secret" "vendure_prod_integrations" {
  name = "vendure/prod/integrations"

  replica {
    region = var.dr_region
  }
}

resource "aws_secretsmanager_secret" "prod_storefronts" {
  name = "prod/storefronts"

  replica {
    region = var.dr_region
  }
}

resource "aws_secretsmanager_secret" "vendure_client_prod_all" {
  name = "vendure-client/prod/all"
  tags = {
    "vendure_client" = "prabasaaridesigns"
  }

  replica {
    region = var.dr_region
  }
}
