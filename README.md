# AWS Infrastructure as Code

## Overview
This repository contains Terraform configurations for setting up a complete AWS infrastructure for a cloud-native web application. The infrastructure includes networking, compute, storage, security, and monitoring components with high availability and security best practices.

## Architecture Components

### Networking
- Custom VPC with DNS support
- 3 Public and 3 Private Subnets across different availability zones
- Internet Gateway
- Public and Private Route Tables
- Network ACLs and Security Groups

### Security Groups
1. Load Balancer Security Group
   - Inbound: HTTPS (443)
   - Outbound: All traffic
2. Application Security Group
   - Inbound: Port 8080 from Load Balancer
   - Outbound: All traffic
3. Database Security Group
   - Inbound: MySQL (3306) from Application
   - Outbound: All traffic

### Compute
- Launch Template with custom AMI
- Auto Scaling Group (Min: 1, Max: 2)
- Application Load Balancer with HTTPS listener
- EC2 instances with IAM roles and user data

### Storage
- S3 Bucket with:
  - Server-side encryption (KMS)
  - Lifecycle policy (transition to IA after 30 days)
  - Force destroy enabled

### Database
- RDS MySQL instance with:
  - Private subnet placement
  - Custom parameter group
  - Encryption at rest
  - Automated backups
  - Multi-AZ disabled for dev

### Encryption & Security
- KMS keys for:
  - EC2 instances
  - RDS database
  - S3 bucket
  - Secrets Manager
  - Email service
- SSL/TLS certificate integration
- Secrets Manager for sensitive data

### Monitoring & Logging
- CloudWatch Log Groups
- CloudWatch Metrics
- Auto Scaling Policies based on CPU utilization
- Custom metrics via CloudWatch agent

### DNS & Email
- Route53 DNS configuration
- Email service integration with SPF and MX records
- HTTPS endpoint configuration

## Prerequisites

- AWS CLI configured with appropriate credentials
- Terraform >= 1.0
- Valid SSL certificate
- Domain name configured in Route53

## Required Variables

Create a `terraform.tfvars` file with:

```hcl
region               = "us-east-1"
vpc_cidr             = "10.0.0.0/16"
vpc_name             = "csye6225-vpc"
domain_name          = "your-domain.com"
route53_zone_id      = "YOUR_ZONE_ID"
ami_id               = "ami-xxxxx"
db_username          = "admin"
db_password          = "password"
db_name              = "csye6225"
mailgun_api_key      = "your-mailgun-key"
mailgun_domain       = "your-mailgun-domain"
lambda_zip_path      = "path/to/lambda.zip"
```

## Usage

1. Initialize Terraform:
```bash
terraform init
```

2. Plan the infrastructure:
```bash
terraform plan -var-file="terraform.tfvars"
```

3. Apply the configuration:
```bash
terraform apply -var-file="terraform.tfvars"
```

4. Destroy the infrastructure:
```bash
terraform destroy -var-file="terraform.tfvars"
```

## Security Features

### Encryption
- All EBS volumes encrypted
- RDS storage encrypted
- S3 bucket objects encrypted
- Secrets encrypted in Secrets Manager
- SSL/TLS for in-transit encryption

### Access Control
- Least privilege IAM roles
- Security group restrictions
- Private subnet isolation
- KMS key rotation enabled

## Auto Scaling Configuration

### Scale Up Policy
- Triggers when CPU > 9%
- Cooldown: 60 seconds
- Adds one instance

### Scale Down Policy
- Triggers when CPU < 7%
- Cooldown: 60 seconds
- Removes one instance

## Monitoring Setup

### CloudWatch Agent Configuration
- Custom metrics collection
- Application log monitoring
- System metrics monitoring
- StatsD metrics support

## Important Notes

1. Database credentials are stored in Secrets Manager
2. Email service credentials are stored in Secrets Manager
3. All KMS keys have 90-day rotation enabled
4. SSL certificate must be imported before applying
5. Lambda function code must be zipped and available at specified path

## Networking Details

### CIDR Blocks
- VPC: 10.0.0.0/16
- Public Subnets: Configured via variables
- Private Subnets: Configured via variables

### Route Tables
- Public: Route to Internet Gateway
- Private: Local routes only

## Maintenance

### Backup and Recovery
- RDS automated backups configured
- S3 lifecycle policies for cost optimization
- AMI backups managed separately

### Updates and Patches
- Use AMI updates for EC2 instances
- RDS maintenance window configured
- Auto Scaling Group handles instance updates

## Troubleshooting

### Common Issues
1. SSL Certificate Issues
   - Verify ACM certificate status
   - Check Route53 records

2. Auto Scaling Issues
   - Verify Launch Template
   - Check CloudWatch metrics
   - Review scaling policies

3. Database Connectivity
   - Verify security group rules
   - Check subnet connectivity
   - Validate credentials in Secrets Manager

## Contributing

1. Fork the repository
2. Create feature branch
3. Commit changes
4. Create Pull Request
5. Ensure CI checks pass

## License
This project is proprietary and confidential.