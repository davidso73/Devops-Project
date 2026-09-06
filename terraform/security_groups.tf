# Backend + worker share this security group. Per the app's requirement, they must
# only be reachable from the frontend and from each other ("themselves") - never
# directly from the internet.
resource "aws_security_group" "vmapp_internal" {
  name        = "vmapp-internal-sg"
  description = "Backend/worker: reachable only from the frontend and from each other"
  vpc_id      = var.vpc_id

  ingress {
    description     = "App port (gunicorn) from frontend"
    from_port       = 8000
    to_port         = 8000
    protocol        = "tcp"
    security_groups = [var.existing_ec2_sg_id]
  }

  ingress {
    description     = "SSH from frontend (jump host - backend/worker have no public IP)"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [var.existing_ec2_sg_id]
  }

  ingress {
    description = "Backend and worker can talk to each other / themselves"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  egress {
    description = "Needed to reach the VPC endpoints (S3/SQS/SNS) and RDS"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "vmapp-internal-sg"
    Project = "vmapp"
  }
}

# Add access for backend/worker to the existing RDS security group, without
# touching its current rules.
resource "aws_security_group_rule" "rds_from_vmapp_internal" {
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = var.existing_rds_sg_id
  source_security_group_id = aws_security_group.vmapp_internal.id
  description              = "PostgreSQL from vmapp backend/worker"
}
