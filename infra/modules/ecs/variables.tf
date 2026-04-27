variable "name" {
  description = "Name prefix"
  type        = string
}

variable "environment" {
  description = "Deployment environment (dev | prod)"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "private_app_subnet_ids" {
  description = "Private app subnet IDs for ECS tasks"
  type        = list(string)
}

variable "alb_security_group_id" {
  description = "Security group ID of the ALB (source for inbound rules)"
  type        = string
}

variable "private_db_subnet_cidrs" {
  description = "CIDR blocks of the private DB subnets (used for egress to RDS)"
  type        = list(string)
}

variable "blue_target_group_arn" {
  description = "ARN of the blue target group (initial active group)"
  type        = string
}

variable "task_execution_role_arn" {
  description = "ARN of the ECS task execution IAM role"
  type        = string
}

variable "task_role_arn" {
  description = "ARN of the ECS task IAM role"
  type        = string
}

variable "container_image" {
  description = "Full ECR image URI (e.g. 123456789.dkr.ecr.us-east-1.amazonaws.com/app:latest)"
  type        = string
}

variable "container_port" {
  description = "Port the container exposes"
  type        = number
  default     = 3000
}

variable "container_cpu" {
  description = "vCPU units for the task (256 = 0.25 vCPU)"
  type        = number
  default     = 512
}

variable "container_memory" {
  description = "Memory (MiB) for the task"
  type        = number
  default     = 1024
}

variable "desired_count" {
  description = "Desired number of running tasks"
  type        = number
  default     = 2
}

variable "database_url_ssm_arn" {
  description = "ARN of the SSM SecureString parameter holding DATABASE_URL"
  type        = string
}

variable "tags" {
  description = "Extra tags"
  type        = map(string)
  default     = {}
}
