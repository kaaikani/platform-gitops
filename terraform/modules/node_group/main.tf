# Generic EKS managed node group. Every value comes from a variable, so the
# same block can produce app-ng, platform-ng, storefront-ng, etc.
resource "aws_eks_node_group" "this" {
  cluster_name    = var.cluster_name
  node_group_name = var.node_group_name
  node_role_arn   = var.node_role_arn
  subnet_ids      = var.subnet_ids
  instance_types  = var.instance_types
  capacity_type   = var.capacity_type
  ami_type        = var.ami_type
  disk_size       = var.disk_size
  version         = var.kube_version

  scaling_config {
    min_size     = var.min_size
    max_size     = var.max_size
    desired_size = var.desired_size
  }

  labels = var.labels
  tags   = var.tags
}
