# IAM is GLOBAL: role NAMES must not collide with prod, so everything here is
# "${var.project}-dr-*". The four CUSTOMER policies (ALB controller, Velero,
# Loki, Karpenter) already exist globally -- managed by the prod root module
# (terraform/iam_irsa.tf) -- so DR roles just ATTACH them by ARN.

data "aws_caller_identity" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
}

# --- EKS cluster + node roles ---

resource "aws_iam_role" "eks_cluster" {
  name = "${var.project}-dr-eks-cluster-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "eks_cluster" {
  role       = aws_iam_role.eks_cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_iam_role_policy_attachment" "eks_cluster_vpc" {
  role       = aws_iam_role.eks_cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
}

resource "aws_iam_role" "eks_node" {
  name = "${var.project}-dr-eks-node-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "node" {
  for_each = toset([
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
  ])
  role       = aws_iam_role.eks_node.name
  policy_arn = each.value
}

# --- IRSA: OIDC provider for the DR cluster ---

data "tls_certificate" "oidc" {
  url = aws_eks_cluster.dr.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "dr" {
  url             = aws_eks_cluster.dr.identity[0].oidc[0].issuer
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.oidc.certificates[0].sha1_fingerprint]
}

# One trust doc shape for every IRSA role, parameterized by SA.
locals {
  oidc_host = replace(aws_eks_cluster.dr.identity[0].oidc[0].issuer, "https://", "")

  irsa_roles = {
    # tf_name => { sa = "namespace:serviceaccount", policy_arns = [...] }
    alb_controller = {
      sa          = "kube-system:aws-load-balancer-controller"
      policy_arns = ["arn:aws:iam::${local.account_id}:policy/AWSLoadBalancerControllerIAMPolicy"]
    }
    external_secrets = {
      sa          = "external-secrets:external-secrets"
      policy_arns = ["arn:aws:iam::aws:policy/SecretsManagerReadWrite"]
    }
    ebs_csi = {
      sa          = "kube-system:ebs-csi-controller-sa"
      policy_arns = ["arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"]
    }
    # vendure app roles: S3 access policies point at ap-south-1 buckets, which
    # STILL WORK from ap-south-2 in a partial outage; in a full regional S3
    # outage the app serves without new image uploads. Attach the same inline
    # doc the prod role uses.
    vendure_prod_app = {
      sa          = "vendure-production:vendure-production-vendure-stack"
      policy_arns = []
    }
    vendure_client_app = {
      sa          = "vendure-client-production:vendure-client-production-vendure-stack"
      policy_arns = []
    }
  }
}

resource "aws_iam_role" "irsa" {
  for_each = local.irsa_roles

  name = "${var.project}-dr-${replace(each.key, "_", "-")}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRoleWithWebIdentity"
      Principal = { Federated = aws_iam_openid_connect_provider.dr.arn }
      Condition = {
        StringEquals = {
          "${local.oidc_host}:aud" = "sts.amazonaws.com"
          "${local.oidc_host}:sub" = "system:serviceaccount:${each.value.sa}"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "irsa" {
  for_each = { for pair in flatten([
    for name, cfg in local.irsa_roles : [
      for arn in cfg.policy_arns : { key = "${name}:${arn}", role = name, arn = arn }
    ]
  ]) : pair.key => pair }

  role       = aws_iam_role.irsa[each.value.role].name
  policy_arn = each.value.arn
}

# Vendure app S3 access (same docs as prod's inline policies).
resource "aws_iam_role_policy" "vendure_prod_app_s3" {
  name   = "vendure-s3-access"
  role   = aws_iam_role.irsa["vendure_prod_app"].id
  policy = file("${path.module}/../../policies/vendure-s3-access.json")
}

resource "aws_iam_role_policy" "vendure_client_app_s3" {
  name   = "vendure-client-prod-permissions"
  role   = aws_iam_role.irsa["vendure_client_app"].id
  policy = file("${path.module}/../../policies/vendure-client-prod-permissions.json")
}
