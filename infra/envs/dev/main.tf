locals {
  name        = "expense-tracker-dev"
  environment = "dev"
  azs         = ["ap-south-1a", "ap-south-1b"]

  tags = {
    Project     = "expense-tracker"
    Environment = local.environment
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# VPC
# ─────────────────────────────────────────────────────────────────────────────
module "vpc" {
  source = "../../modules/vpc"

  name        = local.name
  environment = local.environment

  vpc_cidr                 = "10.0.0.0/16"
  availability_zones       = local.azs
  public_subnet_cidrs      = ["10.0.1.0/24", "10.0.2.0/24"]
  private_app_subnet_cidrs = ["10.0.11.0/24", "10.0.12.0/24"]
  private_db_subnet_cidrs  = ["10.0.21.0/24", "10.0.22.0/24"]

  tags = local.tags
}

# ─────────────────────────────────────────────────────────────────────────────
# IAM (must come before RDS/ECS so ARNs are available)
# ─────────────────────────────────────────────────────────────────────────────
module "iam" {
  source = "../../modules/iam"

  name        = local.name
  environment = local.environment

  # Placeholder ARN — updated after RDS creates the SSM parameter
  database_url_ssm_arn = module.rds.database_url_ssm_arn

  tags = local.tags
}

# ─────────────────────────────────────────────────────────────────────────────
# RDS PostgreSQL
# ─────────────────────────────────────────────────────────────────────────────
module "rds" {
  source = "../../modules/rds"

  name        = local.name
  environment = local.environment

  vpc_id                = module.vpc.vpc_id
  private_db_subnet_ids = module.vpc.private_db_subnet_ids
  ecs_security_group_id = module.ecs.ecs_tasks_security_group_id

  db_name                  = "expense_tracker"
  db_username              = var.db_username
  db_password              = var.db_password
  db_instance_class        = "db.t3.micro"
  db_engine_version        = "16.3"
  db_allocated_storage     = 20
  db_max_allocated_storage = 50

  multi_az                     = false # Single-AZ in dev to save costs
  deletion_protection          = false
  backup_retention_days        = 3
  preferred_backup_window      = "03:00-04:00"
  preferred_maintenance_window = "Mon:04:00-Mon:05:00"

  tags = local.tags
}

# ─────────────────────────────────────────────────────────────────────────────
# ALB + Target Groups
# ─────────────────────────────────────────────────────────────────────────────
module "alb" {
  source = "../../modules/alb"

  name        = local.name
  environment = local.environment

  vpc_id            = module.vpc.vpc_id
  public_subnet_ids = module.vpc.public_subnet_ids

  container_port             = 8000
  health_check_path          = "/health"
  health_check_interval      = 30
  health_check_threshold     = 2
  deregistration_delay       = 30
  enable_deletion_protection = false

  tags = local.tags
}

# ─────────────────────────────────────────────────────────────────────────────
# ECS Fargate
# ─────────────────────────────────────────────────────────────────────────────
module "ecs" {
  source = "../../modules/ecs"

  name        = local.name
  environment = local.environment

  vpc_id                 = module.vpc.vpc_id
  private_app_subnet_ids = module.vpc.private_app_subnet_ids
  alb_security_group_id  = module.alb.alb_security_group_id
  rds_security_group_id  = module.rds.rds_security_group_id

  blue_target_group_arn   = module.alb.blue_target_group_arn
  task_execution_role_arn = module.iam.ecs_task_execution_role_arn
  task_role_arn           = module.iam.ecs_task_role_arn

  container_image  = var.container_image
  container_port   = 8000
  container_cpu    = 512
  container_memory = 1024
  desired_count    = 2

  database_url_ssm_arn = module.rds.database_url_ssm_arn

  tags = local.tags
}

# ─────────────────────────────────────────────────────────────────────────────
# CodeDeploy — Blue/Green
# ─────────────────────────────────────────────────────────────────────────────
module "codedeploy" {
  source = "../../modules/codedeploy"

  name        = local.name
  environment = local.environment

  codedeploy_role_arn = module.iam.codedeploy_role_arn
  ecs_cluster_name    = module.ecs.cluster_name
  ecs_service_name    = module.ecs.service_name

  alb_listener_arn      = module.alb.http_listener_arn
  alb_test_listener_arn = module.alb.test_listener_arn

  blue_target_group_name  = module.alb.blue_target_group_name
  green_target_group_name = module.alb.green_target_group_name

  # 10% canary for 5 min, then 100% — fast feedback in dev
  deployment_config        = "CodeDeployDefault.ECSCanary10Percent5Minutes"
  termination_wait_minutes = 5
  auto_rollback_events     = ["DEPLOYMENT_FAILURE"]

  tags = local.tags
}
