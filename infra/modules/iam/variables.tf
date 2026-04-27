variable "name" {
  description = "Name prefix"
  type        = string
}

variable "environment" {
  description = "Deployment environment (dev | prod)"
  type        = string
}

variable "database_url_ssm_arn" {
  description = "ARN of the SSM parameter the ECS task reads at runtime"
  type        = string
}

variable "tags" {
  description = "Extra tags"
  type        = map(string)
  default     = {}
}
