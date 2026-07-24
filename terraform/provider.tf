provider "aws" {
  region = "ap-south-1"
  # No hardcoded profile: locally set AWS_PROFILE=terraform-admin;
  # in CI, credentials come from the OIDC-assumed role.
}