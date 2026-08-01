output "cluster_name" {
  value = aws_eks_cluster.dr.name
}

output "cluster_endpoint" {
  value = aws_eks_cluster.dr.endpoint
}

output "rds_address" {
  description = "Goes into the replicated vendure/prod/database secret's DB_HOST during failover"
  value       = aws_db_instance.dr.address
}

output "irsa_role_arns" {
  description = "Annotate the DR cluster ServiceAccounts with these (runbook step)"
  value       = { for k, r in aws_iam_role.irsa : k => r.arn }
}

output "kubeconfig_command" {
  value = "aws eks update-kubeconfig --region ${var.dr_region} --name ${aws_eks_cluster.dr.name}"
}
