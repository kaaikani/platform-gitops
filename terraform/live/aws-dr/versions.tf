# DR root module -- ap-south-2 (Hyderabad). NOT applied in normal operation:
# this code is the "kitchen blueprint"; Phase 1 already replicated every
# ingredient (RDS backups, images, secrets, DNS switch). Applied only during
# a regional failover or a quarterly drill, then destroyed after drills.
#
# State: same bucket as prod but its own key. The bucket is CRR-replicated to
# kaaikani-tfstate-dr-149536454380 (ap-south-2). If ap-south-1 is DOWN, init
# against the replica instead:
#   terraform init -backend-config="bucket=kaaikani-tfstate-dr-149536454380" \
#                  -backend-config="region=ap-south-2"
# (dr/terraform.tfstate will not exist there on first failover -- that is fine,
# it starts empty; what matters is we can WRITE state somewhere durable.)

terraform {
  required_version = ">= 1.11"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }

  backend "s3" {
    bucket       = "kaaikani-tfstate-149536454380"
    key          = "dr/terraform.tfstate"
    region       = "ap-south-1"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region = var.dr_region
}
