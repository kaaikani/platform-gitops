resource "aws_security_group" "bastion" {
  vpc_id = aws_vpc.prod.id
  name   = "bastion-sg"
  description = "Bastion SSH access"
  ingress {
        from_port = 22
        to_port = 22
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }
  egress {
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      cidr_blocks = ["0.0.0.0/0"]
    }
}

resource "aws_security_group" "rds" {
    vpc_id = aws_vpc.prod.id
    name   = "vendure-production-rds-sg"
    description = "Security group for RDS MySQL database"
    ingress{
            from_port = 3306
            to_port = 3306
            protocol = "tcp"
            cidr_blocks = ["10.10.0.0/16"]     
        }

    egress{
            from_port   = 0
            to_port     = 0
            protocol    = "-1"
            cidr_blocks = ["0.0.0.0/0"]
        }
}
resource "aws_security_group" "eks_sg" {
    vpc_id = aws_vpc.prod.id
    name   = "vendure-production-eks-cluster-sg"
    description = "Security group for EKS cluster control plane"
    ingress{
            from_port = 443
            to_port = 443
            protocol = "tcp"
            cidr_blocks = ["10.10.0.0/16"]
    }
    egress {
        from_port = 0
        to_port = 0
        protocol = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }
}
resource "aws_security_group" "eks_node_sg" {
  vpc_id = aws_vpc.prod.id
  name= "vendure-production-eks-node-sg"
  description = "Security group for EKS worker nodes"
  ingress {
    from_port = 80
    to_port = 80
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["157.51.24.204/32"]
  }
  ingress {
    from_port = 1025
    to_port = 65535
    protocol = "tcp"
    security_groups = [aws_security_group.eks_sg.id]
  }
  ingress {
    from_port = 443
    to_port = 443
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    security_groups = [aws_security_group.eks_sg.id]
  }
  egress{
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}