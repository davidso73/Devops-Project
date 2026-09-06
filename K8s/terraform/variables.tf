variable "aws_region" {
  type    = string
  default = "il-central-1"
}

variable "aws_profile" {
  type    = string
  default = "dev-profile"
}

# --- Values shared with the existing ../../terraform stack. Deliberately
# passed as variables (not a terraform_remote_state data source) so this
# EKS phase stays fully independent - it can be applied/destroyed without
# touching or depending on the other stack's state. ---

variable "vpc_id" {
  description = "Existing VPC (dev-enviroment-vpc) - same one the EC2 app stack runs in"
  type        = string
  default     = "vpc-078790f7a168052e8"
}

variable "public_subnet_ids" {
  description = "Existing public subnets (dev-enviroment-public-a/b) - used for the build host and tagged for ALB discovery"
  type        = list(string)
  default     = ["subnet-0f6983cf583671932", "subnet-0c27fec8db6f7fbdd"]
}

variable "public_route_table_id" {
  description = "Existing public route table, so the new NAT Gateway's EIP association can be verified against it (informational only, not modified)"
  type        = string
  default     = "rtb-0bac736b229ad7d6a"
}

variable "existing_rds_sg_id" {
  description = "Existing RDS security group (dev-enviroment-rds-sg) - gets a new ingress rule for the EKS node security group"
  type        = string
  default     = "sg-038aba6aca62a3ebc"
}

variable "existing_vpc_endpoints_sg_id" {
  description = "Existing SQS/SNS VPC interface endpoint security group (from the EC2 stack) - gets a new ingress rule so EKS pods can use it too. Needed because VPC-endpoint private DNS resolves VPC-wide, so EKS pods resolve sns./sqs.<region>.amazonaws.com to this endpoint's private IP even though they were never otherwise going to use it."
  type        = string
  default     = "sg-0de108e1c67290fcd"
}

variable "s3_bucket_name" {
  type    = string
  default = "nginx-content-832767338129-il-central-1-an"
}

variable "sqs_queue_arn" {
  type    = string
  default = "arn:aws:sqs:il-central-1:832767338129:vmapp-requests-queue"
}

variable "sns_topic_arn" {
  type    = string
  default = "arn:aws:sns:il-central-1:832767338129:vmapp-notifications"
}

variable "key_name" {
  description = "Existing EC2 key pair, reused for SSH to the build host"
  type        = string
  default     = "david-key"
}

# --- New resources for this phase ---

variable "cluster_name" {
  type    = string
  default = "vmapp-eks"
}

variable "node_instance_type" {
  # t3.medium was rejected by an account guardrail: ASG-launched (i.e. EKS
  # managed node group) instances must be free-tier-eligible in this account.
  # t3.small is free-tier-eligible here and gives more headroom than t3.micro
  # (2GB vs 1GB RAM) for kubelet/kube-proxy/CNI overhead plus app pods.
  type    = string
  default = "t3.small"
}

variable "node_desired_size" {
  type    = number
  default = 2
}

variable "build_host_instance_type" {
  type    = string
  default = "t3.small"
}
