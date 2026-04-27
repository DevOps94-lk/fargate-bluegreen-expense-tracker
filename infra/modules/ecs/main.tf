locals {
  common_tags = merge(var.tags, {
    Environment = var.environment
    ManagedBy   = "terraform"
    Module      = "ecs"
  })
}

# ─────────────────────────────────────────────────────────────────────────────
# CloudWatch Log Group for ECS tasks
# ─────────────────────────────────────────────────────────────────────────────
resource "aws_cloudwatch_log_group" "app" {
  name              = "/ecs/${var.name}/app"
  retention_in_days = 7
  tags              = local.common_tags
}

# ─────────────────────────────────────────────────────────────────────────────
# ECS Cluster
# ─────────────────────────────────────────────────────────────────────────────
resource "aws_ecs_cluster" "this" {
  name = "${var.name}-cluster"
  tags = merge(local.common_tags, { Name = "${var.name}-cluster" })
}

resource "aws_ecs_cluster_capacity_providers" "this" {
  cluster_name       = aws_ecs_cluster.this.name
  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  default_capacity_provider_strategy {
    base              = 1
    weight            = 100
    capacity_provider = "FARGATE"
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# ECS Task Definition
# Terraform creates the initial task definition; CodeDeploy manages
# subsequent revisions through the blue/green deployment process.
# ─────────────────────────────────────────────────────────────────────────────
resource "aws_ecs_task_definition" "app" {
  family                   = "${var.name}-app"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.container_cpu
  memory                   = var.container_memory
  execution_role_arn       = var.task_execution_role_arn
  task_role_arn            = var.task_role_arn

  container_definitions = jsonencode([
    {
      name      = "${var.name}-app"
      image     = var.container_image
      essential = true

      portMappings = [
        {
          containerPort = var.container_port
          protocol      = "tcp"
        }
      ]

      # DATABASE_URL is injected from SSM Parameter Store at task launch.
      # The value is never stored in the task definition or Terraform state.
      secrets = [
        {
          name      = "DATABASE_URL"
          valueFrom = var.database_url_ssm_arn
        }
      ]

      environment = [
        {
          name  = "PORT"
          value = tostring(var.container_port)
        },
        {
          name  = "NODE_ENV"
          value = var.environment
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.app.name
          "awslogs-region"        = data.aws_region.current.name
          "awslogs-stream-prefix" = "app"
        }
      }

      healthCheck = {
        command     = ["CMD-SHELL", "curl -f http://localhost:${var.container_port}/health || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 60
      }
    }
  ])

  tags = merge(local.common_tags, { Name = "${var.name}-task-def" })
}

data "aws_region" "current" {}

# ─────────────────────────────────────────────────────────────────────────────
# Security Group — ECS Tasks
# Inbound:  from ALB SG on container port only
# Outbound: to RDS on 5432, to internet for ECR/SSM/CloudWatch (HTTPS 443)
# ─────────────────────────────────────────────────────────────────────────────
resource "aws_security_group" "ecs_tasks" {
  name        = "${var.name}-ecs-tasks-sg"
  description = "ECS Fargate tasks — allow traffic from ALB, outbound to RDS and AWS APIs"
  vpc_id      = var.vpc_id

  ingress {
    description     = "HTTP from ALB"
    from_port       = var.container_port
    to_port         = var.container_port
    protocol        = "tcp"
    security_groups = [var.alb_security_group_id]
  }

  egress {
    description = "PostgreSQL to RDS (private DB subnets)"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = var.private_db_subnet_cidrs
  }

  egress {
    description = "HTTPS to AWS APIs (ECR, SSM, CloudWatch)"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(local.common_tags, { Name = "${var.name}-ecs-tasks-sg" })
}

# ─────────────────────────────────────────────────────────────────────────────
# ECS Service
#
# deployment_controller = CODE_DEPLOY enables blue/green deployments.
# After the initial Terraform apply, CodeDeploy owns:
#   - task_definition (each deploy registers a new revision)
#   - load_balancer   (CodeDeploy swaps TG references)
# We use ignore_changes to prevent Terraform from reverting those.
# ─────────────────────────────────────────────────────────────────────────────
resource "aws_ecs_service" "app" {
  name            = "${var.name}-service"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  deployment_controller {
    type = "CODE_DEPLOY"
  }

  network_configuration {
    subnets          = var.private_app_subnet_ids
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = false
  }

  # Initial registration against the BLUE target group.
  # CodeDeploy will shift production traffic to GREEN during a deployment
  # and update this binding afterwards.
  load_balancer {
    target_group_arn = var.blue_target_group_arn
    container_name   = "${var.name}-app"
    container_port   = var.container_port
  }

  health_check_grace_period_seconds = 120

  lifecycle {
    # CodeDeploy manages these after the initial apply — let it.
    ignore_changes = [task_definition, load_balancer, desired_count]
  }

  tags = merge(local.common_tags, { Name = "${var.name}-service" })

  depends_on = [aws_ecs_cluster.this]
}
