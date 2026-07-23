resource "aws_internet_gateway" "prod" {
  vpc_id = aws_vpc.prod.id
  tags = {
    Name = "vendure-production-igw"
  }
}
resource "aws_internet_gateway" "test_igw" {
  vpc_id = aws_vpc.test.id
  tags = {
    Name = "test_IGW"
  }
}