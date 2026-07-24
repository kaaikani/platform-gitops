resource "aws_route_table_association" "public_1a" {
  subnet_id      = aws_subnet.public_1a.id
  route_table_id = aws_route_table.public.id
}
resource "aws_route_table_association" "public_2b" {
  subnet_id      = aws_subnet.public_2b.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_3c" {
  subnet_id      = aws_subnet.public_3c.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private_1a" {
  subnet_id      = aws_subnet.private_1a.id
  route_table_id = aws_route_table.private.id

}

resource "aws_route_table_association" "private_2b" {
  subnet_id      = aws_subnet.private_2b.id
  route_table_id = aws_route_table.private.id

}

resource "aws_route_table_association" "private_3c" {
  subnet_id      = aws_subnet.private_3c.id
  route_table_id = aws_route_table.private.id

}
resource "aws_route_table_association" "test_pub_1a" {
  subnet_id      = aws_subnet.test_public_1a.id
  route_table_id = aws_route_table.test_pub_rt.id
}
resource "aws_route_table_association" "test_pri_1b" {
  subnet_id      = aws_subnet.test_private_1b.id
  route_table_id = aws_route_table.test_pri_rt.id

}