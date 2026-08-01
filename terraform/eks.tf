resource "aws_eks_cluster" "prod_eks" {
  name                          = "vendure-prod-cluster"
  version                       = "1.35"
  role_arn                      = aws_iam_role.eks_cluster.arn
  bootstrap_self_managed_addons = false

  lifecycle {
    prevent_destroy = true # guard: never destroy/replace the prod EKS control plane
  }

  vpc_config {
    subnet_ids              = [aws_subnet.public_1a.id, aws_subnet.public_2b.id, aws_subnet.public_3c.id]
    endpoint_public_access  = true
    endpoint_private_access = true
    public_access_cidrs     = ["0.0.0.0/0"]
  }
  encryption_config {
    resources = ["secrets"]
    provider {
      # Same key as before, looked up instead of a hardcoded ARN. The key itself
      # stays unmanaged (KMS keys are never recreated in place); the DR module
      # creates its own key -- see terraform/live/aws-dr.
      key_arn = data.aws_kms_key.eks_secrets.arn
    }
  }
  tags = {
    "alpha.eksctl.io/cluster-oidc-enabled" = "true"
  }
  compute_config {
    enabled = false
  }

  storage_config {
    block_storage {
      enabled = false
    }
  }

  zonal_shift_config {
    enabled = true
  }
}
# EKS managed node groups moved to node_groups.tf (refactored into modules/node_group)
# The EKS secrets-encryption key, previously a hardcoded ARN. Unmanaged on
# purpose: this key can never be replaced on a live cluster (encryption_config
# is immutable), so importing it buys nothing. DR creates its own key.
data "aws_kms_key" "eks_secrets" {
  key_id = "559f6913-83a0-4d22-8d55-58dd0d60fc1e"
}
