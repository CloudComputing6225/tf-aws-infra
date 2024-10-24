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
    security_groups = [aws_security_group.app_sg.id] # Allow from app_sg
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

# EC2 Instance
resource "aws_instance" "app_instance" {
  ami                    = var.ami_id # Replace with your custom AMI ID
  instance_type          = "t2.micro"
  vpc_security_group_ids = [aws_security_group.app_sg.id]
  subnet_id              = aws_subnet.public_subnets[0].id

  root_block_device {
    volume_size           = 25
    volume_type           = "gp2"
    delete_on_termination = true
  }

  # Pass database credentials via user data
  user_data = <<-EOF
    #!/bin/bash
    DB_HOST=$(echo "${aws_db_instance.db_instance.address}")
    echo "DB_HOST=$DB_HOST" >> /opt/app/.env
    echo "DB_USER=${var.db_username}" >> /opt/app/.env
    echo "DB_PASSWORD=${var.db_password}" >> /opt/app/.env
    echo "DB_NAME=${var.db_name}" >> /opt/app/.env
    echo "DB_DIALECT=mysql" >> /opt/app/.env
    echo "PORT=8080" >> /opt/app/.env
    chmod 644 /opt/app/.env
    export $(grep -v '^#' /opt/app/.env | xargs)
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
