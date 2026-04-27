locals {
  common_tags = merge(var.tags, {
    Environment = var.environment
    ManagedBy   = "terraform"
    Module      = "rds"
  })
}

# ─────────────────────────────────────────────────────────────────────────────
# Security Group — RDS
# Only accepts inbound connections from ECS tasks on PostgreSQL port
# ─────────────────────────────────────────────────────────────────────────────
resource "aws_security_group" "rds" {
  name        = "${var.name}-rds-sg"
  description = "PostgreSQL access from ECS tasks only"
  vpc_id      = var.vpc_id

  ingress {
    description     = "PostgreSQL from ECS tasks"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [var.ecs_security_group_id]
  }

  # No egress rules needed — RDS only responds to inbound queries
  egress {
    description = "Allow all outbound (responses handled by stateful SG)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(local.common_tags, { Name = "${var.name}-rds-sg" })
}

# ─────────────────────────────────────────────────────────────────────────────
# DB Subnet Group — uses private DB subnets (no internet access)
# ─────────────────────────────────────────────────────────────────────────────
resource "aws_db_subnet_group" "this" {
  name        = "${var.name}-db-subnet-group"
  description = "Private DB subnets for ${var.name} RDS"
  subnet_ids  = var.private_db_subnet_ids

  tags = merge(local.common_tags, { Name = "${var.name}-db-subnet-group" })
}

# ─────────────────────────────────────────────────────────────────────────────
# RDS PostgreSQL Instance
# ─────────────────────────────────────────────────────────────────────────────
resource "aws_db_instance" "this" {
  identifier = "${var.name}-postgres"

  engine         = "postgres"
  engine_version = var.db_engine_version
  instance_class = var.db_instance_class

  allocated_storage     = var.db_allocated_storage
  max_allocated_storage = var.db_max_allocated_storage
  storage_type          = "gp3"
  storage_encrypted     = true

  db_name  = var.db_name
  username = var.db_username
  password = var.db_password

  # CRITICAL: never expose RDS to the internet
  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false
  multi_az               = var.multi_az
  port                   = 5432

  backup_retention_period   = var.backup_retention_days
  backup_window             = var.preferred_backup_window
  maintenance_window        = var.preferred_maintenance_window
  copy_tags_to_snapshot     = true
  delete_automated_backups  = false
  final_snapshot_identifier = "${var.name}-final-snapshot"
  skip_final_snapshot       = false

  deletion_protection        = var.deletion_protection
  auto_minor_version_upgrade = true

  tags = merge(local.common_tags, { Name = "${var.name}-postgres" })
}

# ─────────────────────────────────────────────────────────────────────────────
# SSM Parameter — DATABASE_URL
# Stored as SecureString so it is encrypted at rest and never appears in logs.
# ECS tasks reference this parameter ARN in their secrets block.
# ─────────────────────────────────────────────────────────────────────────────
resource "aws_ssm_parameter" "database_url" {
  name  = "/${var.environment}/${var.name}/DATABASE_URL"
  type  = "SecureString"
  value = "postgresql://${var.db_username}:${var.db_password}@${aws_db_instance.this.endpoint}/${var.db_name}"

  tags = merge(local.common_tags, { Name = "${var.name}-database-url" })
}
