# Values the module exposes back to the caller.
output "arn" {
  description = "ARN of the node group"
  value       = aws_eks_node_group.this.arn
}

output "id" {
  description = "ID of the node group (cluster:nodegroup)"
  value       = aws_eks_node_group.this.id
}
