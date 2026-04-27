locals {
  common_tags = merge(var.tags, {
    Environment = var.environment
    ManagedBy   = "terraform"
    Module      = "codedeploy"
  })
}

# ─────────────────────────────────────────────────────────────────────────────
# CodeDeploy Application
# One application per service. All deployment groups belong to this app.
# ─────────────────────────────────────────────────────────────────────────────
resource "aws_codedeploy_app" "this" {
  name             = "${var.name}-app"
  compute_platform = "ECS"

  tags = merge(local.common_tags, { Name = "${var.name}-app" })
}

# ─────────────────────────────────────────────────────────────────────────────
# CodeDeploy Deployment Group — ECS Blue/Green
#
# Deployment flow:
#   1. CodeDeploy registers a new task definition revision
#   2. Launches replacement (green) tasks in the green target group
#   3. Shifts the TEST listener (8080) to green for smoke testing
#   4. Waits for health checks to pass
#   5. Shifts PRODUCTION listener (80) traffic to green
#      (canary: 10% immediately → 100% after 5 min)
#   6. Waits termination_wait_minutes then terminates old blue tasks
#
# On any alarm or failure → automatic rollback to blue
# ─────────────────────────────────────────────────────────────────────────────
resource "aws_codedeploy_deployment_group" "this" {
  app_name               = aws_codedeploy_app.this.name
  deployment_group_name  = "${var.name}-deployment-group"
  service_role_arn       = var.codedeploy_role_arn
  deployment_config_name = var.deployment_config

  ecs_service {
    cluster_name = var.ecs_cluster_name
    service_name = var.ecs_service_name
  }

  deployment_style {
    deployment_option = "WITH_TRAFFIC_CONTROL"
    deployment_type   = "BLUE_GREEN"
  }

  blue_green_deployment_config {
    deployment_ready_option {
      # CONTINUE_DEPLOYMENT: automatically shift traffic without waiting for
      # manual approval. Change to STOP_DEPLOYMENT for manual gate.
      action_on_timeout = "CONTINUE_DEPLOYMENT"
    }

    terminate_blue_instances_on_deployment_success {
      action                           = "TERMINATE"
      termination_wait_time_in_minutes = var.termination_wait_minutes
    }
  }

  load_balancer_info {
    target_group_pair_info {
      # Production listener: serves live traffic
      prod_traffic_route {
        listener_arns = [var.alb_listener_arn]
      }

      # Test listener: receives canary/shifted traffic during deployment
      # Allows integration tests or smoke tests to run against new version
      # before it receives production traffic
      test_traffic_route {
        listener_arns = [var.alb_test_listener_arn]
      }

      target_group {
        name = var.blue_target_group_name
      }

      target_group {
        name = var.green_target_group_name
      }
    }
  }

  auto_rollback_configuration {
    enabled = true
    events  = var.auto_rollback_events
  }

  tags = merge(local.common_tags, { Name = "${var.name}-deployment-group" })
}
