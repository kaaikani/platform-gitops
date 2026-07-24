# ECR repositories (the repos themselves — images inside are pushed by CI/CD, not Terraform).
# Encryption is AES256 (default) on all, so encryption_configuration is omitted (computed-clean).
# Lifecycle policies are a SEPARATE resource (aws_ecr_lifecycle_policy) and are left unmanaged
# here; add them deliberately later (3 repos currently lack one).
# NOTE: empty repo "client_vendure" intentionally NOT imported — it's a deletion candidate.

resource "aws_ecr_repository" "vendure_prod" {
  name                 = "vendure-prod"
  image_tag_mutability = "IMMUTABLE"
  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_repository" "prabasaaridesigns" {
  name                 = "prabasaaridesigns"
  image_tag_mutability = "IMMUTABLE"
  image_scanning_configuration {
    scan_on_push = false
  }
}

resource "aws_ecr_repository" "vendure_test" {
  name                 = "vendure-test"
  image_tag_mutability = "IMMUTABLE"
  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_repository" "southmithai" {
  name                 = "southmithai"
  image_tag_mutability = "IMMUTABLE"
  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_repository" "swadkerala" {
  name                 = "swadkerala"
  image_tag_mutability = "IMMUTABLE"
  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_repository" "kaaikanistore" {
  name                 = "kaaikanistore"
  image_tag_mutability = "IMMUTABLE"
  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_repository" "vendure_client" {
  name                 = "vendure-client"
  image_tag_mutability = "IMMUTABLE"
  image_scanning_configuration {
    scan_on_push = true
  }
}
