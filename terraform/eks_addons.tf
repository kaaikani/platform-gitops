# EKS managed addons + Karpenter interruption queue, imported (Phase 2).
# Versions are PINNED to the exact live values -- an unpinned aws_eks_addon
# would plan an upgrade, and an addon upgrade restarts cluster-critical pods.
# Version bumps stay deliberate, reviewed changes to this file.

locals {
  eks_addons = {
    aws-ebs-csi-driver = {
      version  = "v1.56.0-eksbuild.1"
      role_arn = aws_iam_role.ebs_csi.arn
    }
    coredns = {
      version  = "v1.13.2-eksbuild.3"
      role_arn = null
    }
    kube-proxy = {
      version  = "v1.35.0-eksbuild.2"
      role_arn = null
    }
    metrics-server = {
      version  = "v0.8.1-eksbuild.1"
      role_arn = null
    }
    vpc-cni = {
      version  = "v1.21.1-eksbuild.1"
      role_arn = null
    }
  }
}

resource "aws_eks_addon" "this" {
  for_each = local.eks_addons

  cluster_name             = aws_eks_cluster.prod_eks.name
  addon_name               = each.key
  addon_version            = each.value.version
  service_account_role_arn = each.value.role_arn
}

import {
  to = aws_eks_addon.this["aws-ebs-csi-driver"]
  id = "vendure-prod-cluster:aws-ebs-csi-driver"
}
import {
  to = aws_eks_addon.this["coredns"]
  id = "vendure-prod-cluster:coredns"
}
import {
  to = aws_eks_addon.this["kube-proxy"]
  id = "vendure-prod-cluster:kube-proxy"
}
import {
  to = aws_eks_addon.this["metrics-server"]
  id = "vendure-prod-cluster:metrics-server"
}
import {
  to = aws_eks_addon.this["vpc-cni"]
  id = "vendure-prod-cluster:vpc-cni"
}

# --- Karpenter interruption queue (spot/health events -> graceful drain).
# EventBridge rules that feed this queue are still unmanaged -- import later.
resource "aws_sqs_queue" "karpenter_interruption" {
  name                      = "vendure-prod"
  message_retention_seconds = 300
  sqs_managed_sse_enabled   = true

  # Live queue uses the new 1 MiB max (1048576) which AWS provider ~5.100's
  # validator still rejects (caps at 262144). Ignore so import stays no-op and
  # Terraform never "fixes" it down to the old default.
  lifecycle {
    ignore_changes = [max_message_size]
  }
}

import {
  to = aws_sqs_queue.karpenter_interruption
  id = "https://sqs.ap-south-1.amazonaws.com/149536454380/vendure-prod"
}
