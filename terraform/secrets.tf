# Secrets Manager — CONTAINERS ONLY. The secret VALUES live in a separate resource
# (aws_secretsmanager_secret_version) which we deliberately do NOT declare, so no
# credential ever enters Terraform state. Values stay managed out-of-band.

resource "aws_secretsmanager_secret" "vendure_test_env" {
  name = "vendure/test/env"
}

resource "aws_secretsmanager_secret" "vendure_prod_database" {
  name = "vendure/prod/database"
}

resource "aws_secretsmanager_secret" "vendure_prod_redis" {
  name = "vendure/prod/redis"
}

resource "aws_secretsmanager_secret" "vendure_prod_aws_s3" {
  name = "vendure/prod/aws-s3"
}

resource "aws_secretsmanager_secret" "vendure_prod_smtps" {
  name = "vendure/prod/smtps"
}

resource "aws_secretsmanager_secret" "vendure_prod_integrations" {
  name = "vendure/prod/integrations"
}

resource "aws_secretsmanager_secret" "prod_storefronts" {
  name = "prod/storefronts"
}

resource "aws_secretsmanager_secret" "vendure_client_prod_all" {
  name = "vendure-client/prod/all"
  tags = {
    "vendure_client" = "prabasaaridesigns"
  }
}
