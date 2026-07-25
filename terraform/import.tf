# IAM roles
import {
  to = aws_iam_role.eks_cluster
  id = "vendure-production-eks-cluster-role"
}
import {
  to = aws_iam_role.eks_node
  id = "vendure-prod-eks-node-role"
}

# IAM role policy attachments (import id = "role-name/policy-arn")
import {
  to = aws_iam_role_policy_attachment.eks_cluster_policy
  id = "vendure-production-eks-cluster-role/arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}
import {
  to = aws_iam_role_policy_attachment.eks_cluster_vpc_resource_controller
  id = "vendure-production-eks-cluster-role/arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
}
import {
  to = aws_iam_role_policy_attachment.node_ssm
  id = "vendure-prod-eks-node-role/arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}
import {
  to = aws_iam_role_policy_attachment.node_cni
  id = "vendure-prod-eks-node-role/arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}
import {
  to = aws_iam_role_policy_attachment.node_ecr
  id = "vendure-prod-eks-node-role/arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}
import {
  to = aws_iam_role_policy_attachment.node_worker
  id = "vendure-prod-eks-node-role/arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

# RDS support
import {
  to = aws_db_subnet_group.prod
  id = "vendure-prod-db-subnet"
}
import {
  to = aws_db_parameter_group.prod
  id = "aws-vendure-pg"
}
