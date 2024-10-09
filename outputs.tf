# outputs.tf

output "vpc_id" {
  description = "ID of the created VPC"
  value       = aws_vpc.csye6225_vpc.id
}

output "public_subnets" {
  description = "IDs of the public subnets"
  value       = aws_subnet.public_subnets[*].id
}

output "private_subnets" {
  description = "IDs of the private subnets"
  value       = aws_subnet.private_subnets[*].id
}

output "internet_gateway_id" {
  description = "ID of the Internet Gateway"
  value       = aws_internet_gateway.csye6225_igw.id
}

output "public_route_table_id" {
  description = "ID of the Public Route Table"
  value       = aws_route_table.public_route_table.id
}

output "private_route_table_id" {
  description = "ID of the Private Route Table"
  value       = aws_route_table.private_route_table.id
}
