output "db_instance_id" {
  description = "RDS instance identifier"
  value       = aws_db_instance.this.id
}

output "db_endpoint" {
  description = "RDS connection endpoint (host:port)"
  value       = aws_db_instance.this.endpoint
}

output "db_address" {
  description = "RDS hostname"
  value       = aws_db_instance.this.address
}

output "db_port" {
  description = "RDS port"
  value       = aws_db_instance.this.port
}

output "db_name" {
  description = "Database name"
  value       = aws_db_instance.this.db_name
}

output "rds_security_group_id" {
  description = "Security group ID attached to RDS"
  value       = aws_security_group.rds.id
}

output "database_url_ssm_arn" {
  description = "ARN of the SSM SecureString parameter holding DATABASE_URL"
  value       = aws_ssm_parameter.database_url.arn
}

output "database_url_ssm_name" {
  description = "Name of the SSM parameter"
  value       = aws_ssm_parameter.database_url.name
}
