provider "aws" {
  region = var.aws_region
  # No hardcoded profile: locally set AWS_PROFILE=terraform-admin;
  # in CI, credentials come from the OIDC-assumed role.
}