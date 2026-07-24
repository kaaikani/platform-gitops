resource "aws_instance" "delivery_partner" {
  ami                    = "ami-0f25d62448df9edee"
  instance_type          = "t3a.medium"
  subnet_id              = aws_subnet.public_1a.id
  key_name               = "new one"
  ebs_optimized          = true
  monitoring             = false
  vpc_security_group_ids = [aws_security_group.eks_sg.id, aws_security_group.bastion.id, aws_security_group.eks_node_sg.id, aws_security_group.rds.id]
  tags = {
    ec2  = "delivery-partner",
    Name = "Delivery-partner"
  }
}

resource "aws_instance" "gk_const" {
  ami           = "ami-006f82a1d5a27da54"
  instance_type = "t3a.medium"
  subnet_id     = aws_subnet.public_1a.id
  key_name      = "client_key_pair"
  ebs_optimized = true
  monitoring    = true
  vpc_security_group_ids = [
    aws_security_group.eks_sg.id,
    aws_security_group.eks_node_sg.id,
    aws_security_group.rds.id,
    "sg-0ba5c7c8f76401d4b",
    "sg-08acbcb27549a1e75"
  ]
  tags = {
    Name = "GK_Construction"
  }
}

resource "aws_instance" "test_ec2" {
  ami           = "ami-001c3e230ff9dd79c"
  instance_type = "t3a.medium"
  subnet_id     = aws_subnet.test_public_1a.id
  key_name      = "test_key"
  ebs_optimized = true
  monitoring    = false
  vpc_security_group_ids = [
    aws_security_group.test_sg.id
  ]
  tags = {
    Name = "test_ec2"
  }
}