# IRSA + platform IAM, recovered from console-made resources (Phase 2 inventory,
# 2026-07-31) and imported as-is. Until now these existed ONLY in the console --
# no code could rebuild the cluster's permission layer in a DR region.
#
# Role -> ServiceAccount map (trust-policy conditions, verified live):
#   ebs_csi              -> kube-system:ebs-csi-controller-sa
#   alb_controller       -> kube-system:aws-load-balancer-controller
#   external_secrets     -> external-secrets:external-secrets
#   karpenter_controller -> karpenter:karpenter        (+ inline extra perms)
#   karpenter_node       -> EC2 nodes (Karpenter-launched)
#   velero               -> velero:velero-server
#   vendure_prod_app     -> vendure-production:vendure-production-vendure-stack
#   vendure_client_app   -> vendure-client-production:...-vendure-stack
#   loki                 -> monitoring:loki   ⚠ trusts a DEAD cluster OIDC
#                           (76105CDD...) -- IRSA for Loki CANNOT work today.
#                           Imported as-is; fixing the trust is a separate,
#                           deliberate prod change (see docs/dr TODO).
#   github_actions       -> GitHub Actions CI (AdministratorAccess ⚠ -- scope
#                           down someday; imported as-is)
#
# Assume-role docs are emitted verbatim from the live docs so imports are no-op.
# Policy documents live in ./policies/*.json (byte-for-byte from IAM).

# --- the ACTIVE cluster's OIDC provider (7 orphans from deleted clusters were
# --- deliberately NOT imported; cleanup candidates, see docs/dr TODO).
resource "aws_iam_openid_connect_provider" "cluster" {
  url             = "https://oidc.eks.ap-south-1.amazonaws.com/id/49B4F1DE175BD38F8192416B929E9D7E"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["06b25927c42a721631c1efd9431e648fa62e1e39"]

  tags = {
    "alpha.eksctl.io/eksctl-version" = "0.220.0"
    "alpha.eksctl.io/cluster-name"   = "vendure-prod-cluster"
  }
}

import {
  to = aws_iam_openid_connect_provider.cluster
  id = "arn:aws:iam::149536454380:oidc-provider/oidc.eks.ap-south-1.amazonaws.com/id/49B4F1DE175BD38F8192416B929E9D7E"
}

# --- GitHub OIDC provider (CI) ---
resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["1c58a3a8518e8759bf075b76b750d4f2df264fcd"]
}

import {
  to = aws_iam_openid_connect_provider.github
  id = "arn:aws:iam::149536454380:oidc-provider/token.actions.githubusercontent.com"
}

resource "aws_iam_policy" "awsloadbalancercontrolleriampolicy" {
  name   = "AWSLoadBalancerControllerIAMPolicy"
  policy = file("${path.module}/policies/AWSLoadBalancerControllerIAMPolicy.json")
}

import {
  to = aws_iam_policy.awsloadbalancercontrolleriampolicy
  id = "arn:aws:iam::149536454380:policy/AWSLoadBalancerControllerIAMPolicy"
}

resource "aws_iam_policy" "karpentercontrollerpolicy_vendure_prod" {
  name   = "KarpenterControllerPolicy-vendure-prod"
  policy = file("${path.module}/policies/KarpenterControllerPolicy-vendure-prod.json")
}

import {
  to = aws_iam_policy.karpentercontrollerpolicy_vendure_prod
  id = "arn:aws:iam::149536454380:policy/KarpenterControllerPolicy-vendure-prod"
}

resource "aws_iam_policy" "velerobackuppolicy" {
  name   = "VeleroBackupPolicy"
  policy = file("${path.module}/policies/VeleroBackupPolicy.json")
}

import {
  to = aws_iam_policy.velerobackuppolicy
  id = "arn:aws:iam::149536454380:policy/VeleroBackupPolicy"
}

resource "aws_iam_policy" "lokis3policy" {
  name   = "LokiS3Policy"
  policy = file("${path.module}/policies/LokiS3Policy.json")
}

import {
  to = aws_iam_policy.lokis3policy
  id = "arn:aws:iam::149536454380:policy/LokiS3Policy"
}

resource "aws_iam_role" "ebs_csi" {
  name                 = "AmazonEKS_EBS_CSI_DriverRole_VendureProd"
  max_session_duration = 3600
  assume_role_policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Principal" : {
          "Federated" : "arn:aws:iam::149536454380:oidc-provider/oidc.eks.ap-south-1.amazonaws.com/id/49B4F1DE175BD38F8192416B929E9D7E"
        },
        "Action" : "sts:AssumeRoleWithWebIdentity",
        "Condition" : {
          "StringEquals" : {
            "oidc.eks.ap-south-1.amazonaws.com/id/49B4F1DE175BD38F8192416B929E9D7E:aud" : "sts.amazonaws.com",
            "oidc.eks.ap-south-1.amazonaws.com/id/49B4F1DE175BD38F8192416B929E9D7E:sub" : "system:serviceaccount:kube-system:ebs-csi-controller-sa"
          }
        }
      }
    ]
  })

  tags = {
    "alpha.eksctl.io/cluster-name"                = "vendure-prod-cluster"
    "alpha.eksctl.io/iamserviceaccount-name"      = "kube-system/ebs-csi-controller-sa"
    "alpha.eksctl.io/eksctl-version"              = "0.220.0"
    "eksctl.cluster.k8s.io/v1alpha1/cluster-name" = "vendure-prod-cluster"
  }
}

import {
  to = aws_iam_role.ebs_csi
  id = "AmazonEKS_EBS_CSI_DriverRole_VendureProd"
}

resource "aws_iam_role_policy_attachment" "ebs_csi" {
  role       = aws_iam_role.ebs_csi.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

import {
  to = aws_iam_role_policy_attachment.ebs_csi
  id = "AmazonEKS_EBS_CSI_DriverRole_VendureProd/arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

resource "aws_iam_role" "alb_controller" {
  name                 = "eksctl-vendure-prod-cluster-addon-iamservicea-Role1-qNEhVoigjkRN"
  max_session_duration = 3600
  assume_role_policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Principal" : {
          "Federated" : "arn:aws:iam::149536454380:oidc-provider/oidc.eks.ap-south-1.amazonaws.com/id/49B4F1DE175BD38F8192416B929E9D7E"
        },
        "Action" : "sts:AssumeRoleWithWebIdentity",
        "Condition" : {
          "StringEquals" : {
            "oidc.eks.ap-south-1.amazonaws.com/id/49B4F1DE175BD38F8192416B929E9D7E:aud" : "sts.amazonaws.com",
            "oidc.eks.ap-south-1.amazonaws.com/id/49B4F1DE175BD38F8192416B929E9D7E:sub" : "system:serviceaccount:kube-system:aws-load-balancer-controller"
          }
        }
      }
    ]
  })

  tags = {
    "alpha.eksctl.io/cluster-name"                = "vendure-prod-cluster"
    "alpha.eksctl.io/iamserviceaccount-name"      = "kube-system/aws-load-balancer-controller"
    "alpha.eksctl.io/eksctl-version"              = "0.220.0"
    "eksctl.cluster.k8s.io/v1alpha1/cluster-name" = "vendure-prod-cluster"
  }
}

import {
  to = aws_iam_role.alb_controller
  id = "eksctl-vendure-prod-cluster-addon-iamservicea-Role1-qNEhVoigjkRN"
}

resource "aws_iam_role_policy_attachment" "alb_controller_custom" {
  role       = aws_iam_role.alb_controller.name
  policy_arn = aws_iam_policy.awsloadbalancercontrolleriampolicy.arn
}

import {
  to = aws_iam_role_policy_attachment.alb_controller_custom
  id = "eksctl-vendure-prod-cluster-addon-iamservicea-Role1-qNEhVoigjkRN/arn:aws:iam::149536454380:policy/AWSLoadBalancerControllerIAMPolicy"
}

resource "aws_iam_role" "external_secrets" {
  name                 = "eksctl-vendure-prod-cluster-addon-iamservicea-Role1-RAc664tKQwib"
  max_session_duration = 3600
  assume_role_policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Principal" : {
          "Federated" : "arn:aws:iam::149536454380:oidc-provider/oidc.eks.ap-south-1.amazonaws.com/id/49B4F1DE175BD38F8192416B929E9D7E"
        },
        "Action" : "sts:AssumeRoleWithWebIdentity",
        "Condition" : {
          "StringEquals" : {
            "oidc.eks.ap-south-1.amazonaws.com/id/49B4F1DE175BD38F8192416B929E9D7E:aud" : "sts.amazonaws.com",
            "oidc.eks.ap-south-1.amazonaws.com/id/49B4F1DE175BD38F8192416B929E9D7E:sub" : "system:serviceaccount:external-secrets:external-secrets"
          }
        }
      }
    ]
  })

  tags = {
    "alpha.eksctl.io/cluster-name"                = "vendure-prod-cluster"
    "alpha.eksctl.io/iamserviceaccount-name"      = "external-secrets/external-secrets"
    "alpha.eksctl.io/eksctl-version"              = "0.220.0"
    "eksctl.cluster.k8s.io/v1alpha1/cluster-name" = "vendure-prod-cluster"
  }
}

import {
  to = aws_iam_role.external_secrets
  id = "eksctl-vendure-prod-cluster-addon-iamservicea-Role1-RAc664tKQwib"
}

resource "aws_iam_role_policy_attachment" "external_secrets" {
  role       = aws_iam_role.external_secrets.name
  policy_arn = "arn:aws:iam::aws:policy/SecretsManagerReadWrite"
}

import {
  to = aws_iam_role_policy_attachment.external_secrets
  id = "eksctl-vendure-prod-cluster-addon-iamservicea-Role1-RAc664tKQwib/arn:aws:iam::aws:policy/SecretsManagerReadWrite"
}

resource "aws_iam_role" "karpenter_controller" {
  name                 = "KarpenterControllerRole-vendure-prod"
  max_session_duration = 3600
  assume_role_policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Principal" : {
          "Federated" : "arn:aws:iam::149536454380:oidc-provider/oidc.eks.ap-south-1.amazonaws.com/id/49B4F1DE175BD38F8192416B929E9D7E"
        },
        "Action" : "sts:AssumeRoleWithWebIdentity",
        "Condition" : {
          "StringEquals" : {
            "oidc.eks.ap-south-1.amazonaws.com/id/49B4F1DE175BD38F8192416B929E9D7E:aud" : "sts.amazonaws.com",
            "oidc.eks.ap-south-1.amazonaws.com/id/49B4F1DE175BD38F8192416B929E9D7E:sub" : "system:serviceaccount:karpenter:karpenter"
          }
        }
      }
    ]
  })

  tags = {
    "alpha.eksctl.io/cluster-name"                = "vendure-prod"
    "alpha.eksctl.io/iamserviceaccount-name"      = "kube-system/karpenter"
    "alpha.eksctl.io/eksctl-version"              = "0.220.0"
    "eksctl.cluster.k8s.io/v1alpha1/cluster-name" = "vendure-prod"
  }
}

import {
  to = aws_iam_role.karpenter_controller
  id = "KarpenterControllerRole-vendure-prod"
}

resource "aws_iam_role_policy_attachment" "karpenter_controller_custom" {
  role       = aws_iam_role.karpenter_controller.name
  policy_arn = aws_iam_policy.karpentercontrollerpolicy_vendure_prod.arn
}

import {
  to = aws_iam_role_policy_attachment.karpenter_controller_custom
  id = "KarpenterControllerRole-vendure-prod/arn:aws:iam::149536454380:policy/KarpenterControllerPolicy-vendure-prod"
}

resource "aws_iam_role_policy" "karpenter_controller_inline" {
  name   = "KarpenterExtraPermissions"
  role   = aws_iam_role.karpenter_controller.id
  policy = file("${path.module}/policies/KarpenterExtraPermissions.json")
}

import {
  to = aws_iam_role_policy.karpenter_controller_inline
  id = "KarpenterControllerRole-vendure-prod:KarpenterExtraPermissions"
}

resource "aws_iam_role" "karpenter_node" {
  name                 = "KarpenterNodeRole-vendure-prod"
  max_session_duration = 3600
  assume_role_policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Principal" : {
          "Service" : "ec2.amazonaws.com"
        },
        "Action" : "sts:AssumeRole"
      }
    ]
  })
}

import {
  to = aws_iam_role.karpenter_node
  id = "KarpenterNodeRole-vendure-prod"
}

resource "aws_iam_role_policy_attachment" "karpenter_node_0" {
  role       = aws_iam_role.karpenter_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

import {
  to = aws_iam_role_policy_attachment.karpenter_node_0
  id = "KarpenterNodeRole-vendure-prod/arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "karpenter_node_1" {
  role       = aws_iam_role.karpenter_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

import {
  to = aws_iam_role_policy_attachment.karpenter_node_1
  id = "KarpenterNodeRole-vendure-prod/arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "karpenter_node_2" {
  role       = aws_iam_role.karpenter_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

import {
  to = aws_iam_role_policy_attachment.karpenter_node_2
  id = "KarpenterNodeRole-vendure-prod/arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_role_policy_attachment" "karpenter_node_3" {
  role       = aws_iam_role.karpenter_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

import {
  to = aws_iam_role_policy_attachment.karpenter_node_3
  id = "KarpenterNodeRole-vendure-prod/arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role" "velero" {
  name                 = "VeleroBackupRole"
  max_session_duration = 3600
  assume_role_policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Principal" : {
          "Federated" : "arn:aws:iam::149536454380:oidc-provider/oidc.eks.ap-south-1.amazonaws.com/id/49B4F1DE175BD38F8192416B929E9D7E"
        },
        "Action" : "sts:AssumeRoleWithWebIdentity",
        "Condition" : {
          "StringEquals" : {
            "oidc.eks.ap-south-1.amazonaws.com/id/49B4F1DE175BD38F8192416B929E9D7E:aud" : "sts.amazonaws.com",
            "oidc.eks.ap-south-1.amazonaws.com/id/49B4F1DE175BD38F8192416B929E9D7E:sub" : "system:serviceaccount:velero:velero-server"
          }
        }
      }
    ]
  })
}

import {
  to = aws_iam_role.velero
  id = "VeleroBackupRole"
}

resource "aws_iam_role_policy_attachment" "velero_custom" {
  role       = aws_iam_role.velero.name
  policy_arn = aws_iam_policy.velerobackuppolicy.arn
}

import {
  to = aws_iam_role_policy_attachment.velero_custom
  id = "VeleroBackupRole/arn:aws:iam::149536454380:policy/VeleroBackupPolicy"
}

resource "aws_iam_role" "vendure_prod_app" {
  name                 = "vendure-production-role"
  max_session_duration = 3600
  description          = "IRSA role for Vendure production pods - S3 access"
  assume_role_policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Principal" : {
          "Federated" : "arn:aws:iam::149536454380:oidc-provider/oidc.eks.ap-south-1.amazonaws.com/id/49B4F1DE175BD38F8192416B929E9D7E"
        },
        "Action" : "sts:AssumeRoleWithWebIdentity",
        "Condition" : {
          "StringEquals" : {
            "oidc.eks.ap-south-1.amazonaws.com/id/49B4F1DE175BD38F8192416B929E9D7E:aud" : "sts.amazonaws.com",
            "oidc.eks.ap-south-1.amazonaws.com/id/49B4F1DE175BD38F8192416B929E9D7E:sub" : "system:serviceaccount:vendure-production:vendure-production-vendure-stack"
          }
        }
      }
    ]
  })

  tags = {
    Environment = "production"
    Cluster     = "vendure-prod-cluster"
  }
}

import {
  to = aws_iam_role.vendure_prod_app
  id = "vendure-production-role"
}

resource "aws_iam_role_policy" "vendure_prod_app_inline" {
  name   = "vendure-s3-access"
  role   = aws_iam_role.vendure_prod_app.id
  policy = file("${path.module}/policies/vendure-s3-access.json")
}

import {
  to = aws_iam_role_policy.vendure_prod_app_inline
  id = "vendure-production-role:vendure-s3-access"
}

resource "aws_iam_role" "vendure_client_app" {
  name                 = "vendure-client-production-role"
  max_session_duration = 3600
  description          = "IRSA role for vendure-client (prabhasaaridesigns.com) production"
  assume_role_policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Principal" : {
          "Federated" : "arn:aws:iam::149536454380:oidc-provider/oidc.eks.ap-south-1.amazonaws.com/id/49B4F1DE175BD38F8192416B929E9D7E"
        },
        "Action" : "sts:AssumeRoleWithWebIdentity",
        "Condition" : {
          "StringEquals" : {
            "oidc.eks.ap-south-1.amazonaws.com/id/49B4F1DE175BD38F8192416B929E9D7E:aud" : "sts.amazonaws.com",
            "oidc.eks.ap-south-1.amazonaws.com/id/49B4F1DE175BD38F8192416B929E9D7E:sub" : "system:serviceaccount:vendure-client-production:vendure-client-production-vendure-stack"
          }
        }
      }
    ]
  })
}

import {
  to = aws_iam_role.vendure_client_app
  id = "vendure-client-production-role"
}

resource "aws_iam_role_policy" "vendure_client_app_inline" {
  name   = "vendure-client-prod-permissions"
  role   = aws_iam_role.vendure_client_app.id
  policy = file("${path.module}/policies/vendure-client-prod-permissions.json")
}

import {
  to = aws_iam_role_policy.vendure_client_app_inline
  id = "vendure-client-production-role:vendure-client-prod-permissions"
}

# Trust FIXED 2026-08-03: previously pointed at a DELETED cluster's OIDC
# provider (76105CDD...) so Loki's IRSA could never authenticate -- S3 log
# shipping was silently broken in prod. Now trusts the active cluster.
resource "aws_iam_role" "loki" {
  name                 = "LokiS3Role"
  max_session_duration = 3600
  assume_role_policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Principal" : {
          "Federated" : "arn:aws:iam::149536454380:oidc-provider/oidc.eks.ap-south-1.amazonaws.com/id/49B4F1DE175BD38F8192416B929E9D7E"
        },
        "Action" : "sts:AssumeRoleWithWebIdentity",
        "Condition" : {
          "StringEquals" : {
            "oidc.eks.ap-south-1.amazonaws.com/id/49B4F1DE175BD38F8192416B929E9D7E:sub" : "system:serviceaccount:monitoring:loki",
            "oidc.eks.ap-south-1.amazonaws.com/id/49B4F1DE175BD38F8192416B929E9D7E:aud" : "sts.amazonaws.com"
          }
        }
      }
    ]
  })
}

import {
  to = aws_iam_role.loki
  id = "LokiS3Role"
}

resource "aws_iam_role_policy_attachment" "loki_custom" {
  role       = aws_iam_role.loki.name
  policy_arn = aws_iam_policy.lokis3policy.arn
}

import {
  to = aws_iam_role_policy_attachment.loki_custom
  id = "LokiS3Role/arn:aws:iam::149536454380:policy/LokiS3Policy"
}

resource "aws_iam_role" "github_actions" {
  name                 = "github-actions-terraform"
  max_session_duration = 3600
  assume_role_policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Principal" : {
          "Federated" : "arn:aws:iam::149536454380:oidc-provider/token.actions.githubusercontent.com"
        },
        "Action" : "sts:AssumeRoleWithWebIdentity",
        "Condition" : {
          "StringEquals" : {
            "token.actions.githubusercontent.com:aud" : "sts.amazonaws.com"
          },
          "StringLike" : {
            "token.actions.githubusercontent.com:sub" : "repo:kaaikani/platform-gitops:*"
          }
        }
      }
    ]
  })
}

import {
  to = aws_iam_role.github_actions
  id = "github-actions-terraform"
}

resource "aws_iam_role_policy_attachment" "github_actions" {
  role       = aws_iam_role.github_actions.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

import {
  to = aws_iam_role_policy_attachment.github_actions
  id = "github-actions-terraform/arn:aws:iam::aws:policy/AdministratorAccess"
}
