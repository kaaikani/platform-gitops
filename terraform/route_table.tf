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