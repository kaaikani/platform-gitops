# --- EKS managed node groups, built from the reusable ./modules/node_group ---
# Only the values that DIFFER per node group are passed here; the shared defaults
# (ami_type, capacity_type, disk_size, kube_version) live in the module.

module "app_ng" {
  source = "./modules/node_group"

  cluster_name    = aws_eks_cluster.prod_eks.name
  node_group_name = "vendure-prod-app-ng-x86"
  node_role_arn   = "arn:aws:iam::149536454380:role/vendure-prod-eks-node-role"
  subnet_ids      = [aws_subnet.public_1a.id, aws_subnet.public_2b.id, aws_subnet.public_3c.id]
  instance_types  = ["t3a.medium"]
  min_size        = 0
  max_size        = 2
  desired_size    = 0
  labels          = { environment = "production", node-group = "vendure" }
  tags            = { Project = "vendure", Environment = "production", ManagedBy = "aws-cli" }
}

module "platform_ng" {
  source = "./modules/node_group"

  cluster_name    = aws_eks_cluster.prod_eks.name
  node_group_name = "vendure-prod-platform-ng"
  node_role_arn   = "arn:aws:iam::149536454380:role/vendure-prod-eks-node-role"
  subnet_ids      = [aws_subnet.public_1a.id, aws_subnet.public_2b.id, aws_subnet.public_3c.id]
  instance_types  = ["t3a.large"]
  min_size        = 1
  max_size        = 2
  desired_size    = 1
  labels          = { environment = "production", node-group = "platform" }
  # tags omitted on purpose -> defaults to {} (platform-ng really has no tags in AWS)
}

module "storefront_ng" {
  source = "./modules/node_group"

  cluster_name    = aws_eks_cluster.prod_eks.name
  node_group_name = "vendure-prod-storefront-ng-medium"
  node_role_arn   = "arn:aws:iam::149536454380:role/vendure-prod-eks-node-role"
  subnet_ids      = [aws_subnet.public_1a.id, aws_subnet.public_2b.id, aws_subnet.public_3c.id]
  instance_types  = ["t3a.medium"]
  min_size        = 1
  max_size        = 2
  desired_size    = 1
  labels          = { environment = "production", node-group = "storefront" }
  tags            = { Project = "vendure", Environment = "production", InstanceType = "t3a.medium", Name = "vendure-prod-storefront-ng-medium" }
}

# --- moved{} blocks: tell Terraform each resource is the SAME one, only re-addressed.
# Without these, the refactor would DESTROY the old addresses and CREATE new node groups.
moved {
  from = aws_eks_node_group.prod_eks_ng
  to   = module.app_ng.aws_eks_node_group.this
}

moved {
  from = aws_eks_node_group.prod_eks_platform_ng
  to   = module.platform_ng.aws_eks_node_group.this
}

moved {
  from = aws_eks_node_group.prod_eks_storefront_ng
  to   = module.storefront_ng.aws_eks_node_group.this
}
