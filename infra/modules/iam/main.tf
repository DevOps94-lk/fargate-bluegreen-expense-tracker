locals {
  common_tags = merge(var.tags, {
    Environment = var.environment
    ManagedBy   = "terraform"
    Module      = "iam"
  })
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ─────────────────────────────────────────────────────────────────────────────
# ECS Task Execution Role
# Used by the ECS agent to pull images from ECR, fetch SSM secrets,
# and write logs to CloudWatch — NOT used by application code.
# ─────────────────────────────────────────────────────────────────────────────
resource "aws_iam_role" "ecs_task_execution" {
  name        = "${var.name}-ecs-task-execution-role"
  description = "ECS agent role - ECR pull, SSM secrets, CloudWatch logs"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "ECSTasksAssumeRole"
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })

  tags = local.common_tags
}

# AWS managed policy grants ECR pull, CloudWatch log creation, and SSM access
resource "aws_iam_role_policy_attachment" "ecs_task_execution_managed" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Additional policy: allow the execution role to fetch specific SSM SecureStrings
resource "aws_iam_role_policy" "ecs_task_execution_ssm" {
  name = "${var.name}-ecs-execution-ssm"
  role = aws_iam_role.ecs_task_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "GetSSMSecrets"
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:GetParametersByPath"
        ]
        Resource = var.database_url_ssm_arn
      },
      {
        Sid    = "DecryptSSMSecrets"
        Effect = "Allow"
        Action = ["kms:Decrypt"]
        # Restrict to the default SSM key in this account/region
        Resource = "arn:aws:kms:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:alias/aws/ssm"
      }
    ]
  })
}

# ─────────────────────────────────────────────────────────────────────────────
# ECS Task Role
# Granted to application code running inside the container.
# Principle of least privilege: start empty, add only what the app needs.
# ─────────────────────────────────────────────────────────────────────────────
resource "aws_iam_role" "ecs_task" {
  name        = "${var.name}-ecs-task-role"
  description = "Application role - scoped to what the Expense Tracker code actually calls"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "ECSTasksAssumeRole"
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })

  tags = local.common_tags
}

# Minimal policy: application-level permissions only
resource "aws_iam_role_policy" "ecs_task_app" {
  name = "${var.name}-ecs-task-app-policy"
  role = aws_iam_role.ecs_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CloudWatchMetrics"
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData",
          "cloudwatch:GetMetricData"
        ]
        Resource = "*"
      },
      {
        Sid    = "XRayTracing"
        Effect = "Allow"
        Action = [
          "xray:PutTraceSegments",
          "xray:PutTelemetryRecords",
          "xray:GetSamplingRules",
          "xray:GetSamplingTargets"
        ]
        Resource = "*"
      }
    ]
  })
}

# ─────────────────────────────────────────────────────────────────────────────
# CodeDeploy Role
# Allows CodeDeploy to manage ECS blue/green deployments:
# update ECS services, swap ALB listener rules, and register task definitions.
# ─────────────────────────────────────────────────────────────────────────────
resource "aws_iam_role" "codedeploy" {
  name        = "${var.name}-codedeploy-role"
  description = "CodeDeploy service role for ECS blue/green deployments"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "CodeDeployAssumeRole"
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "codedeploy.amazonaws.com" }
    }]
  })

  tags = local.common_tags
}

# AWS managed policy for ECS blue/green deployments
resource "aws_iam_role_policy_attachment" "codedeploy_ecs" {
  role       = aws_iam_role.codedeploy.name
  policy_arn = "arn:aws:iam::aws:policy/AWSCodeDeployRoleForECS"
}
