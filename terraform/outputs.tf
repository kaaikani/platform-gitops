# Key values exposed as the config's interface (read-only, no infra impact).

output "vpc_id" {
  description = "Production VPC ID"
  value       = aws_vpc.prod.id
}

output "eks_cluster_name" {
  description = "EKS cluster name"
  value       = aws_eks_cluster.prod_eks.name
}

output "eks_cluster_endpoint" {
  description = "EKS API server endpoint"
  value       = aws_eks_cluster.prod_eks.endpoint
}

output "rds_endpoint" {
  description = "Production RDS endpoint (host:port)"
  value       = aws_db_instance.prod_db.endpoint
}

output "rds_address" {
  description = "Production RDS hostname"
  value       = aws_db_instance.prod_db.address
}
