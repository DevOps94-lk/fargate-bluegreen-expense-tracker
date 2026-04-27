variable "name" {
  description = "Name prefix"
  type        = string
}

variable "environment" {
  description = "Deployment environment (dev | prod)"
  type        = string
}

variable "codedeploy_role_arn" {
  description = "IAM role ARN for CodeDeploy to assume"
  type        = string
}

variable "ecs_cluster_name" {
  description = "ECS cluster name"
  type        = string
}

variable "ecs_service_name" {
  description = "ECS service name"
  type        = string
}

variable "alb_listener_arn" {
  description = "ARN of the ALB production listener (port 80)"
  type        = string
}

variable "alb_test_listener_arn" {
  description = "ARN of the ALB test listener (port 8080) used during deployment"
  type        = string
}

variable "blue_target_group_name" {
  description = "Name of the blue target group"
  type        = string
}

variable "green_target_group_name" {
  description = "Name of the green target group"
  type        = string
}

variable "deployment_config" {
  description = "CodeDeploy deployment config (canary / linear / all-at-once)"
  type        = string
  default     = "CodeDeployDefault.ECSCanary10Percent5Minutes"
  # Options:
  #   CodeDeployDefault.ECSAllAtOnce
  #   CodeDeployDefault.ECSLinear10PercentEvery1Minutes
  #   CodeDeployDefault.ECSLinear10PercentEvery3Minutes
  #   CodeDeployDefault.ECSCanary10Percent5Minutes
  #   CodeDeployDefault.ECSCanary10Percent15Minutes
}

variable "termination_wait_minutes" {
  description = "Minutes to wait before terminating old (blue) tasks after successful deployment"
  type        = number
  default     = 5
}

variable "auto_rollback_events" {
  description = "Events that trigger an automatic rollback"
  type        = list(string)
  default     = ["DEPLOYMENT_FAILURE", "DEPLOYMENT_STOP_ON_ALARM"]
}

variable "tags" {
  description = "Extra tags"
  type        = map(string)
  default     = {}
}
