# These two SGs on GK_Construction are created and OWNED by the in-cluster
# aws-load-balancer-controller (k8s-vendureshared / k8s-traffic-*). They must
# never be imported into Terraform -- the controller recreates them if the ALB
# is rebuilt, at which point the ids below go stale and these data sources fail
# the plan loudly (which is what we want: a visible signal, not a silent drift).
data "aws_security_group" "alb_managed" {
  id = "sg-0ba5c7c8f76401d4b" # k8s-vendureshared -- ALB frontend SG
}

data "aws_security_group" "alb_backend" {
  id = "sg-08acbcb27549a1e75" # k8s-traffic-vendureprodcluster -- shared backend SG
}

resource "aws_instance" "delivery_partner" {
  # DR story: nightly AWS Backup copy in ap-south-2 (dr_backup.tf), restore as
  # AMI there. The region-scoped AMI id below is only the ORIGINAL boot image;
  # it is never used again unless the instance is recreated -- guarded below.
  ami                    = "ami-0f25d62448df9edee"
  instance_type          = "t3a.medium"
  subnet_id              = aws_subnet.public_1a.id
  key_name               = "new one"
  ebs_optimized          = true
  monitoring             = false
  vpc_security_group_ids = [aws_security_group.eks_sg.id, aws_security_group.bastion.id, aws_security_group.eks_node_sg.id, aws_security_group.rds.id]

  lifecycle {
    prevent_destroy = true # client production server, serves www.kaaikanistore.com
  }

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
    data.aws_security_group.alb_managed.id,
    data.aws_security_group.alb_backend.id,
  ]

  lifecycle {
    prevent_destroy = true # client production server (gkc.avsecomhub.com)
  }

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

# resource "aws_instance" "demo" {
#   ami           = "ami-001c3e230ff9dd79c"
#   instance_type = "t3.micro"
#   subnet_id     = aws_subnet.test_public_1a.id
#   key_name      = "test_key"
#   ebs_optimized = true
#   monitoring    = false
#   vpc_security_group_ids = [
#     aws_security_group.test_sg.id
#   ]
#   tags = {
#     Name = "demo_ec2"
#   }
# }