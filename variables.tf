# variables.tf

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
}

variable "availability_zones" {
  description = "List of availability zones to use"
  type        = list(string)
}

variable "region" {
  description = "AWS Region"
  type        = string
}

variable "vpc_name" {
  description = "Name for the VPC"
  type        = string
}
variable "ami_id" {
  description = "The AMI ID for the EC2 instance"
  type        = string
}
variable "db_password" {
  description = "RDS master password"
  type        = string
  sensitive   = true
}

variable "db_username" {
  description = "RDS master name"
  type        = string
}

variable "db_name" {
  description = "RDS database name"
  type        = string
}

variable "domain_name" {
  description = "RDS database name"
  type        = string
}

variable "route53_zone_id" {
  description = "Route53 Hosted Zone ID"
  type        = string
}
