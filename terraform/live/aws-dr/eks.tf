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

  compute_config {
    enabled = false
  }
  storage_config {
    block_storage {
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
  instance_types  = ["t3a.large"]
  min_size        = 2
  max_size        = 6
  desired_size    = 3
  kube_version    = var.kube_version
  labels          = { environment = "dr" }
  tags            = { Project = var.project, Environment = "dr" }
}

# Same five addons as prod, latest compatible versions (a DR build always uses
# fresh defaults -- there is no live workload to disturb at create time).
data "aws_eks_addon_version" "latest" {
  for_each = toset(["aws-ebs-csi-driver", "coredns", "kube-proxy", "metrics-server", "vpc-cni"])

  addon_name         = each.key
  kubernetes_version = var.kube_version
  most_recent        = true
}

resource "aws_eks_addon" "this" {
  for_each = data.aws_eks_addon_version.latest

  cluster_name  = aws_eks_cluster.dr.name
  addon_name    = each.key
  addon_version = each.value.version

  service_account_role_arn = each.key == "aws-ebs-csi-driver" ? aws_iam_role.irsa["ebs_csi"].arn : null

  depends_on = [module.app_ng]
}
