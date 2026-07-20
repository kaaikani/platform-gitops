resource "aws_vpc" "test" {
  assign_generated_ipv6_cidr_block = false
  cidr_block                       = "10.0.0.0/16"
  enable_dns_hostnames             = true
  enable_dns_support               = true
  tags = {
    Name = "Test-vpc"
  }
}
resource "aws_vpc" "prod" {
  cidr_block           = "10.10.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags = {
    Name = "vendure-production-vpc"
  }
}
