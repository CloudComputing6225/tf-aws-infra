provider "aws" {
  region = var.region
}

# Create VPC
resource "aws_vpc" "csye6225_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name = var.vpc_name
  }
}

# Create Internet Gateway and attach to VPC
resource "aws_internet_gateway" "csye6225_igw" {
  vpc_id = aws_vpc.csye6225_vpc.id
  tags = {
    Name = "${var.vpc_name}-igw"
  }
}

# Create public subnets
resource "aws_subnet" "public_subnets" {
  count                   = length(var.public_subnet_cidrs)
  vpc_id                  = aws_vpc.csye6225_vpc.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true
  tags = {
    Name = "${var.vpc_name}-public-subnet-${count.index + 1}"
  }
}

# Create private subnets
resource "aws_subnet" "private_subnets" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.csye6225_vpc.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]
  tags = {
    Name = "${var.vpc_name}-private-subnet-${count.index + 1}"
  }
}

# Create public route table
resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.csye6225_vpc.id
  tags = {
    Name = "${var.vpc_name}-public-rt"
  }
}

# Create route in public route table
resource "aws_route" "public_route" {
  route_table_id         = aws_route_table.public_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.csye6225_igw.id
}

# Associate public subnets with public route table
resource "aws_route_table_association" "public_rt_associations" {
  count          = length(var.public_subnet_cidrs)
  subnet_id      = aws_subnet.public_subnets[count.index].id
  route_table_id = aws_route_table.public_route_table.id
}

# Create private route table
resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.csye6225_vpc.id
  tags = {
    Name = "${var.vpc_name}-private-rt"
  }
}

# Associate private subnets with private route table
resource "aws_route_table_association" "private_rt_associations" {
  count          = length(var.private_subnet_cidrs)
  subnet_id      = aws_subnet.private_subnets[count.index].id
  route_table_id = aws_route_table.private_route_table.id
}

# Application Security Group (for EC2)
resource "aws_security_group" "app_sg" {
  name   = "csye6225-app-sg"
  vpc_id = aws_vpc.csye6225_vpc.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "csye6225-app-sg"
  }
}

# DB Security Group (for RDS)
resource "aws_security_group" "db_sg" {
  name   = "csye6225-db-sg"
  vpc_id = aws_vpc.csye6225_vpc.id

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.app_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "csye6225-db-sg"
  }
}

# S3 Bucket
resource "aws_s3_bucket" "app_bucket" {
  bucket        = uuid()
  force_destroy = true

  tags = {
    Name = "csye6225-app-bucket"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "bucket_encryption" {
  bucket = aws_s3_bucket.app_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "bucket_lifecycle" {
  bucket = aws_s3_bucket.app_bucket.id

  rule {
    id     = "transition-to-ia"
    status = "Enabled"

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }
  }
}

# IAM Role for EC2
resource "aws_iam_role" "ec2_s3_access_role" {
  name = "EC2-S3-Access-Role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

# IAM Policy for S3 access
resource "aws_iam_policy" "s3_access_policy" {
  name        = "S3-Access-Policy"
  description = "Policy for EC2 to access S3"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:DeleteObject"
        ]
        Resource = "${aws_s3_bucket.app_bucket.arn}/*"
      }
    ]
  })
}

# CloudWatch log group
resource "aws_cloudwatch_log_group" "app_log_group" {
  name              = "/opt/app/webapp"
  retention_in_days = 30
}

# IAM Policy for CloudWatch logging
resource "aws_iam_policy" "cloudwatch_logging_policy" {
  name        = "CloudWatchLoggingPolicy"
  description = "Allows EC2 instances to write logs to CloudWatch"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Resource = "*"
      }
    ]
  })
}

# Attach policies to role
resource "aws_iam_role_policy_attachment" "s3_access_attachment" {
  policy_arn = aws_iam_policy.s3_access_policy.arn
  role       = aws_iam_role.ec2_s3_access_role.name
}

resource "aws_iam_role_policy_attachment" "cloudwatch_logging_attachment" {
  policy_arn = aws_iam_policy.cloudwatch_logging_policy.arn
  role       = aws_iam_role.ec2_s3_access_role.name
}

# CloudWatchAgentServerPolicy attachment
data "aws_iam_policy" "cloudwatch_agent_server_policy" {
  arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_role_policy_attachment" "cloudwatch_agent_policy_attachment" {
  policy_arn = data.aws_iam_policy.cloudwatch_agent_server_policy.arn
  role       = aws_iam_role.ec2_s3_access_role.name
}

# Instance Profile
resource "aws_iam_instance_profile" "ec2_profile" {
  name = "EC2-S3-Profile"
  role = aws_iam_role.ec2_s3_access_role.name
}

# EC2 Instance
resource "aws_instance" "app_instance" {
  ami                    = var.ami_id
  instance_type          = "t2.micro"
  vpc_security_group_ids = [aws_security_group.app_sg.id]
  subnet_id              = aws_subnet.public_subnets[0].id
  iam_instance_profile   = aws_iam_instance_profile.ec2_profile.name

  root_block_device {
    volume_size           = 25
    volume_type           = "gp2"
    delete_on_termination = true
  }

  user_data = <<-EOF
    #!/bin/bash
    DB_HOST=$(echo "${aws_db_instance.db_instance.address}")
    echo "DB_HOST=$DB_HOST" >> /opt/app/.env
    echo "DB_USER=${var.db_username}" >> /opt/app/.env
    echo "DB_PASSWORD=${var.db_password}" >> /opt/app/.env
    echo "DB_NAME=${var.db_name}" >> /opt/app/.env
    echo "DB_DIALECT=mysql" >> /opt/app/.env
    echo "PORT=8080" >> /opt/app/.env
    echo "S3_BUCKET_NAME=${aws_s3_bucket.app_bucket.id}" >> /opt/app/.env
    echo "S3_BUCKET_URL=https://${aws_s3_bucket.app_bucket.bucket_regional_domain_name}" >> /opt/app/.env
    echo "AWS_REGION=us-east-1" >> /opt/app/.env
    chmod 644 /opt/app/.env
    export $(grep -v '^#' /opt/app/.env | xargs)
    sudo touch /opt/app/webapp.log
    sudo chmod 644 /opt/app/webapp.log
    sudo chown root:root /opt/app/webapp.log
    # Add test log entry
    echo "Test log entry: Instance started at $(date)" | sudo tee -a /opt/app/webapp.log
    # Configure and start CloudWatch agent
    cat <<EOT > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json
    {
      "agent": {
        "metrics_collection_interval": 5,
        "run_as_user": "root"
      },
      "logs": {
        "logs_collected": {
          "files": {
            "collect_list": [
              {
                "file_path": "/opt/app/webapp.log",
                "log_group_name": "csye6225",
                "log_stream_name": "webapp"
              }
            ]
          }
        }
      },
      "metrics": {
        "metrics_collected": {
          "statsd": {
            "service_address": ":8125",
            "metrics_collection_interval": 5,
            "metrics_aggregation_interval": 5
          }
        }
      }
    }
    EOT
    
    /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -s -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json
    systemctl restart webapp.service
  EOF

  tags = {
    Name = "csye6225-ec2-instance"
  }
}

# RDS Parameter Group
resource "aws_db_parameter_group" "db_param_group" {
  name   = "csye6225-db-param-group"
  family = "mysql8.0"

  parameter {
    name  = "max_connections"
    value = "100"
  }

  tags = {
    Name = "csye6225-db-param-group"
  }
}

# RDS Subnet Group (for private subnets)
resource "aws_db_subnet_group" "db_subnet_group" {
  name       = "csye6225-db-subnet-group"
  subnet_ids = aws_subnet.private_subnets[*].id

  tags = {
    Name = "csye6225-db-subnet-group"
  }
}

# RDS Instance
resource "aws_db_instance" "db_instance" {
  identifier             = "csye6225"
  engine                 = "mysql"
  instance_class         = "db.t3.micro"
  allocated_storage      = 20
  username               = var.db_username
  password               = var.db_password
  db_subnet_group_name   = aws_db_subnet_group.db_subnet_group.name
  vpc_security_group_ids = [aws_security_group.db_sg.id]
  parameter_group_name   = aws_db_parameter_group.db_param_group.name
  publicly_accessible    = false
  skip_final_snapshot    = true
  multi_az               = false
  db_name                = var.db_name
  engine_version         = "8.0.39"

  tags = {
    Name = "csye6225-db-instance"
  }
}

# Route 53 A Record
resource "aws_route53_record" "app_record" {
  zone_id = var.route53_zone_id
  name    = var.domain_name
  type    = "A"
  ttl     = 300
  records = [aws_instance.app_instance.public_ip]
}

resource "aws_route53_record" "dkim" {
  zone_id = var.route53_zone_id
  name    = "mailo._domainkey.${var.domain_name}"
  type    = "TXT"
  ttl     = "300"
  records = [
    "k=rsa; p=MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQCqJuOCyceEXAS2SwmuK/TQGVzdUaoBk0Mdb6PCwLISHuPz08p8TwJPsTJeUzkrq6Zb2oy9VcjozFx/+cfcKOnXsfDGYG6HmehPZz74jMcpq2SHjyTY5LbSpTDKmga9R8ewc/IoHk6jUcD7nXnW6ea4p+HVXoUI5L6uO7i7LKPQpwIDAQAB"
  ]
}

resource "aws_route53_record" "spf" {
  zone_id = var.route53_zone_id
  name    = var.domain_name
  type    = "TXT"
  ttl     = "300"
  records = [
    "v=spf1 include:mailgun.org ~all"
  ]
}

resource "aws_route53_record" "mx1" {
  zone_id = var.route53_zone_id
  name    = var.domain_name
  type    = "MX"
  ttl     = "300"
  records = [
    "10 mxa.mailgun.org"
  ]
}


resource "aws_route53_record" "email_cname" {
  zone_id = var.route53_zone_id
  name    = "email.${var.domain_name}"
  type    = "CNAME"
  ttl     = "300"
  records = [
    "mailgun.org"
  ]
}

