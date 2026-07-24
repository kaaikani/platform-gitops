resource "aws_eks_cluster" "prod_eks" {
  name = "vendure-prod-cluster"
  version = "1.35"
  role_arn = "arn:aws:iam::149536454380:role/vendure-production-eks-cluster-role"
  bootstrap_self_managed_addons = false          # ← ADD (stops replacement #1)

  vpc_config {
    subnet_ids =[aws_subnet.public_1a.id, aws_subnet.public_2b.id, aws_subnet.public_3c.id]
    endpoint_public_access = true
    endpoint_private_access = true
    public_access_cidrs = ["0.0.0.0/0"]
  }
  encryption_config {                            # ← ADD whole block (stops replacement #2)
    resources = ["secrets"]
    provider {
      key_arn = "arn:aws:kms:ap-south-1:149536454380:key/559f6913-83a0-4d22-8d55-58dd0d60fc1e"
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