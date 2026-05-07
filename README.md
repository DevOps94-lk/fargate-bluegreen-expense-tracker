# Fargate Blue/Green Deployment Platform

A production-grade expense tracker application deployed on AWS ECS Fargate using CodeDeploy blue/green deployments, Terraform infrastructure-as-code, Atlantis GitOps, and GitHub Actions CI/CD.

---

## Table of Contents

- [Application Overview](#application-overview)
- [AWS Architecture](#aws-architecture)
- [Network Design](#network-design)
- [Traffic Flow](#traffic-flow)
- [Blue/Green Deployment Flow](#bluegreen-deployment-flow)
- [Terraform Infrastructure](#terraform-infrastructure)
- [Atlantis GitOps](#atlantis-gitops)
- [GitHub Actions Pipelines](#github-actions-pipelines)
- [Security](#security)
- [How to Deploy](#how-to-deploy)

---

## Application Overview

**Expense Tracker** — a personal finance app built with FastAPI (Python) and a vanilla JS/HTML/CSS frontend.

| Layer     | Technology                          |
|-----------|-------------------------------------|
| Frontend  | HTML, CSS, JavaScript (vanilla)     |
| Backend   | Python 3.12, FastAPI, Uvicorn       |
| Database  | PostgreSQL 16.6 (AWS RDS)           |
| Container | Docker (`python:3.12-slim`)         |
| Registry  | AWS ECR                             |

**API endpoints:**

| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/categories/` | List all categories |
| POST | `/api/categories/` | Create a category |
| GET | `/api/expenses/` | List expenses (filterable) |
| POST | `/api/expenses/` | Create an expense |
| PUT | `/api/expenses/{id}` | Update an expense |
| DELETE | `/api/expenses/{id}` | Delete an expense |
| GET | `/api/expenses/summary` | Spending summary |
| GET | `/health` | ALB health check |
| GET | `/` | Frontend (static files) |

On startup the app automatically creates database tables and seeds 8 default categories (Food, Transport, Housing, Entertainment, Health, Shopping, Education, Other).

---

## AWS Architecture

```
                         ┌─────────────────────────────────────────────────────┐
                         │                    AWS ap-south-1                    │
                         │                                                     │
  Internet               │   ┌─────────────────────────────────────────────┐  │
  ─────────►  ALB        │   │               VPC  10.0.0.0/16              │  │
  port 80   (public)─────┼───►  Public Subnets (10.0.1.0/24, 10.0.2.0/24) │  │
  port 8080              │   │  ┌──────────┐  ┌──────────┐                 │  │
                         │   │  │ NAT GW   │  │ NAT GW   │                 │  │
                         │   │  │ ap-south │  │ ap-south │                 │  │
                         │   │  │   -1a    │  │   -1b    │                 │  │
                         │   └──┴────┬─────┴──┴────┬─────┘                │  │
                         │           │              │                      │  │
                         │   ┌───────▼──────────────▼───────────────────┐  │  │
                         │   │    Private App Subnets                   │  │  │
                         │   │  10.0.11.0/24        10.0.12.0/24        │  │  │
                         │   │  ┌────────────┐  ┌────────────┐          │  │  │
                         │   │  │ ECS Task   │  │ ECS Task   │          │  │  │
                         │   │  │ (Fargate)  │  │ (Fargate)  │          │  │  │
                         │   │  │ port 8000  │  │ port 8000  │          │  │  │
                         │   │  └────────────┘  └────────────┘          │  │  │
                         │   └───────────────────────────┬───────────────┘  │  │
                         │                               │                  │  │
                         │   ┌───────────────────────────▼───────────────┐  │  │
                         │   │    Private DB Subnets                     │  │  │
                         │   │  10.0.21.0/24        10.0.22.0/24         │  │  │
                         │   │  ┌─────────────────────────────────────┐  │  │  │
                         │   │  │  RDS PostgreSQL 16.6  (db.t3.micro) │  │  │  │
                         │   │  │  port 5432  (no internet access)    │  │  │  │
                         │   │  └─────────────────────────────────────┘  │  │  │
                         │   └───────────────────────────────────────────┘  │  │
                         │                                                   │  │
                         └───────────────────────────────────────────────────┘  │
                                                                                │
       ┌────────────────────────────────────────────────────────────────────────┘
       │  Supporting services (all in ap-south-1)
       │
       ├── ECR          — Docker image registry (expense-tracker repo)
       ├── CodeDeploy   — Blue/green deployment orchestration
       ├── SSM          — DATABASE_URL stored as SecureString
       └── CloudWatch   — ECS task logs (/ecs/expense-tracker-dev/app)
```

---

## Network Design

| Subnet Tier | CIDR | AZs | Internet Access |
|-------------|------|-----|-----------------|
| Public | 10.0.1.0/24, 10.0.2.0/24 | ap-south-1a, ap-south-1b | Via Internet Gateway |
| Private App | 10.0.11.0/24, 10.0.12.0/24 | ap-south-1a, ap-south-1b | Outbound via NAT Gateway |
| Private DB | 10.0.21.0/24, 10.0.22.0/24 | ap-south-1a, ap-south-1b | None |

**Security Groups:**

| Resource | Inbound | Outbound |
|----------|---------|----------|
| ALB | 0.0.0.0/0:80 (prod), 0.0.0.0/0:8080 (test) | ECS tasks :8000 |
| ECS Tasks | ALB SG :8000 | RDS :5432, AWS APIs :443 |
| RDS | ECS SG :5432 | All (stateful responses) |

---

## Traffic Flow

### Normal request (user visiting the app):

```
Browser
  │
  ▼ HTTP :80
ALB (internet-facing, public subnets)
  │
  ▼ Forward to active target group
Blue Target Group  OR  Green Target Group
  │
  ▼ HTTP :8000
ECS Fargate Task (private app subnet)
  │
  ├── Static file? → Serve from /app/frontend/
  │
  └── API call?   → FastAPI handler
                        │
                        ▼ TCP :5432
                    RDS PostgreSQL (private DB subnet)
```

### During a blue/green deployment:

```
Step 1:  New ECS tasks start in replacement task set
         └── Tasks pull image from ECR (via NAT → ECR endpoint)
         └── Tasks fetch DATABASE_URL from SSM Parameter Store
         └── Tasks pass ALB health check on /health

Step 2:  ALB test listener (:8080) → Green target group
         └── Smoke tests can run against port 8080

Step 3:  10% of port 80 traffic → Green (canary)
         90% of port 80 traffic → Blue (original)

Step 4:  Wait 5 minutes — monitor for errors

Step 5:  100% of port 80 traffic → Green
         Blue tasks wait 5 min then terminate
```

---

## Blue/Green Deployment Flow

**Why blue/green?** Zero-downtime deployments with instant rollback capability.

```
                    ┌──────────────┐
                    │     ALB      │
                    │  :80  :8080  │
                    └──────┬───────┘
                           │
              ┌────────────┴────────────┐
              │                         │
    ┌─────────▼─────────┐   ┌───────────▼─────────┐
    │   Blue TG         │   │   Green TG           │
    │  (Original)       │   │  (Replacement)       │
    │  100% traffic     │   │  0% traffic          │
    │  old image        │   │  new image           │
    └───────────────────┘   └─────────────────────┘
              ↕  CodeDeploy swaps these during deploy
```

**Deployment configuration:** `CodeDeployDefault.ECSCanary10Percent5Minutes`

| Step | Action |
|------|--------|
| 1 | New tasks start in replacement task set |
| 2 | Test listener (:8080) routes to replacement |
| 3 | 10% of production traffic shifts to replacement |
| 4 | Wait 5 minutes (canary observation window) |
| 5 | 100% traffic shifts to replacement |
| 6 | Original tasks terminate after 5 min wait |

**Auto-rollback triggers:** `DEPLOYMENT_FAILURE`

---

## Terraform Infrastructure

### Module Structure

```
infra/
├── envs/
│   └── dev/
│       ├── main.tf          # Module wiring
│       ├── variables.tf     # Input variables
│       ├── outputs.tf       # Stack outputs
│       └── backend.tf       # S3 remote state
└── modules/
    ├── vpc/                 # VPC, subnets, NAT GW, route tables
    ├── alb/                 # ALB, target groups, listeners
    ├── ecs/                 # ECS cluster, task definition, service, SG
    ├── rds/                 # RDS PostgreSQL, subnet group, SG, SSM param
    ├── iam/                 # Task execution role, task role, CodeDeploy role
    └── codedeploy/          # CodeDeploy app and deployment group
```

### Remote State

| Setting | Value |
|---------|-------|
| Backend | S3 |
| Bucket | `expense-tracker-tfstate-dev-697502032879-ap-south-1-an` |
| Key | `dev/terraform.tfstate` |
| Workspace | `dev` |
| Encryption | AES-256 (SSE-S3) |

### Key Design Decisions

**ECS service uses `ignore_changes`** on `task_definition` and `load_balancer`:
```hcl
lifecycle {
  ignore_changes = [task_definition, load_balancer, desired_count]
}
```
Terraform creates the service once. CodeDeploy owns task definitions and traffic routing after that. Without this, Terraform would fight CodeDeploy and revert deployments.

**RDS password never in state:** Passed via `TF_VAR_db_password` environment variable on the Atlantis server. Stored in SSM Parameter Store as a SecureString and injected into containers at runtime — never baked into the image or stored in Terraform state.

**Container image placeholder:** Terraform creates the ECS service with a placeholder image (`dummy`). The real image is deployed by CodeDeploy on the first GitHub Actions run after `terraform apply`.

### IAM Roles

| Role | Purpose |
|------|---------|
| `ecs-task-execution-role` | ECS agent — pulls ECR images, fetches SSM secrets, writes CloudWatch logs |
| `ecs-task-role` | Application code — CloudWatch metrics, X-Ray tracing |
| `codedeploy-role` | CodeDeploy — updates ECS service, swaps ALB listener rules |

---

## Atlantis GitOps

Atlantis is a self-hosted GitOps tool that runs `terraform plan` and `terraform apply` in response to GitHub Pull Requests.

**Server:** DigitalOcean droplet at port 4141

**Workflow:**

```
1. Engineer pushes infra changes to a feature branch
         │
         ▼
2. Pull Request opened on GitHub
         │
         ▼
3. Atlantis detects *.tf file changes (via webhook)
   → Runs: terraform workspace select dev
   → Runs: terraform plan
   → Posts plan output as PR comment
         │
         ▼
4. Reviewer reads plan, comments: atlantis apply
         │
         ▼
5. Atlantis runs: terraform apply
   → Posts apply result as PR comment
         │
         ▼
6. PR merged to main
```

**atlantis.yaml:**

```yaml
version: 3
projects:
  - name: expense-tracker-dev
    dir: infra/envs/dev
    workspace: dev
    terraform_version: v1.6.6
    autoplan:
      enabled: true
      when_modified:
        - "**/*.tf"
        - "**/*.tfvars"
        - "atlantis.yaml"
```

**Server environment variables** (set in `/etc/atlantis.env`):

```bash
TF_VAR_db_username=<db_username>
TF_VAR_db_password=<db_password>
TF_VAR_container_image=dummy
AWS_ACCESS_KEY_ID=<key>
AWS_SECRET_ACCESS_KEY=<secret>
```

**Required GitHub webhook events:**
- `push`
- `pull_request`
- `issue_comment` (needed for `atlantis apply` command)

> Set webhook to **"Send me everything"** to ensure all events are delivered.

---

## GitHub Actions Pipelines

### 1. Terraform CI (`ci.yml`)

Triggers on: PRs and pushes to `main` that change files in `infra/`

```
┌─────────────┐    ┌──────────────┐    ┌──────────────┐    ┌────────────────────┐
│   fmt       │    │  validate    │    │  tfsec       │    │ atlantis-plan      │
│             │    │              │    │  security    │    │ (required gate)    │
│ terraform   │    │ terraform    │    │  scan        │    │                    │
│ fmt -check  │    │ validate     │    │  soft_fail   │    │ reminder that      │
│             │    │              │    │              │    │ Atlantis must plan  │
└─────────────┘    └──────────────┘    └──────────────┘    └────────────────────┘
```

| Job | Tool | Purpose |
|-----|------|---------|
| `fmt` | `terraform fmt -check` | Enforce consistent formatting |
| `validate` | `terraform validate` | Check syntax and config validity |
| `security` | `tfsec` | Static security analysis |
| `atlantis-plan-required` | Status check | Gate — Atlantis must plan before merge |

### 2. Build & Deploy (`deploy.yml`)

Triggers on: pushes to `main` that change files in `expense-tracker/` or `.github/workflows/deploy.yml`

```
Checkout
    │
    ▼
Configure AWS credentials
    │
    ▼
Login to ECR
    │
    ▼
Build Docker image
  • context: expense-tracker/
  • tags: <sha>, stable
    │
    ▼
Push to ECR
    │
    ▼
Download current task definition from ECS
    │
    ▼
Inject new image URI into task definition JSON
    │
    ▼
Register new task definition revision
    │
    ▼
Generate appspec.json (Python)
  • fetches subnet/SG IDs from ECS service
  • writes revision.json for CodeDeploy
    │
    ▼
Wait for any in-progress deployment (up to 20 min)
    │
    ▼
Create CodeDeploy deployment
    │
    ▼
Poll deployment status every 30s (up to 30 min)
  • Succeeded → exit 0
  • Failed/Stopped → exit 1
  • Timeout → exit 0 (check console)
```

**GitHub Secrets required:**

| Secret | Description |
|--------|-------------|
| `AWS_ACCESS_KEY_ID` | IAM user access key |
| `AWS_SECRET_ACCESS_KEY` | IAM user secret key |
| `AWS_REGION` | `ap-south-1` |

---

## Security

| Area | Control |
|------|---------|
| Database password | Never in code/state — SSM SecureString, injected at runtime |
| RDS | Not publicly accessible, private DB subnets only |
| ECS tasks | Private subnets, no public IP, outbound via NAT |
| Container image | ECR private registry, IAM-authenticated pull |
| IAM | Least privilege — task role only has CloudWatch + X-Ray |
| ALB | Drops invalid HTTP headers |
| Storage encryption | RDS encrypted at rest (gp3), SSM SecureString (KMS) |

---

## How to Deploy

### First-time infrastructure setup

```bash
# 1. Create S3 state bucket manually
aws s3api create-bucket \
  --bucket expense-tracker-tfstate-dev-<account-id>-ap-south-1-an \
  --region ap-south-1 \
  --create-bucket-configuration LocationConstraint=ap-south-1

# 2. Create ECR repository manually
aws ecr create-repository \
  --repository-name expense-tracker \
  --region ap-south-1

# 3. Open a PR with infra changes → Atlantis auto-plans
# 4. Comment 'atlantis apply' on the PR
# 5. Merge the PR
```

### Deploy application changes

```bash
# Push any change to expense-tracker/ on main branch
git push origin main
# GitHub Actions builds image, pushes to ECR, creates CodeDeploy deployment
```

### Tear down everything

```bash
# On the Atlantis droplet:
cd /home/atlantis/.atlantis/repos/<org>/<repo>/<pr>/dev/infra/envs/dev
source /etc/atlantis.env
terraform workspace select dev
terraform destroy -auto-approve

# Then manually:
aws ecr delete-repository --repository-name expense-tracker --region ap-south-1 --force
aws s3 rm s3://<state-bucket> --recursive
aws s3api delete-bucket --bucket <state-bucket> --region ap-south-1
```

---

## Resource Summary

| Resource | Name | Count |
|----------|------|-------|
| VPC | expense-tracker-dev-vpc | 1 |
| Public Subnets | expense-tracker-dev-public-* | 2 |
| Private App Subnets | expense-tracker-dev-private-app-* | 2 |
| Private DB Subnets | expense-tracker-dev-private-db-* | 2 |
| NAT Gateways | expense-tracker-dev-nat-* | 2 |
| ALB | expense-tracker-dev-alb | 1 |
| Target Groups | expense-tracker-dev-tg-blue/green | 2 |
| ECS Cluster | expense-tracker-dev-cluster | 1 |
| ECS Service | expense-tracker-dev-service | 1 |
| RDS Instance | expense-tracker-dev-postgres | 1 |
| CodeDeploy App | expense-tracker-dev-app | 1 |
| IAM Roles | task-execution, task, codedeploy | 3 |
| SSM Parameter | /dev/expense-tracker-dev/DATABASE_URL | 1 |
| CloudWatch Log Group | /ecs/expense-tracker-dev/app | 1 |
