variable "cluster_name" {
  description = "Name of the EKS cluster this node group attaches to"
  type        = string
}

variable "node_group_name" {
  description = "Name of the managed node group"
  type        = string
}

variable "node_role_arn" {
  description = "IAM role ARN the worker nodes assume"
  type        = string
}

variable "subnet_ids" {
  description = "Subnets the node group launches instances into"
  type        = list(string)
}

variable "instance_types" {
  description = "EC2 instance types for the nodes"
  type        = list(string)
}

variable "min_size" {
  description = "Minimum number of nodes"
  type        = number
}

variable "max_size" {
  description = "Maximum number of nodes"
  type        = number
}

variable "desired_size" {
  description = "Desired number of nodes"
  type        = number
}

variable "labels" {
  description = "Kubernetes labels applied to the nodes"
  type        = map(string)
}

variable "tags" {
  description = "AWS tags applied to the node group"
  type        = map(string)
  default     = {}
}

variable "ami_type" {
  description = "AMI type for the nodes"
  type        = string
  default     = "AL2023_x86_64_STANDARD"
}

variable "capacity_type" {
  description = "ON_DEMAND or SPOT"
  type        = string
  default     = "ON_DEMAND"
}

variable "disk_size" {
  description = "Root disk size in GiB"
  type        = number
  default     = 20
}

variable "kube_version" {
  description = "Kubernetes version for the node group (NOT named 'version' - that word is reserved in module blocks)"
  type        = string
  default     = "1.35"
}
