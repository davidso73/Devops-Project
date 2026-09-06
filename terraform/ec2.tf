data "aws_ssm_parameter" "al2023_ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

locals {
  # Use var.ami_id if explicitly set, otherwise fall back to the latest AL2023 AMI.
  ami_id = var.ami_id != "" ? var.ami_id : data.aws_ssm_parameter.al2023_ami.value
}

resource "aws_instance" "backend" {
  ami                    = local.ami_id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.private_a.id
  vpc_security_group_ids = [aws_security_group.vmapp_internal.id]
  key_name               = var.key_name
  iam_instance_profile   = aws_iam_instance_profile.backend.name

  # No user_data: Ansible (see ../Ansible) owns all software configuration.
  # Terraform's job here stops at "a bare, correctly networked/secured instance".

  tags = {
    Name    = "vmapp-backend"
    Project = "vmapp"
  }

  depends_on = [
    aws_vpc_endpoint.s3,
    aws_vpc_endpoint.sqs,
    aws_vpc_endpoint.sns,
    aws_db_instance.vmapp,
  ]
}

resource "aws_instance" "worker" {
  ami                    = local.ami_id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.private_b.id
  vpc_security_group_ids = [aws_security_group.vmapp_internal.id]
  key_name               = var.key_name
  iam_instance_profile   = aws_iam_instance_profile.worker.name

  tags = {
    Name    = "vmapp-worker"
    Project = "vmapp"
  }

  depends_on = [
    aws_vpc_endpoint.s3,
    aws_vpc_endpoint.sqs,
    aws_vpc_endpoint.sns,
    aws_db_instance.vmapp,
  ]
}

resource "aws_instance" "frontend" {
  ami                         = local.ami_id
  instance_type               = var.instance_type
  subnet_id                   = var.public_subnet_id
  vpc_security_group_ids      = [var.existing_ec2_sg_id]
  key_name                    = var.key_name
  associate_public_ip_address = true

  tags = {
    Name    = "vmapp-frontend"
    Project = "vmapp"
  }
}
