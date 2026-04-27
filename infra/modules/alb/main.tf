locals {
  common_tags = merge(var.tags, {
    Environment = var.environment
    ManagedBy   = "terraform"
    Module      = "alb"
  })
}

# ─────────────────────────────────────────────────────────────────────────────
# Security Group — ALB
# Inbound:  80 (production), 8080 (test/CodeDeploy) from internet
# Outbound: to ECS tasks on container port
# ─────────────────────────────────────────────────────────────────────────────
resource "aws_security_group" "alb" {
  name        = "${var.name}-alb-sg"
  description = "Allow HTTP traffic to ALB; test port for CodeDeploy blue/green"
  vpc_id      = var.vpc_id

  ingress {
    description = "Production HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Port 8080 is the CodeDeploy test listener — receives shifted traffic
  # during a blue/green deployment before production cutover
  ingress {
    description = "CodeDeploy test listener"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Outbound to ECS tasks"
    from_port   = var.container_port
    to_port     = var.container_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(local.common_tags, { Name = "${var.name}-alb-sg" })
}

# ─────────────────────────────────────────────────────────────────────────────
# Application Load Balancer
# ─────────────────────────────────────────────────────────────────────────────
resource "aws_lb" "this" {
  name               = "${var.name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = var.public_subnet_ids

  enable_deletion_protection = var.enable_deletion_protection

  # Drop invalid HTTP headers for security
  drop_invalid_header_fields = true

  tags = merge(local.common_tags, { Name = "${var.name}-alb" })
}

# ─────────────────────────────────────────────────────────────────────────────
# Target Groups — Blue (active) and Green (standby)
# Both are identical; CodeDeploy swaps traffic between them at deploy time
# ─────────────────────────────────────────────────────────────────────────────
resource "aws_lb_target_group" "blue" {
  name                 = "${var.name}-tg-blue"
  port                 = var.container_port
  protocol             = "HTTP"
  vpc_id               = var.vpc_id
  target_type          = "ip" # Required for ECS Fargate (awsvpc network mode)
  deregistration_delay = var.deregistration_delay

  health_check {
    enabled             = true
    path                = var.health_check_path
    protocol            = "HTTP"
    interval            = var.health_check_interval
    timeout             = 5
    healthy_threshold   = var.health_check_threshold
    unhealthy_threshold = 3
    matcher             = "200-299"
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(local.common_tags, { Name = "${var.name}-tg-blue", Color = "blue" })
}

resource "aws_lb_target_group" "green" {
  name                 = "${var.name}-tg-green"
  port                 = var.container_port
  protocol             = "HTTP"
  vpc_id               = var.vpc_id
  target_type          = "ip"
  deregistration_delay = var.deregistration_delay

  health_check {
    enabled             = true
    path                = var.health_check_path
    protocol            = "HTTP"
    interval            = var.health_check_interval
    timeout             = 5
    healthy_threshold   = var.health_check_threshold
    unhealthy_threshold = 3
    matcher             = "200-299"
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(local.common_tags, { Name = "${var.name}-tg-green", Color = "green" })
}

# ─────────────────────────────────────────────────────────────────────────────
# Listeners
# Port 80  → production traffic → blue TG (initial; CodeDeploy updates this)
# Port 8080 → test traffic       → green TG (CodeDeploy shifts here first)
# ─────────────────────────────────────────────────────────────────────────────
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.blue.arn
  }

  # CodeDeploy manages the listener rules during deployments.
  # Ignore changes so Terraform doesn't fight CodeDeploy post-deployment.
  lifecycle {
    ignore_changes = [default_action]
  }

  tags = merge(local.common_tags, { Name = "${var.name}-listener-http" })
}

resource "aws_lb_listener" "test" {
  load_balancer_arn = aws_lb.this.arn
  port              = 8080
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.green.arn
  }

  lifecycle {
    ignore_changes = [default_action]
  }

  tags = merge(local.common_tags, { Name = "${var.name}-listener-test" })
}
