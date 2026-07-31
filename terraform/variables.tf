variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "ap-south-1"
}

variable "project" {
  description = "Project name, used for tagging"
  type        = string
  default     = "vendure"
}

variable "dr_region" {
  description = "DR region. ap-south-2 (Hyderabad) keeps Indian customer/order data in-country (DPDP Act) and has EKS 1.35 + mysql 8.0.45 on db.t3.medium/gp3, matching prod."
  type        = string
  default     = "ap-south-2"
}
