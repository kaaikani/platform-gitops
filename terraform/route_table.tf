resource "aws_route_table" "private" {
  vpc_id = aws_vpc.prod.id
  tags = {
    Name = "vendure-prod-rt-private"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.prod.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.prod.id
  }
  tags = {
    Name = "vendure-production-rtb-public"
  }
}
 resource "aws_route_table" "test_pub_rt" {
  vpc_id = aws_vpc.test.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.test_igw.id
  }
  tags = {
    Name = "pub_RT"
  }
   
 }

 resource "aws_route_table" "test_pri_rt" {
  vpc_id = aws_vpc.test.id
  tags = {
    Name = "pri_RT"
  }
 }