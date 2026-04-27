output "app_name" {
  description = "CodeDeploy application name"
  value       = aws_codedeploy_app.this.name
}

output "app_id" {
  description = "CodeDeploy application ID"
  value       = aws_codedeploy_app.this.id
}

output "deployment_group_name" {
  description = "CodeDeploy deployment group name"
  value       = aws_codedeploy_deployment_group.this.deployment_group_name
}

output "deployment_group_id" {
  description = "CodeDeploy deployment group ID"
  value       = aws_codedeploy_deployment_group.this.id
}

output "deployment_config_name" {
  description = "Deployment configuration in use"
  value       = var.deployment_config
}
