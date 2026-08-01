# DR EKS: managed node groups only, NO Karpenter. An emergency environment
# wants the fewest moving parts; a fixed node group up to 6 nodes carries the
# whole platform (prod runs on ~5-6). Karpenter can be layered on later if the
# DR promotion becomes long-lived.

resource "aws_kms_key" "eks_secrets" {
  description         = "EKS secrets envelope encryption for ${var.cluster_name}"
  enable_key_rotation = true
}

resource "aws_eks_cluster" "dr" {
  name     = var.cluster_name
  version  = var.kube_version
  role_arn = aws_iam_role.eks_cluster.arn

  bootstrap_self_managed_addons = false

  vpc_config {
    subnet_ids              = aws_subnet.public[*].id
    security_group_ids      = [aws_security_group.eks_cluster.id]
    endpoint_public_access  = true
    endpoint_private_access = true
    public_access_cidrs     = ["0.0.0.0/0"]
  }

  encryption_config {
    resources = ["secrets"]
    provider {
      key_arn = aws_kms_key.eks_secrets.arn
    }
  }

  # DRILL FINDING #2 (2026-08-01): the CreateCluster API demands ALL THREE
  # Auto-Mode configs together (compute, blockStorage, AND
  # kubernetesNetworkConfig.elasticLoadBalancing) or it 400s. Prod never hit
  # this because its cluster was IMPORTED -- the third block lives invisibly in
  # state as a computed attribute. Only a real create exposes it.
  compute_config {
    enabled = false
  }
  storage_config {
    block_storage {
      enabled = false
    }
  }
  kubernetes_network_config {
    elastic_load_balancing {
      enabled = false
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster,
    aws_iam_role_policy_attachment.eks_cluster_vpc,
  ]
}

module "app_ng" {
  source = "../../modules/node_group"

  cluster_name    = aws_eks_cluster.dr.name
  node_group_name = "${var.project}-dr-app-ng"
  node_role_arn   = aws_iam_role.eks_node.arn
  subnet_ids      = aws_subnet.public[*].id
  # DRILL FINDING #5 (2026-08-01): the t3a (AMD) family DOES NOT EXIST in
  # ap-south-2 -- the whole prod fleet runs t3a and none of it can launch in
  # Hyderabad. t3.large (Intel) is the like-for-like shape (2 vCPU / 8 GiB).
  # Verified offerings: t3.medium/large, m5.large, m7g.large, c6a.large.
  instance_types = ["t3.large"]
  min_size       = 2
  max_size       = 6
  desired_size   = 3
  kube_version   = var.kube_version
  labels         = { environment = "dr" }
  tags           = { Project = var.project, Environment = "dr" }
}

# Same five addons as prod, latest compatible versions (a DR build always uses
# fresh defaults -- there is no live workload to disturb at create time).
data "aws_eks_addon_version" "latest" {
  for_each = toset(["aws-ebs-csi-driver", "coredns", "kube-proxy", "metrics-server", "vpc-cni"])

  addon_name         = each.key
  kubernetes_version = var.kube_version
  most_recent        = true
}

# DRILL FINDING #8 (2026-08-01): with bootstrap_self_managed_addons=false the
# cluster has NO CNI, so nodes join NotReady forever, the node group never goes
# ACTIVE, and addons that waited on the node group DEADLOCK the whole apply.
# Boot-critical addons (vpc-cni, kube-proxy) must be created BEFORE the node
# group; only workload addons (coredns, metrics-server, ebs-csi) wait for nodes.
resource "aws_eks_addon" "boot" {
  for_each = { for k, v in data.aws_eks_addon_version.latest : k => v if contains(["vpc-cni", "kube-proxy"], k) }

  cluster_name  = aws_eks_cluster.dr.name
  addon_name    = each.key
  addon_version = each.value.version
}

resource "aws_eks_addon" "this" {
  for_each = { for k, v in data.aws_eks_addon_version.latest : k => v if !contains(["vpc-cni", "kube-proxy"], k) }

  cluster_name  = aws_eks_cluster.dr.name
  addon_name    = each.key
  addon_version = each.value.version

  service_account_role_arn = each.key == "aws-ebs-csi-driver" ? aws_iam_role.irsa["ebs_csi"].arn : null

  depends_on = [module.app_ng]
}
