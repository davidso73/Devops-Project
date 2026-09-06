# A single EC2 instance used only as a Docker/kubectl/helm/awscli host, since
# none of that tooling can run natively on the Windows machine driving this
# project (same constraint, same fix, as using the frontend instance as the
# Ansible control node in the previous phase). Not part of the app itself.

data "aws_ssm_parameter" "al2023_ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

resource "aws_security_group" "build_host" {
  name        = "vmapp-eks-buildhost-sg"
  description = "SSH only, from anywhere (demo convenience - see README security notes)"
  vpc_id      = var.vpc_id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "vmapp-eks-buildhost-sg", Project = "vmapp-eks" }
}

resource "aws_iam_role" "build_host" {
  name               = "vmapp-eks-buildhost-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

resource "aws_iam_role_policy_attachment" "build_host_ecr" {
  role       = aws_iam_role.build_host.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser"
}

resource "aws_iam_role_policy" "build_host_eks_describe" {
  name = "vmapp-eks-buildhost-eks-describe"
  role = aws_iam_role.build_host.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["eks:DescribeCluster"]
        Resource = aws_eks_cluster.this.arn
      }
    ]
  })
}

resource "aws_iam_instance_profile" "build_host" {
  name = "vmapp-eks-buildhost-profile"
  role = aws_iam_role.build_host.name
}

resource "aws_instance" "build_host" {
  ami                         = data.aws_ssm_parameter.al2023_ami.value
  instance_type               = var.build_host_instance_type
  subnet_id                   = var.public_subnet_ids[0]
  vpc_security_group_ids      = [aws_security_group.build_host.id]
  key_name                    = var.key_name
  iam_instance_profile        = aws_iam_instance_profile.build_host.name
  associate_public_ip_address = true

  root_block_device {
    volume_size = 30 # room for Docker images/layers
  }

  tags = { Name = "vmapp-eks-buildhost", Project = "vmapp-eks" }
}
