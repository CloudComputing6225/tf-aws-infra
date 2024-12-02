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

# Load Balancer Security Group
resource "aws_security_group" "lb_sg" {
  name        = "load-balancer-security-group"
  description = "Security group for load balancer"
  vpc_id      = aws_vpc.csye6225_vpc.id

  ingress {
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "load-balancer-security-group"
  }
}

# Application Security Group (for EC2)
resource "aws_security_group" "app_sg" {
  name   = "csye6225-app-sg"
  vpc_id = aws_vpc.csye6225_vpc.id

  ingress {
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.lb_sg.id]
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
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.s3_key.arn
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

resource "aws_acm_certificate" "ssl_cert" {
  domain_name       = var.domain_name
  validation_method = "DNS"

  tags = {
    Name = "csye6225-ssl-cert"
  }

  lifecycle {
    create_before_destroy = true
  }
}
# KMS Key for Secret Manager
resource "aws_kms_key" "secret_manager_key" {
  description             = "KMS key for Secret Manager"
  deletion_window_in_days = 10
  enable_key_rotation     = true
  rotation_period_in_days = 90
  tags = {
    Name = "csye6225-secret-manager-kms-key"
  }
}

# KMS Key for Email Service
resource "aws_kms_key" "email_service_key" {
  description             = "KMS key for Email Service"
  deletion_window_in_days = 10
  enable_key_rotation     = true
  rotation_period_in_days = 90
  tags = {
    Name = "csye6225-email-service-kms-key"
  }
}

# Secret for RDS Database Password
resource "aws_secretsmanager_secret" "db_password" {
  name        = "new-csye6225-db-password6"
  description = "RDS Database Password"
  kms_key_id  = aws_kms_key.secret_manager_key.arn
}


resource "aws_secretsmanager_secret_version" "db_password" {
  secret_id     = aws_secretsmanager_secret.db_password.id
  secret_string = var.db_password
}

# Secret for Email Service Credentials
resource "aws_secretsmanager_secret" "email_credentials" {
  name        = "new-csye6225-email-credentials6"
  description = "Email Service Credentials"
  kms_key_id  = aws_kms_key.email_service_key.arn
}

resource "aws_secretsmanager_secret_version" "email_credentials" {
  secret_id     = aws_secretsmanager_secret.email_credentials.id
  secret_string = var.mailgun_api_key
  # domain  = var.mailgun_domain
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
# KMS Key for EC2
resource "aws_kms_key" "ec2_key" {
  description             = "KMS key for EC2 instances"
  deletion_window_in_days = 10
  enable_key_rotation     = true
  rotation_period_in_days = 90

  tags = {
    Name = "csye6225-ec2-kms-key"
  }
}

# KMS Key for RDS
resource "aws_kms_key" "rds_key" {
  description             = "KMS key for RDS instances"
  deletion_window_in_days = 10
  enable_key_rotation     = true
  rotation_period_in_days = 90

  tags = {
    Name = "csye6225-rds-kms-key"
  }
}

# KMS Key for S3
resource "aws_kms_key" "s3_key" {
  description             = "KMS key for S3 buckets"
  deletion_window_in_days = 10
  enable_key_rotation     = true
  rotation_period_in_days = 90

  tags = {
    Name = "csye6225-s3-kms-key"
  }
}

# SNS Topic for user registration
resource "aws_sns_topic" "user_registration" {
  name = "user-registration-topic"
}

# Lambda Function for email verification
resource "aws_lambda_function" "email_verification" {
  filename         = var.lambda_zip_path
  function_name    = "email-verification"
  role             = aws_iam_role.lambda_exec.arn
  handler          = "index.handler"
  source_code_hash = filebase64sha256(var.lambda_zip_path)
  runtime          = "nodejs20.x"

  environment {
    variables = {
      MAILGUN_API_KEY = aws_secretsmanager_secret.email_credentials.name
      SNS_TOPIC_ARN   = aws_sns_topic.user_registration.arn
    }
  }
}
resource "aws_iam_policy" "kms_access_policy" {
  name        = "KMS-Access-Policy"
  description = "Policy for EC2 to access KMS keys"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = [
          "*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "kms_access_attachment" {
  policy_arn = aws_iam_policy.kms_access_policy.arn
  role       = aws_iam_role.ec2_s3_access_role.name
}

# IAM Role for Lambda
resource "aws_iam_role" "lambda_exec" {
  name = "lambda-email-verification-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_policy" "secret_manager_policy" {
  name        = "ec2-secret-manager-access"
  description = "IAM policy for ec2 to access SM"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
        ]
        Resource = [
          aws_secretsmanager_secret.db_password.arn,
          aws_secretsmanager_secret.email_credentials.arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:Encrypt",
          "kms:DescribeSecret"
        ]
        Resource = [
          aws_kms_key.secret_manager_key.arn,
          aws_kms_key.email_service_key.arn
        ]
      }
    ]
  })
}
resource "aws_iam_policy" "lambda_secrets_policy" {
  name        = "lambda-secrets-policy"
  description = "IAM policy for Lambda to access Secrets Manager"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
        ]
        Resource = [
          aws_secretsmanager_secret.db_password.arn,
          aws_secretsmanager_secret.email_credentials.arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:Encrypt",
          "kms:DescribeSecret"
        ]
        Resource = [
          aws_kms_key.secret_manager_key.arn,
          aws_kms_key.email_service_key.arn
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ec2-secret-policy_attachment" {
  policy_arn = aws_iam_policy.secret_manager_policy.arn
  role       = aws_iam_role.ec2_s3_access_role.name
}
resource "aws_iam_role_policy_attachment" "lambda_secrets_policy_attachment" {
  policy_arn = aws_iam_policy.lambda_secrets_policy.arn
  role       = aws_iam_role.lambda_exec.name
}

# IAM Policy for Lambda
resource "aws_iam_role_policy_attachment" "lambda_exec_policy" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  role       = aws_iam_role.lambda_exec.name
}

# SNS Topic Subscription
resource "aws_sns_topic_subscription" "user_registration_lambda" {
  topic_arn = aws_sns_topic.user_registration.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.email_verification.arn
}

# Lambda Permission for SNS
resource "aws_lambda_permission" "allow_sns" {
  statement_id  = "AllowSNSInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.email_verification.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.user_registration.arn
}

# Update EC2 IAM Role to allow SNS publish
resource "aws_iam_role_policy_attachment" "ec2_sns_publish" {
  policy_arn = aws_iam_policy.sns_publish_policy.arn
  role       = aws_iam_role.ec2_s3_access_role.name
}

resource "aws_iam_policy" "sns_publish_policy" {
  name        = "SNSPublishPolicy"
  description = "Allows EC2 instances to publish to SNS"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = aws_sns_topic.user_registration.arn
      }
    ]
  })
}


# Launch Template
resource "aws_launch_template" "app_launch_template" {
  name                   = "csye6225_asg"
  image_id               = var.ami_id
  instance_type          = "t2.micro"
  key_name               = "csye6225"
  vpc_security_group_ids = [aws_security_group.app_sg.id]

  iam_instance_profile {
    name = aws_iam_instance_profile.ec2_profile.name
  }
  # block_device_mappings {
  #   device_name = "/dev/sda1"
  #   ebs {
  #     volume_size           = 25
  #     volume_type           = "gp2"
  #     delete_on_termination = true
  #     encrypted             = true
  #     kms_key_id            = aws_kms_key.ec2_key.arn
  #   }
  # }
  # depends_on = [
  #   aws_kms_key.ec2_key
  # ]

  user_data = base64encode(<<-EOF
              #!/bin/bash
              # Update system and install necessary packages
              sudo apt-get update
              sudo apt-get install -y unzip curl
              # Download and install AWS CLI v2
              curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
              unzip awscliv2.zip
              sudo ./aws/install
              # Check AWS CLI installation
              aws --version
              DB_HOST=$(echo "${aws_db_instance.db_instance.address}")
              echo "DB_HOST=$DB_HOST" >> /opt/app/.env
              echo "DB_USER=${var.db_username}" >> /opt/app/.env
              DB_PASSWORD=$(aws secretsmanager get-secret-value --secret-id "new-csye6225-db-password6" --query 'SecretString' --output text)
              echo "DB_PASSWORD=$DB_PASSWORD" >> /opt/app/.env
              echo "DB_NAME=${var.db_name}" >> /opt/app/.env
              echo "DB_DIALECT=mysql" >> /opt/app/.env
              echo "PORT=8080" >> /opt/app/.env
              echo "S3_BUCKET_NAME=${aws_s3_bucket.app_bucket.id}" >> /opt/app/.env
              echo "S3_BUCKET_URL=https://${aws_s3_bucket.app_bucket.bucket_regional_domain_name}" >> /opt/app/.env
              echo "AWS_REGION=${var.region}" >> /opt/app/.env
              echo "SNS_TOPIC_ARN=${aws_sns_topic.user_registration.arn}" >> /opt/app/.env
              MAILGUN_API_KEY=$(aws secretsmanager get-secret-value --secret-id "new-csye6225-email-credentials6" --query 'SecretString' --output text)
              echo "MAILGUN_API_KEY=$MAILGUN_API_KEY" >> /opt/app/.env
              echo "MAILGUN_DOMAIN=${var.mailgun_domain}" >> /opt/app/.env
              chmod 644 /opt/app/.env
              export $(grep -v '^#' /opt/app/.env | xargs)
              sudo touch /opt/app/webapp.log
              sudo chmod 644 /opt/app/webapp.log
              sudo chown root:root /opt/app/webapp.log
              echo "Test log entry: Instance started at $(date)" | sudo tee -a /opt/app/webapp.log
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
  )

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "csye6225-ec2-instance"
    }
  }
}

# Auto Scaling Group configuration
resource "aws_autoscaling_group" "app_asg" {
  name                = "csye6225-asg"
  vpc_zone_identifier = aws_subnet.public_subnets[*].id
  launch_template {
    id      = aws_launch_template.app_launch_template.id
    version = "$Latest"
  }
  min_size          = 1
  max_size          = 2
  desired_capacity  = 1
  target_group_arns = [aws_lb_target_group.app_tg.arn]

  tag {
    key                 = "Name"
    value               = "csye6225-asg-instance"
    propagate_at_launch = true
  }
}

# Scale Up Policy when CPU utilization exceeds 9%
resource "aws_autoscaling_policy" "scale_up" {
  name                   = "scale-up"
  autoscaling_group_name = aws_autoscaling_group.app_asg.name
  policy_type            = "SimpleScaling"
  adjustment_type        = "ChangeInCapacity"
  scaling_adjustment     = 1
  cooldown               = 60
}

resource "aws_cloudwatch_metric_alarm" "high_cpu_utilization" {
  alarm_name          = "High-CPU-Utilization"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 60
  statistic           = "Average"
  threshold           = 9.0
  alarm_description   = "This alarm triggers a scale-up action if CPU utilization exceeds 9%."
  alarm_actions       = [aws_autoscaling_policy.scale_up.arn]

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.app_asg.name
  }
}

# Scale Down Policy when CPU utilization falls below 7%
resource "aws_autoscaling_policy" "scale_down" {
  name                   = "scale-down"
  autoscaling_group_name = aws_autoscaling_group.app_asg.name
  policy_type            = "SimpleScaling"
  adjustment_type        = "ChangeInCapacity"
  scaling_adjustment     = -1
  cooldown               = 60
}

resource "aws_cloudwatch_metric_alarm" "low_cpu_utilization" {
  alarm_name          = "Low-CPU-Utilization"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 60
  statistic           = "Average"
  threshold           = 7.0
  alarm_description   = "This alarm triggers a scale-down action if CPU utilization falls below 7%."
  alarm_actions       = [aws_autoscaling_policy.scale_down.arn]

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.app_asg.name
  }
}

# Application Load Balancer
resource "aws_lb" "app_lb" {
  name               = "csye6225-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.lb_sg.id]
  subnets            = aws_subnet.public_subnets[*].id

  tags = {
    Name = "csye6225-lb"
  }
}

resource "aws_lb_target_group" "app_tg" {
  name     = "csye6225-tg"
  port     = 8080
  protocol = "HTTP"
  vpc_id   = aws_vpc.csye6225_vpc.id

  health_check {
    path                = "/healthz"
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 30
  }
}

data "aws_acm_certificate" "issued" {
  domain   = var.domain_name
  statuses = ["ISSUED"]
}
resource "aws_lb_listener" "app_listener" {
  load_balancer_arn = aws_lb.app_lb.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = data.aws_acm_certificate.issued.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app_tg.arn
  }
}

# Route53 DNS Update
resource "aws_route53_record" "app_dns" {
  zone_id = var.route53_zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_lb.app_lb.dns_name
    zone_id                = aws_lb.app_lb.zone_id
    evaluate_target_health = true
  }
}
# # DKIM TXT Record for email validation
# resource "aws_route53_record" "dkim" {
#   zone_id = var.route53_zone_id
#   name    = "mailo._domainkey.${var.domain_name}"
#   type    = "TXT"
#   ttl     = 300
#   records = [
#     "k=rsa; p=MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQCqJuOCyceEXAS2SwmuK/TQGVzdUaoBk0Mdb6PCwLISHuPz08p8TwJPsTJeUzkrq6Zb2oy9VcjozFx/+cfcKOnXsfDGYG6HmehPZz74jMcpq2SHjyTY5LbSpTDKmga9R8ewc/IoHk6jUcD7nXnW6ea4p+HVXoUI5L6uO7i7LKPQpwIDAQAB"
#   ]
# }

# SPF TXT Record for email sender policy
resource "aws_route53_record" "spf" {
  zone_id = var.route53_zone_id
  name    = var.domain_name
  type    = "TXT"
  ttl     = 300
  records = [
    "v=spf1 include:mailgun.org ~all"
  ]
}

# MX Records for email receiving
resource "aws_route53_record" "mx1" {
  zone_id = var.route53_zone_id
  name    = var.domain_name
  type    = "MX"
  ttl     = 300
  records = [
    "10 mxa.mailgun.org",
    "10 mxb.mailgun.org"
  ]
}

# CNAME Record for email subdomain handling
resource "aws_route53_record" "email_cname" {
  zone_id = var.route53_zone_id
  name    = "email.${var.domain_name}"
  type    = "CNAME"
  ttl     = 300
  records = [
    "mailgun.org"
  ]
}
# resource "aws_route53_record" "ssl_cname" {
#   zone_id = var.route53_zone_id
#   name    = "_4c1b455ce39586c08892b716e7a48979.dev.saurabhprojects.me"
#   type    = "CNAME"
#   ttl     = 300
#   records = [
#     "AD53B295043CA73F1AC63A81A08098CB.DCD7026B4CFE6E17B80FC84A2D4BE629.572d5c8bd342d4b.comodoca.com"
#   ]
# }


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
  engine_version         = "8.0.39"
  instance_class         = "db.t3.micro"
  allocated_storage      = 20
  username               = var.db_username
  password               = var.db_password
  db_name                = var.db_name
  db_subnet_group_name   = aws_db_subnet_group.db_subnet_group.name
  vpc_security_group_ids = [aws_security_group.db_sg.id]
  parameter_group_name   = aws_db_parameter_group.db_param_group.name
  publicly_accessible    = false
  skip_final_snapshot    = true
  multi_az               = false
  storage_encrypted      = true
  kms_key_id             = aws_kms_key.rds_key.arn
  tags = {
    Name = "csye6225-db-instance"
  }
}
