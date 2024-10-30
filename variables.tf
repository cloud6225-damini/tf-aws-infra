# Variables for region, CIDR blocks, and subnet CIDRs
variable "aws_region" {
  description = "The AWS region to create resources in."
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for the public subnets"
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for the private subnets"
  type        = list(string)
}

# Custom AMI for EC2
variable "custom_ami" {
  description = "AMI ID for the EC2 instance"
  type        = string
}

# Application Port
variable "app_port" {
  description = "Port on which the application runs"
  type        = number
  default     = 3000
}

# Database Password
variable "db_password" {
  description = "Password for the RDS instance"
  type        = string
  default     = "23101996"
}

variable "db_port" {
  default = "3306"
}

variable "vpc_name" {
  default = "mainvpc"
}

variable "subnet_count" {
  default = "3"
}

variable "db_engine" {
  default = "mysql"
}

variable "db_username" {
  default = "cloud6225"
}

variable "db_name" {
  default = "cloud6225"
}

variable "db_group_family" {
  default = "mysql8.0"
}

variable "sendgrid_api_key" {
  description = "API key for SendGrid"
  type        = string
}

variable "s3_bucket_name" {
  description = "Name of the S3 bucket for storing images"
  type        = string
}
