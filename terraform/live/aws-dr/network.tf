# Mirrors prod's topology (public node subnets, private DB subnets) rather than
# redesigning networking inside a disaster. 3 AZs: ap-south-2a/2b/2c.

locals {
  azs = ["${var.dr_region}a", "${var.dr_region}b", "${var.dr_region}c"]
}

resource "aws_vpc" "dr" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags                 = { Name = "${var.project}-dr-vpc" }
}

resource "aws_internet_gateway" "dr" {
  vpc_id = aws_vpc.dr.id
  tags   = { Name = "${var.project}-dr-igw" }
}

resource "aws_subnet" "public" {
  count = 3

  vpc_id                  = aws_vpc.dr.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 4, count.index) # /20s: 10.20.0/16/32
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = true
  tags = {
    Name                     = "${var.project}-dr-public-${local.azs[count.index]}"
    "kubernetes.io/role/elb" = "1" # ALB controller subnet discovery
  }
}

resource "aws_subnet" "private" {
  count = 3

  vpc_id            = aws_vpc.dr.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 4, count.index + 8) # 10.20.128/144/160
  availability_zone = local.azs[count.index]
  tags              = { Name = "${var.project}-dr-private-${local.azs[count.index]}" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.dr.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.dr.id
  }
  tags = { Name = "${var.project}-dr-rt-public" }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.dr.id
  tags   = { Name = "${var.project}-dr-rt-private" }
}

resource "aws_route_table_association" "public" {
  count          = 3
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  count          = 3
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# --- Security groups (mirroring prod's intent, DR CIDR) ---

resource "aws_security_group" "eks_cluster" {
  vpc_id      = aws_vpc.dr.id
  name        = "${var.project}-dr-eks-cluster-sg"
  description = "EKS control plane"
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "eks_node" {
  vpc_id      = aws_vpc.dr.id
  name        = "${var.project}-dr-eks-node-sg"
  description = "EKS worker nodes"
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port       = 1025
    to_port         = 65535
    protocol        = "tcp"
    security_groups = [aws_security_group.eks_cluster.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "rds" {
  vpc_id      = aws_vpc.dr.id
  name        = "${var.project}-dr-rds-sg"
  description = "RDS MySQL from inside the DR VPC"
  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
