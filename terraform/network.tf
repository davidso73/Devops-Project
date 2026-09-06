# Private subnets for backend/worker/RDS, added to the existing dev-enviroment-vpc.
# No route to an Internet Gateway - egress to AWS services only happens via the
# VPC endpoints defined in endpoints.tf (no NAT Gateway).

resource "aws_subnet" "private_a" {
  vpc_id            = var.vpc_id
  cidr_block        = "10.0.11.0/24"
  availability_zone = "il-central-1a"

  tags = {
    Name      = "vmapp-private-a"
    ManagedBy = "Terraform"
    Project   = "vmapp"
  }
}

resource "aws_subnet" "private_b" {
  vpc_id            = var.vpc_id
  cidr_block        = "10.0.12.0/24"
  availability_zone = "il-central-1b"

  tags = {
    Name      = "vmapp-private-b"
    ManagedBy = "Terraform"
    Project   = "vmapp"
  }
}

resource "aws_route_table" "private" {
  vpc_id = var.vpc_id

  tags = {
    Name      = "vmapp-private-rt"
    ManagedBy = "Terraform"
    Project   = "vmapp"
  }
}

resource "aws_route_table_association" "private_a" {
  subnet_id      = aws_subnet.private_a.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "private_b" {
  subnet_id      = aws_subnet.private_b.id
  route_table_id = aws_route_table.private.id
}
