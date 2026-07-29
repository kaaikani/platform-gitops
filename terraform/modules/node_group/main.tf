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

  # desired_size is owned at RUNTIME by the cluster-autoscaler / Karpenter / HPA,
  # not by Terraform. Without this, every apply resets the count back to the value
  # in node_groups.tf and terminates any node the autoscaler had added.
  # min_size / max_size stay managed here on purpose — those are the guardrails.
  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
  }
}
