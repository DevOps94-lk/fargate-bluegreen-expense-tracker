output "cluster_id" {
  description = "ECS cluster ID"
  value       = aws_ecs_cluster.this.id
}

output "cluster_name" {
  description = "ECS cluster name"
  value       = aws_ecs_cluster.this.name
}

output "service_name" {
  description = "ECS service name"
  value       = aws_ecs_service.app.name
}

output "service_id" {
  description = "ECS service ID"
  value       = aws_ecs_service.app.id
}

output "task_definition_arn" {
  description = "Latest task definition ARN (initial revision)"
  value       = aws_ecs_task_definition.app.arn
}

output "task_definition_family" {
  description = "Task definition family name"
  value       = aws_ecs_task_definition.app.family
}

output "ecs_tasks_security_group_id" {
  description = "ECS tasks security group ID"
  value       = aws_security_group.ecs_tasks.id
}

output "log_group_name" {
  description = "CloudWatch log group name for ECS tasks"
  value       = aws_cloudwatch_log_group.app.name
}
