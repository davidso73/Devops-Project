variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "il-central-1"
}

variable "aws_profile" {
  description = "AWS CLI profile used by Terraform"
  type        = string
  default     = "dev-profile"
}

variable "vpc_id" {
  description = "Existing VPC to build this app inside (dev-enviroment-vpc)"
  type        = string
  default     = "vpc-078790f7a168052e8"
}

variable "public_subnet_id" {
  description = "Existing public subnet for the frontend instance (dev-enviroment-public-a)"
  type        = string
  default     = "subnet-0f6983cf583671932"
}

variable "existing_ec2_sg_id" {
  description = "Existing EC2 security group (dev-enviroment-ec2-sg) - allows 22/80 from the internet, used by the frontend"
  type        = string
  default     = "sg-07fc3eed9422e090a"
}

variable "existing_rds_sg_id" {
  description = "Existing RDS security group (dev-enviroment-rds-sg)"
  type        = string
  default     = "sg-038aba6aca62a3ebc"
}

variable "s3_bucket_name" {
  description = "Existing S3 bucket reused for the app's user-choice files"
  type        = string
  default     = "nginx-content-832767338129-il-central-1-an"
}

variable "key_name" {
  description = "Existing EC2 key pair for SSH access"
  type        = string
  default     = "david-key"
}

variable "instance_type" {
  description = "EC2 instance type for frontend/backend/worker"
  type        = string
  default     = "t3.micro"
}

variable "ami_id" {
  description = "AMI ID for frontend/backend/worker. Leave empty to auto-resolve the latest Amazon Linux 2023 (x86_64) AMI via SSM."
  type        = string
  default     = ""
}

variable "db_name" {
  description = "PostgreSQL database name"
  type        = string
  default     = "vmappdb"
}

variable "db_username" {
  description = "PostgreSQL master username"
  type        = string
  default     = "vmappadmin"
}

variable "notification_email" {
  description = "Email address subscribed to the SNS notifications topic"
  type        = string
  default     = "david.sosi@gmail.com"
}
