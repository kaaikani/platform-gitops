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
resource "aws_eks_node_group" "prod_eks_ng" {
  cluster_name = aws_eks_cluster.prod_eks.name
  node_group_name = "vendure-prod-app-ng-x86"
  node_role_arn = "arn:aws:iam::149536454380:role/vendure-prod-eks-node-role"
  subnet_ids = [aws_subnet.public_1a.id, aws_subnet.public_2b.id, aws_subnet.public_3c.id]
  instance_types = ["t3a.medium"]
  capacity_type = "ON_DEMAND"
  ami_type = "AL2023_x86_64_STANDARD"
  disk_size = 20
  version = "1.35"
  scaling_config {
    desired_size = 0
    max_size     = 2
    min_size     = 0
  }
  labels = {environment = "production",node-group ="vendure"}
  tags = { Project = "vendure", Environment = "production", ManagedBy = "aws-cli" }

}
resource "aws_eks_node_group" "prod_eks_platform_ng" {
  cluster_name   = aws_eks_cluster.prod_eks.name
  node_role_arn  = "arn:aws:iam::149536454380:role/vendure-prod-eks-node-role"
  subnet_ids     = [aws_subnet.public_1a.id, aws_subnet.public_2b.id, aws_subnet.public_3c.id]
  capacity_type  = "ON_DEMAND"
  ami_type       = "AL2023_x86_64_STANDARD"
  disk_size      = 20
  version        = "1.35"
  node_group_name = "vendure-prod-platform-ng"
  instance_types = ["t3a.large"]
  scaling_config {
    min_size = 1
    max_size = 2
    desired_size = 1
  }
  labels = { environment = "production", node-group = "platform" }
  tags = {}
}

resource "aws_eks_node_group" "prod_eks_storefront_ng" {
    cluster_name   = aws_eks_cluster.prod_eks.name
    node_role_arn  = "arn:aws:iam::149536454380:role/vendure-prod-eks-node-role"
    subnet_ids     = [aws_subnet.public_1a.id, aws_subnet.public_2b.id, aws_subnet.public_3c.id]
    capacity_type  = "ON_DEMAND"
    ami_type       = "AL2023_x86_64_STANDARD"
    disk_size      = 20
    version        = "1.35"
    node_group_name = "vendure-prod-storefront-ng-medium"
    instance_types = ["t3a.medium"]
    scaling_config {
        min_size = 1
        max_size = 2
        desired_size = 1    
    }
    labels = { environment = "production", node-group = "storefront" }
    tags = { Project = "vendure", Environment = "production", InstanceType = "t3a.medium", Name = "vendure-prod-storefront-ng-medium" }
}