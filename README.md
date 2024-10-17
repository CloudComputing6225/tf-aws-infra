# tf-aws-infra
# Assignment 3

# AWS Networking Setup with Terraform

This repository contains the Terraform configuration files to set up the networking infrastructure in AWS. The infrastructure includes a Virtual Private Cloud (VPC), public and private subnets, an Internet Gateway, and route tables. The setup is designed to be modular, allowing multiple VPCs and subnets to be created across different availability zones in the same AWS account and region.

# Prerequisites

An AWS account with access credentials (AWS Access Key ID and Secret Access Key).

Terraform v1.x or later installed on your local machine.

Basic knowledge of Terraform and AWS.

# Instructions to run

Clone the repository

Install terraform in your local

Add terraform.tfvars and update the configurations

`terraform init`

`terraform plan`

`terraform apply`

To destroy: `terraform destroy`


# Assignment 4

# Overview

This project uses Terraform to create AWS infrastructure, including a VPC, subnets, route tables, security groups, and an EC2 instance with a custom AMI. The setup ensures that the instance hosts a web application securely.

# Prerequisites

AWS CLI configured with access credentials.

Terraform (v1.0+).

A custom AMI ID pre-configured with the application.


# Author
Saurabh Srivastava

email: srivastava.sau@northeastern.edu

NUID: 002895225



