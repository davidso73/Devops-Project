# Private egress without a NAT Gateway: an S3 gateway endpoint (free - also covers
# Amazon Linux's S3-backed dnf/yum repos) plus interface endpoints for the two AWS
# APIs backend/worker actually call directly: SQS and SNS.

resource "aws_security_group" "vpc_endpoints" {
  name        = "vmapp-vpc-endpoints-sg"
  description = "Allow HTTPS from vmapp backend/worker to the interface endpoints"
  vpc_id      = var.vpc_id

  ingress {
    description     = "HTTPS from vmapp internal instances"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.vmapp_internal.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "vmapp-vpc-endpoints-sg"
    Project = "vmapp"
  }
}

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = var.vpc_id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private.id]

  tags = {
    Name    = "vmapp-s3-endpoint"
    Project = "vmapp"
  }
}

resource "aws_vpc_endpoint" "sqs" {
  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.sqs"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.private_a.id, aws_subnet.private_b.id]
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = {
    Name    = "vmapp-sqs-endpoint"
    Project = "vmapp"
  }
}

resource "aws_vpc_endpoint" "sns" {
  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.sns"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.private_a.id, aws_subnet.private_b.id]
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = {
    Name    = "vmapp-sns-endpoint"
    Project = "vmapp"
  }
}
