variable "name" {
  description = "Name prefix"
  type        = string
}

variable "environment" {
  description = "Deployment environment (dev | prod)"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where the ALB will be deployed"
  type        = string
}

variable "public_subnet_ids" {
  description = "Public subnet IDs for the ALB"
  type        = list(string)
}

variable "container_port" {
  description = "Port the ECS container listens on"
  type        = number
  default     = 3000
}

variable "health_check_path" {
  description = "Health check path for both target groups"
  type        = string
  default     = "/health"
}

variable "health_check_interval" {
  description = "Health check interval in seconds"
  type        = number
  default     = 30
}

variable "health_check_threshold" {
  description = "Healthy threshold count"
  type        = number
  default     = 2
}

variable "deregistration_delay" {
  description = "Target group deregistration delay (seconds)"
  type        = number
  default     = 30
}

variable "enable_deletion_protection" {
  description = "Enable ALB deletion protection"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Extra tags"
  type        = map(string)
  default     = {}
}
