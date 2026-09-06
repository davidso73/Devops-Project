# EKS-dedicated private subnets. Larger than the EC2 app stack's /24s because
# the VPC CNI hands every pod a real VPC IP - a couple of t3.medium nodes
# alone can consume dozens of addresses. Kept separate from the EC2 stack's
# private subnets to avoid any IP-budget coupling between the two phases.
resource "aws_subnet" "eks_private_a" {
  vpc_id            = var.vpc_id
  cidr_block        = "10.0.32.0/20"
  availability_zone = "il-central-1a"

  tags = {
    Name                                        = "vmapp-eks-private-a"
    ManagedBy                                   = "Terraform"
    Project                                     = "vmapp-eks"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    "kubernetes.io/role/internal-elb"           = "1"
  }
}

resource "aws_subnet" "eks_private_b" {
  vpc_id            = var.vpc_id
  cidr_block        = "10.0.48.0/20"
  availability_zone = "il-central-1b"

  tags = {
    Name                                        = "vmapp-eks-private-b"
    ManagedBy                                   = "Terraform"
    Project                                     = "vmapp-eks"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    "kubernetes.io/role/internal-elb"           = "1"
  }
}

# EKS nodes need broad AWS API reachability (ECR, EKS, STS for IRSA,
# CloudWatch, ELB) - enough distinct services that a NAT Gateway is simpler
# and about the same cost as the many VPC endpoints that would otherwise be
# needed, unlike the simple 3-tier app's SQS/SNS/S3-only egress.
resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name    = "vmapp-eks-nat-eip"
    Project = "vmapp-eks"
  }
}

resource "aws_nat_gateway" "eks" {
  allocation_id = aws_eip.nat.id
  subnet_id     = var.public_subnet_ids[0]

  tags = {
    Name    = "vmapp-eks-nat"
    Project = "vmapp-eks"
  }
}

resource "aws_route_table" "eks_private" {
  vpc_id = var.vpc_id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.eks.id
  }

  tags = {
    Name    = "vmapp-eks-private-rt"
    Project = "vmapp-eks"
  }
}

resource "aws_route_table_association" "eks_private_a" {
  subnet_id      = aws_subnet.eks_private_a.id
  route_table_id = aws_route_table.eks_private.id
}

resource "aws_route_table_association" "eks_private_b" {
  subnet_id      = aws_subnet.eks_private_b.id
  route_table_id = aws_route_table.eks_private.id
}

# ALB auto-discovery needs this tag on the public subnets it can place an
# internet-facing load balancer into. Non-destructive - adds a tag to an
# existing, shared resource without touching anything else about it.
resource "aws_ec2_tag" "public_subnet_elb_role" {
  for_each    = toset(var.public_subnet_ids)
  resource_id = each.value
  key         = "kubernetes.io/role/elb"
  value       = "1"
}

resource "aws_ec2_tag" "public_subnet_cluster" {
  for_each    = toset(var.public_subnet_ids)
  resource_id = each.value
  key         = "kubernetes.io/cluster/${var.cluster_name}"
  value       = "shared"
}
