resource "aws_subnet" "public_1a" {
  vpc_id                  = aws_vpc.prod.id
  cidr_block              = "10.10.0.0/20"
  availability_zone       = "ap-south-1a"
  map_public_ip_on_launch = true
  tags = {
    Name                     = "vendure-production-subnet-public1-ap-south-1a"
    "karpenter.sh/discovery" = "vendure-prod"
  }
}
resource "aws_subnet" "public_2b" {
  vpc_id                  = aws_vpc.prod.id
  cidr_block              = "10.10.16.0/20"
  availability_zone       = "ap-south-1b"
  map_public_ip_on_launch = true
  tags = {
    Name                     = "vendure-production-subnet-public2-ap-south-1b"
    "karpenter.sh/discovery" = "vendure-prod"
  }
}
resource "aws_subnet" "public_3c" {
  vpc_id                  = aws_vpc.prod.id
  cidr_block              = "10.10.32.0/20"
  availability_zone       = "ap-south-1c"
  map_public_ip_on_launch = true
  tags = {
    Name                     = "vendure-production-subnet-public3-ap-south-1c"
    "karpenter.sh/discovery" = "vendure-prod"
  }
}
resource "aws_subnet" "private_1a" {
  vpc_id                  = aws_vpc.prod.id
  cidr_block              = "10.10.128.0/20"
  availability_zone       = "ap-south-1a"
  map_public_ip_on_launch = false
  tags = {
    Name = "vendure-production-subnet-private1-ap-south-1a"
  }
}
resource "aws_subnet" "private_2b" {
  vpc_id                  = aws_vpc.prod.id
  cidr_block              = "10.10.144.0/20"
  availability_zone       = "ap-south-1b"
  map_public_ip_on_launch = false
  tags = {
    Name = "vendure-production-subnet-private2-ap-south-1b"
  }
}
resource "aws_subnet" "private_3c" {
  vpc_id                  = aws_vpc.prod.id
  cidr_block              = "10.10.160.0/20"
  availability_zone       = "ap-south-1c"
  map_public_ip_on_launch = false
  tags = {
    Name = "vendure-production-subnet-private3-ap-south-1c"
  }
}


resource "aws_subnet" "test_public_1a" {
  vpc_id                  = aws_vpc.test.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "ap-south-1a"
  map_public_ip_on_launch = false
  tags = {
    Name                     = "pub_sn"
  }
}
resource "aws_subnet" "test_public_1b" {
  vpc_id                  = aws_vpc.test.id
  cidr_block              = "10.0.3.0/24"
  availability_zone       = "ap-south-1b"
  map_public_ip_on_launch = false
  tags = {  
    Name                     = "pub_sn_2"
  } 
}
resource "aws_subnet" "test_private_1a" {
  vpc_id                  = aws_vpc.test.id
  cidr_block              = "10.0.4.0/24"
  availability_zone       = "ap-south-1a" 
  map_public_ip_on_launch = false
  tags = {
    Name = "pri_sn_2"  
  }
}
resource "aws_subnet" "test_private_1b" {
  vpc_id = aws_vpc.test.id
  cidr_block = "10.0.2.0/24"
  availability_zone = "ap-south-1b"
  map_public_ip_on_launch = false
  tags = {
    Name = "pri_sn"
  }
}