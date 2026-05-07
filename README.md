# Fargate Blue/Green Deployment Platform

A production-grade expense tracker application deployed on **AWS ECS Fargate** using **CodeDeploy blue/green** deployments, **Terraform** infrastructure-as-code, **Atlantis** GitOps, and **GitHub Actions** CI/CD pipelines.

---

## Table of Contents

- [Tech Stack](#tech-stack)
- [Application Overview](#application-overview)
- [AWS Architecture — Full Picture](#aws-architecture--full-picture)
- [AWS Services Explained](#aws-services-explained)
- [Network Design — Deep Dive](#network-design--deep-dive)
- [Traffic Flow](#traffic-flow)
- [Blue/Green + Canary Deployment](#bluegreen--canary-deployment)
- [Terraform — Deep Dive](#terraform--deep-dive)
- [Atlantis GitOps — Deep Dive](#atlantis-gitops--deep-dive)
- [GitHub Actions Pipelines](#github-actions-pipelines)
- [Security Model](#security-model)
- [Step-by-Step Setup Guide](#step-by-step-setup-guide)
- [Day-to-Day Operations](#day-to-day-operations)
- [Resource Summary](#resource-summary)

---

## Tech Stack

| Category | Technology |
|----------|-----------|
| **Application** | Python 3.12, FastAPI, Uvicorn |
| **Frontend** | HTML5, CSS3, JavaScript (vanilla) |
| **Database** | PostgreSQL 16.6 |
| **Container** | Docker (`python:3.12-slim`) |
| **Container Orchestration** | AWS ECS Fargate |
| **Container Registry** | AWS ECR |
| **Load Balancer** | AWS ALB (Application Load Balancer) |
| **Deployment** | AWS CodeDeploy (Blue/Green) |
| **Infrastructure as Code** | Terraform 1.6.6 |
| **GitOps / IaC Automation** | Atlantis (self-hosted) |
| **CI/CD** | GitHub Actions |
| **Secrets Management** | AWS SSM Parameter Store |
| **Logging** | AWS CloudWatch Logs |
| **Cloud** | AWS ap-south-1 (Mumbai) |

---

## Application Overview

**Expense Tracker** — a personal finance app where users track daily expenses by category.

```
┌─────────────────────────────────────────────────┐
│                 Browser                         │
│  index.html + css/style.css + js/app.js         │
│  Makes API calls to /api/* using fetch()        │
└────────────────────┬────────────────────────────┘
                     │ HTTP requests
                     ▼
┌─────────────────────────────────────────────────┐
│              FastAPI Backend                    │
│                                                 │
│  /api/categories/   ──► CRUD for categories    │
│  /api/expenses/     ──► CRUD for expenses      │
│  /api/expenses/summary ► spending totals       │
│  /health            ──► ALB health check       │
│  /                  ──► serves frontend HTML   │
└────────────────────┬────────────────────────────┘
                     │ SQLAlchemy ORM
                     ▼
┌─────────────────────────────────────────────────┐
│         PostgreSQL 16.6 (AWS RDS)               │
│  Tables: categories, expenses                   │
│  Seeded on startup: 8 default categories        │
└─────────────────────────────────────────────────┘
```

**API Endpoints:**

| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/categories/` | List all categories |
| POST | `/api/categories/` | Create a category |
| GET | `/api/expenses/` | List expenses (filterable by date/category) |
| POST | `/api/expenses/` | Create an expense |
| PUT | `/api/expenses/{id}` | Update an expense |
| DELETE | `/api/expenses/{id}` | Delete an expense |
| GET | `/api/expenses/summary` | Spending summary by category |
| GET | `/health` | Health check (returns `{"status":"ok"}`) |
| GET | `/` | Serves frontend `index.html` |

---

## AWS Architecture — Full Picture

```
                          ┌──────────────────────────────────────────────────────────────────────┐
                          │                         AWS  ap-south-1 (Mumbai)                      │
                          │                                                                       │
                          │  ┌────────────────────────────────────────────────────────────────┐  │
  ┌─────────┐  HTTP :80   │  │                    VPC   10.0.0.0/16                           │  │
  │ Browser │─────────────┼──►                                                                │  │
  └─────────┘  HTTP :8080 │  │  ┌───────────────────────────────────────────────────────┐    │  │
  (test only)             │  │  │              PUBLIC SUBNETS                            │    │  │
                          │  │  │  ap-south-1a: 10.0.1.0/24   ap-south-1b: 10.0.2.0/24 │    │  │
                          │  │  │                                                        │    │  │
                          │  │  │  ┌─────────────────────────────────────────────────┐  │    │  │
                          │  │  │  │          Application Load Balancer              │  │    │  │
                          │  │  │  │  Listener :80  ──► Blue or Green Target Group  │  │    │  │
                          │  │  │  │  Listener :8080 ──► Test Target Group          │  │    │  │
                          │  │  │  └───────────────────┬─────────────────────────────┘  │    │  │
                          │  │  │                      │                                │    │  │
                          │  │  │  ┌───────────────────┴──────────────────┐             │    │  │
                          │  │  │  │  NAT GW (ap-south-1a)               │             │    │  │
                          │  │  │  │  NAT GW (ap-south-1b)  ◄── ECS tasks│             │    │  │
                          │  │  │  │  use these to reach ECR/SSM/CW      │             │    │  │
                          │  │  │  └───────────────────────────────────  ─┘             │    │  │
                          │  │  └───────────────────────────────────────────────────────┘    │  │
                          │  │                          │                                    │  │
                          │  │  ┌───────────────────────▼───────────────────────────────┐    │  │
                          │  │  │              PRIVATE APP SUBNETS                      │    │  │
                          │  │  │  ap-south-1a: 10.0.11.0/24  ap-south-1b: 10.0.12.0/24│    │  │
                          │  │  │                                                        │    │  │
                          │  │  │  ┌──────────────────────┐  ┌──────────────────────┐   │    │  │
                          │  │  │  │   ECS Fargate Task   │  │   ECS Fargate Task   │   │    │  │
                          │  │  │  │  (Blue Task Set)     │  │  (Green Task Set)    │   │    │  │
                          │  │  │  │  FastAPI :8000       │  │  FastAPI :8000       │   │    │  │
                          │  │  │  │  desired_count: 2    │  │  desired_count: 2    │   │    │  │
                          │  │  │  │  512 CPU / 1024 MB   │  │  512 CPU / 1024 MB   │   │    │  │
                          │  │  │  └──────────┬───────────┘  └──────────┬───────────┘   │    │  │
                          │  │  └─────────────┼──────────────────────── ┼───────────────┘    │  │
                          │  │                │                          │                    │  │
                          │  │  ┌─────────────▼──────────────────────── ▼───────────────┐    │  │
                          │  │  │              PRIVATE DB SUBNETS                       │    │  │
                          │  │  │  ap-south-1a: 10.0.21.0/24  ap-south-1b: 10.0.22.0/24│    │  │
                          │  │  │                                                        │    │  │
                          │  │  │  ┌──────────────────────────────────────────────────┐ │    │  │
                          │  │  │  │        RDS PostgreSQL 16.6  (db.t3.micro)        │ │    │  │
                          │  │  │  │        port 5432  •  encrypted gp3 storage       │ │    │  │
                          │  │  │  │        NOT publicly accessible                   │ │    │  │
                          │  │  │  └──────────────────────────────────────────────────┘ │    │  │
                          │  │  └───────────────────────────────────────────────────────┘    │  │
                          │  └────────────────────────────────────────────────────────────────┘  │
                          │                                                                       │
                          │  AWS Managed Services (region-wide, no VPC placement)                │
                          │  ┌─────────────┐  ┌─────────────┐  ┌────────────┐  ┌─────────────┐  │
                          │  │    ECR      │  │ CodeDeploy  │  │    SSM     │  │ CloudWatch  │  │
                          │  │  Docker     │  │ Blue/Green  │  │  Secrets   │  │   Logs      │  │
                          │  │  Registry   │  │ Orchestrate │  │  Store     │  │  /ecs/..    │  │
                          │  └─────────────┘  └─────────────┘  └────────────┘  └─────────────┘  │
                          └──────────────────────────────────────────────────────────────────────┘

  Outside AWS:
  ┌───────────────────────────────────────────────┐
  │   DigitalOcean Droplet  168.144.88.87         │
  │   Atlantis server  :4141                      │
  │   Receives GitHub webhooks → runs tf plan/apply│
  └───────────────────────────────────────────────┘
```

---

## AWS Services Explained

### VPC (Virtual Private Cloud)
Your own private network inside AWS. All resources live inside it. CIDR: `10.0.0.0/16` = 65,536 IP addresses.

### Subnets
Segments of the VPC, each in a specific Availability Zone:
- **Public subnets** — have a route to the Internet Gateway. ALB and NAT Gateways live here.
- **Private app subnets** — no direct internet. ECS tasks live here. Outbound internet goes via NAT Gateway (to pull ECR images, reach SSM, etc.)
- **Private DB subnets** — completely isolated. RDS lives here. No route to internet at all.

### Internet Gateway (IGW)
The door between your VPC and the public internet. Only resources in public subnets with public IPs can use it directly.

### NAT Gateway
Lets private subnet resources make **outbound** internet connections (e.g. ECS tasks pulling Docker images from ECR) without exposing them to inbound traffic. One per AZ for high availability.

### ALB (Application Load Balancer)
Sits in public subnets. Receives HTTP traffic and routes it to healthy ECS tasks. Has two listeners:
- **Port 80** — production traffic → active target group
- **Port 8080** — test traffic → CodeDeploy uses this during deployment to verify the new version before going live

### Target Groups (Blue & Green)
Logical groups of ECS task IP addresses. The ALB forwards traffic to registered, healthy targets. During a deployment CodeDeploy switches the ALB listener from the blue TG to the green TG.

### ECS Fargate
Runs Docker containers without managing EC2 servers. AWS handles the underlying compute. Each task = one running container instance. We run `desired_count = 2` tasks spread across two AZs.

### ECR (Elastic Container Registry)
Private Docker image registry. GitHub Actions pushes images here tagged with the git commit SHA. ECS pulls from here at task startup.

### RDS PostgreSQL
Managed relational database. Runs in private DB subnets with no internet access. Only ECS tasks (via security group rule) can connect on port 5432.

### SSM Parameter Store
Secure secret storage. The database connection string (`DATABASE_URL`) is stored as a `SecureString` (KMS-encrypted). ECS task execution role has IAM permission to read it. The value is injected into the container as an environment variable at startup — never stored in the image or task definition plaintext.

### CodeDeploy
Orchestrates the blue/green swap. Creates a replacement task set, shifts traffic gradually (canary), waits, then completes or rolls back.

### CloudWatch Logs
All container stdout/stderr goes to log group `/ecs/expense-tracker-dev/app`. Each task stream is prefixed with `app/`.

---

## Network Design — Deep Dive

### Subnet Layout

```
VPC: 10.0.0.0/16
│
├── Public (internet-facing)
│   ├── 10.0.1.0/24  →  ap-south-1a  (ALB, NAT GW)
│   └── 10.0.2.0/24  →  ap-south-1b  (ALB, NAT GW)
│
├── Private App (ECS tasks)
│   ├── 10.0.11.0/24 →  ap-south-1a  (ECS Fargate tasks)
│   └── 10.0.12.0/24 →  ap-south-1b  (ECS Fargate tasks)
│
└── Private DB (RDS)
    ├── 10.0.21.0/24 →  ap-south-1a  (RDS primary/standby)
    └── 10.0.22.0/24 →  ap-south-1b  (RDS primary/standby)
```

### Route Tables

| Route Table | Attached To | Destination | Target |
|-------------|-------------|-------------|--------|
| `rt-public` | Public subnets | 0.0.0.0/0 | Internet Gateway |
| `rt-private-app-1` | Private app ap-south-1a | 0.0.0.0/0 | NAT GW ap-south-1a |
| `rt-private-app-2` | Private app ap-south-1b | 0.0.0.0/0 | NAT GW ap-south-1b |
| `rt-private-db` | Private DB subnets | — | No internet route |

### Security Groups (Firewall Rules)

**ALB Security Group:**
```
Inbound:   0.0.0.0/0  :80    (production HTTP)
           0.0.0.0/0  :8080  (CodeDeploy test listener)
Outbound:  0.0.0.0/0  :8000  (to ECS container port)
```

**ECS Tasks Security Group:**
```
Inbound:   ALB-SG     :8000  (only from ALB, not from internet)
Outbound:  10.0.21.0/24 :5432  (to RDS, private DB subnets)
           10.0.22.0/24 :5432
           0.0.0.0/0    :443   (to ECR, SSM, CloudWatch via NAT)
```

**RDS Security Group:**
```
Inbound:   ECS-SG     :5432  (only from ECS tasks)
Outbound:  0.0.0.0/0  all    (stateful — response traffic)
```

---

## Traffic Flow

### Normal User Request

```
User's browser
    │
    │  GET http://expense-tracker-dev-alb-xxx.ap-south-1.elb.amazonaws.com/
    ▼
ALB  (public subnet, internet-facing)
    │  Listener :80 → forward to active target group
    ▼
Blue Target Group  (or Green after deployment)
    │  Routes to a healthy ECS task IP (e.g. 10.0.11.45:8000)
    ▼
ECS Fargate Task  (private app subnet 10.0.11.x or 10.0.12.x)
    │
    ├─── Request for /  or /css/  or /js/
    │    └── FastAPI StaticFiles serves frontend files from /app/frontend/
    │
    └─── Request for /api/expenses/
         └── FastAPI router handles it
                  │
                  │  SQLAlchemy query  TCP :5432
                  ▼
             RDS PostgreSQL  (private DB subnet 10.0.21.x)
                  │
                  ▼
             Returns data → JSON response → browser
```

### ECS Task Startup (what happens when a container starts)

```
ECS agent (AWS managed)
    │
    ├── 1. Pull Docker image from ECR
    │        ECS task → NAT GW → internet → ECR API (HTTPS :443)
    │        Authenticate with IAM (task execution role)
    │
    ├── 2. Fetch secrets from SSM Parameter Store
    │        Reads: /dev/expense-tracker-dev/DATABASE_URL
    │        Decrypts with KMS using task execution role
    │        Injects as env var DATABASE_URL into container
    │
    ├── 3. Start container
    │        CMD: uvicorn app.main:app --host 0.0.0.0 --port 8000
    │        FastAPI lifespan: create DB tables + seed categories
    │
    └── 4. Health check
             curl -f http://localhost:8000/health
             ALB polls /health every 30s
             Task registered as healthy → receives traffic
```

---

## Blue/Green + Canary Deployment

### Concept

```
BEFORE DEPLOYMENT:
                    ┌────────────────────────────────┐
                    │            ALB                 │
                    │  :80 listener                  │
                    └──────────────┬─────────────────┘
                                   │ 100%
                    ┌──────────────▼─────────────────┐
                    │    Blue Target Group            │
                    │    2 ECS tasks  (v1 image)      │
                    └────────────────────────────────┘
                    Green Target Group (idle, 0 tasks)


DURING DEPLOYMENT — Step 1 (new tasks start):
                    ┌────────────────────────────────┐
                    │            ALB                 │
                    │  :80  ──► Blue  (100%)          │
                    │  :8080 ──► Green (test)         │
                    └────────────────────────────────┘
                    Blue TG:  2 tasks (v1)  ← still live
                    Green TG: 2 tasks (v2)  ← warming up


DURING DEPLOYMENT — Step 3 (10% canary):
                    ┌────────────────────────────────┐
                    │            ALB                 │
                    │  :80 ──► 90% Blue  + 10% Green │
                    └────────────────────────────────┘
                    Wait 5 min — if errors → auto rollback


AFTER DEPLOYMENT — Step 5 (full shift):
                    ┌────────────────────────────────┐
                    │            ALB                 │
                    │  :80 listener                  │
                    └──────────────┬─────────────────┘
                                   │ 100%
                    ┌──────────────▼─────────────────┐
                    │    Green Target Group           │
                    │    2 ECS tasks  (v2 image)      │
                    └────────────────────────────────┘
                    Blue tasks: wait 5 min then terminate
```

### Deployment Steps in Detail

| Step | Name | What happens |
|------|------|--------------|
| 1 | Deploying replacement task set | ECS launches 2 new tasks (v2) in green TG. Health checks must pass. |
| 2 | Test traffic route setup | ALB :8080 → green TG. Run smoke tests here. |
| 3 | Rerouting production traffic | 10% of :80 traffic → green. 90% still → blue. |
| 4 | Wait 5 minutes | Observation window. CodeDeploy monitors for failures. |
| 5 | 100% traffic shift | All :80 traffic → green. Blue tasks deregistered. |
| 6 | Terminate original task set | Blue tasks deleted after 5 min termination wait. |

**Configuration:** `CodeDeployDefault.ECSCanary10Percent5Minutes`
**Auto-rollback on:** `DEPLOYMENT_FAILURE`

### Rollback

If any step fails, CodeDeploy automatically:
1. Shifts 100% traffic back to the original (blue) task set
2. Terminates the replacement (green) task set
3. Marks the deployment as `Failed`

Zero downtime — users were already on blue when the rollback happened.

---

## Terraform — Deep Dive

Terraform is the tool that creates and manages all AWS infrastructure. You write the desired state in `.tf` files. Terraform figures out what to create, update, or delete.

### How Terraform Works

```
You write HCL code (.tf files)
    │
    ▼
terraform plan  →  compares desired state (code) with actual state (AWS)
                   shows what will be ADDED / CHANGED / DESTROYED
    │
    ▼
terraform apply →  makes the actual AWS API calls to reach desired state
                   saves the result to state file (S3)
    │
    ▼
State file (S3) →  remembers what Terraform created
                   used for future plans and applies
```

### Project Structure

```
infra/
│
├── envs/                        ← environment-specific configs
│   └── dev/
│       ├── backend.tf           ← where to store state (S3 bucket + key)
│       ├── main.tf              ← calls all modules with dev-specific values
│       ├── variables.tf         ← input variable declarations
│       └── outputs.tf           ← values to print after apply
│
└── modules/                     ← reusable building blocks
    ├── vpc/                     ← networking foundation
    │   ├── main.tf              ← VPC, subnets, IGW, NAT GW, route tables
    │   ├── variables.tf         ← inputs: vpc_cidr, azs, subnet_cidrs...
    │   └── outputs.tf           ← outputs: vpc_id, subnet_ids...
    │
    ├── alb/                     ← load balancer
    │   ├── main.tf              ← ALB, security group, blue/green TGs, listeners
    │   ├── variables.tf
    │   └── outputs.tf           ← outputs: alb_arn, tg_arns, listener_arns...
    │
    ├── ecs/                     ← container platform
    │   ├── main.tf              ← cluster, task definition, service, security group
    │   ├── variables.tf
    │   └── outputs.tf           ← outputs: cluster_name, service_name, sg_id...
    │
    ├── rds/                     ← database
    │   ├── main.tf              ← RDS instance, subnet group, security group, SSM param
    │   ├── variables.tf
    │   └── outputs.tf           ← outputs: endpoint, ssm_arn...
    │
    ├── iam/                     ← permissions
    │   ├── main.tf              ← 3 IAM roles + policies
    │   ├── variables.tf
    │   └── outputs.tf           ← outputs: role ARNs
    │
    └── codedeploy/              ← deployment orchestration
        ├── main.tf              ← CodeDeploy app + deployment group
        └── variables.tf
```

### Module Dependency Graph

```
              vpc
               │
       ┌───────┼────────┐
       │       │        │
      iam     alb      rds
       │       │        │
       └───────┼────────┘
               │
              ecs
               │
          codedeploy
```

`vpc` is created first. `iam` and `rds` depend on VPC outputs. `ecs` needs outputs from `vpc`, `alb`, `iam`, and `rds`. `codedeploy` needs `ecs` and `alb` outputs.

### Remote State (S3 Backend)

```hcl
# infra/envs/dev/backend.tf
backend "s3" {
  bucket  = "expense-tracker-tfstate-dev-697502032879-ap-south-1-an"
  key     = "dev/terraform.tfstate"
  region  = "ap-south-1"
  encrypt = true
}
```

The state file lives in S3. This means:
- Multiple people can run Terraform (Atlantis, you) and share the same state
- State is not lost if your local machine crashes
- State is encrypted at rest

Atlantis uses **workspace `dev`** so the actual state path in S3 is:
`env:/dev/dev/terraform.tfstate`

### Key Design Decisions

**1. CodeDeploy owns the ECS service after first apply**

```hcl
# infra/modules/ecs/main.tf
resource "aws_ecs_service" "app" {
  deployment_controller {
    type = "CODE_DEPLOY"   # ← hand control to CodeDeploy
  }

  lifecycle {
    ignore_changes = [task_definition, load_balancer, desired_count]
    # ↑ Terraform will NOT revert these even if they differ from code
    # CodeDeploy updates task_definition on every deploy
    # CodeDeploy swaps load_balancer between blue/green TGs
  }
}
```

Without `ignore_changes`, every `terraform apply` would reset the ECS service back to the original task definition, undoing CodeDeploy deployments.

**2. Database password never enters Terraform state**

```hcl
# RDS module — password comes from env var TF_VAR_db_password
resource "aws_db_instance" "this" {
  password = var.db_password    # passed at runtime, never hardcoded
}

# SSM stores the full connection URL encrypted
resource "aws_ssm_parameter" "database_url" {
  type  = "SecureString"        # KMS encrypted
  value = "postgresql://${var.db_username}:${var.db_password}@${aws_db_instance.this.endpoint}/${var.db_name}"
}
```

**3. Placeholder image on first apply**

Terraform needs an image URI to create the ECS task definition. The real image doesn't exist yet (built by GitHub Actions later). So we pass `container_image = "dummy"` as a placeholder. CodeDeploy replaces it on the first deployment.

**4. Three-tier subnet isolation**

```hcl
# Public → Internet Gateway (ALB, NAT GW)
# Private App → NAT Gateway (ECS tasks, outbound only)
# Private DB → No internet route (RDS, completely isolated)
```

RDS can only be reached via the ECS security group on port 5432. Not even the NAT gateway can reach it.

### Terraform Workspaces

Workspaces let you have multiple independent states in the same S3 bucket:

```bash
terraform workspace new dev     # creates a new workspace
terraform workspace select dev  # switch to dev workspace
terraform workspace list        # show all workspaces
```

Each workspace gets its own state file: `env:/<workspace>/<key>`

This means the same Terraform code can be used for `dev`, `staging`, and `prod` with separate state files.

---

## Atlantis GitOps — Deep Dive

Atlantis is a self-hosted server that listens for GitHub webhook events and runs Terraform commands automatically.

### Why Atlantis?

Without Atlantis, the workflow is:
```
Engineer runs terraform plan locally → shares output in Slack → someone says "looks good" → engineer runs apply
```

Problems: no audit trail, credentials on laptops, can't enforce code review.

With Atlantis:
```
PR opened → Atlantis runs plan → plan posted on PR → code review → comment "atlantis apply" → Atlantis applies → PR merged
```

Benefits: credentials only on the Atlantis server, full audit trail in GitHub, plan reviewed before apply.

### How Atlantis Works Internally

```
GitHub                          Atlantis Server (DigitalOcean :4141)
  │                                          │
  │  Webhook: pull_request.opened            │
  ├─────────────────────────────────────────►│
  │                                          │  1. Clone repo to
  │                                          │     /home/atlantis/.atlantis/repos/
  │                                          │
  │                                          │  2. Read atlantis.yaml
  │                                          │     find projects matching changed files
  │                                          │
  │                                          │  3. terraform init
  │                                          │     (downloads providers, connects S3 backend)
  │                                          │
  │                                          │  4. terraform workspace select dev
  │                                          │
  │                                          │  5. terraform plan -out=expense-tracker-dev-dev.tfplan
  │                                          │
  │  Post plan output as PR comment          │
  │◄─────────────────────────────────────────┤
  │                                          │
  │  Webhook: issue_comment "atlantis apply" │
  ├─────────────────────────────────────────►│
  │                                          │  6. terraform apply expense-tracker-dev-dev.tfplan
  │                                          │     (uses the saved plan from step 5)
  │                                          │
  │  Post apply result as PR comment         │
  │◄─────────────────────────────────────────┤
```

### atlantis.yaml — Explained

```yaml
version: 3

automerge: false        # Atlantis will NOT auto-merge PR after apply
parallel_plan: true     # Multiple projects can plan simultaneously
parallel_apply: false   # Apply one project at a time (safer)

projects:
  - name: expense-tracker-dev     # human-readable name shown in GitHub checks
    dir: infra/envs/dev           # directory to run terraform in
    workspace: dev                # terraform workspace to use
    terraform_version: v1.6.6     # pin exact terraform version

    autoplan:
      enabled: true               # auto-plan when PR is opened/updated
      when_modified:              # only plan when these files change
        - "**/*.tf"               # any .tf file anywhere in the repo
        - "**/*.tfvars"           # any variable files
        - "atlantis.yaml"         # the atlantis config itself
```

### Atlantis Server Configuration

On the DigitalOcean droplet, Atlantis runs as a systemd service:

```bash
# /etc/atlantis.env
TF_VAR_db_username=expenseadmin       # passed to terraform as variable
TF_VAR_db_password=<password>         # never in git
TF_VAR_container_image=dummy          # placeholder for first apply
AWS_ACCESS_KEY_ID=<key>               # AWS credentials for terraform
AWS_SECRET_ACCESS_KEY=<secret>
ATLANTIS_GH_TOKEN=<github_pat>        # to post PR comments
ATLANTIS_GH_WEBHOOK_SECRET=<secret>   # validates webhook signatures
ATLANTIS_REPO_ALLOWLIST=github.com/DevOps94-lk/*
```

### GitHub Webhook Setup

Atlantis receives events via a GitHub webhook:

```
Repository Settings → Webhooks → Add webhook
  Payload URL:    http://168.144.88.87:4141/events
  Content type:   application/json
  Events:         Send me everything  (or at minimum: push, pull_request, issue_comment)
```

> **Important:** `issue_comment` event is required for `atlantis apply` to work.
> Select **"Send me everything"** to avoid delivery issues with individual event checkboxes.

### Atlantis Commands (PR Comments)

| Comment | What it does |
|---------|-------------|
| `atlantis plan` | Force re-run plan even if no files changed |
| `atlantis apply` | Apply the saved plan |
| `atlantis apply -p expense-tracker-dev` | Apply a specific project by name |
| `atlantis unlock` | Release the project lock |

---

## GitHub Actions Pipelines

### Pipeline 1: Terraform CI (`ci.yml`)

**Triggers:** PRs and pushes to `main` touching `infra/` files

```
Push / PR with infra changes
         │
         ├──────────────────────────────────────────────┐
         │                                              │
         ▼                                              ▼
  ┌─────────────┐                              ┌────────────────┐
  │  fmt check  │                              │   validate     │
  │             │                              │                │
  │ terraform   │                              │ terraform init │
  │ fmt -check  │                              │ (no backend)   │
  │  infra/     │                              │ terraform      │
  │             │                              │ validate       │
  └──────┬──────┘                              └───────┬────────┘
         │                                             │
         └──────────────────┬──────────────────────────┘
                            │
                            ▼
                    ┌───────────────┐
                    │  tfsec scan   │
                    │               │
                    │ security scan │
                    │ of all .tf    │
                    │ files         │
                    │ soft_fail=true│
                    └───────┬───────┘
                            │
                            ▼
                 ┌──────────────────────┐
                 │ atlantis-plan-required│
                 │                      │
                 │  Required status     │
                 │  check — reminds     │
                 │  reviewer that       │
                 │  Atlantis must also  │
                 │  have planned        │
                 └──────────────────────┘
```

All 4 checks must pass before a PR can be merged.

### Pipeline 2: Build & Deploy (`deploy.yml`)

**Triggers:** Pushes to `main` touching `expense-tracker/` or `.github/workflows/deploy.yml`

```
git push origin main
         │
         ▼
┌─────────────────────────────────────────────────────────────────┐
│  Step 1: Checkout code                                          │
└───────────────────────────────┬─────────────────────────────────┘
                                │
┌───────────────────────────────▼─────────────────────────────────┐
│  Step 2: Configure AWS credentials                              │
│  Uses: AWS_ACCESS_KEY_ID + AWS_SECRET_ACCESS_KEY from secrets   │
└───────────────────────────────┬─────────────────────────────────┘
                                │
┌───────────────────────────────▼─────────────────────────────────┐
│  Step 3: Login to ECR                                           │
│  Gets registry URL: 697502032879.dkr.ecr.ap-south-1.amazonaws.com│
└───────────────────────────────┬─────────────────────────────────┘
                                │
┌───────────────────────────────▼─────────────────────────────────┐
│  Step 4: Build Docker image                                     │
│  Context: expense-tracker/ (includes backend/ AND frontend/)    │
│  Tags: <registry>/expense-tracker:<git-sha>                     │
│        <registry>/expense-tracker:stable                        │
└───────────────────────────────┬─────────────────────────────────┘
                                │
┌───────────────────────────────▼─────────────────────────────────┐
│  Step 5: Push image to ECR                                      │
│  Pushes both the SHA-tagged and stable-tagged images            │
└───────────────────────────────┬─────────────────────────────────┘
                                │
┌───────────────────────────────▼─────────────────────────────────┐
│  Step 6: Download current ECS task definition                   │
│  aws ecs describe-task-definition → task-definition.json        │
└───────────────────────────────┬─────────────────────────────────┘
                                │
┌───────────────────────────────▼─────────────────────────────────┐
│  Step 7: Inject new image URI                                   │
│  aws-actions/amazon-ecs-render-task-definition                  │
│  Replaces the old image URI with the new ECR image URI          │
└───────────────────────────────┬─────────────────────────────────┘
                                │
┌───────────────────────────────▼─────────────────────────────────┐
│  Step 8: Register new task definition revision                  │
│  aws ecs register-task-definition → returns new task def ARN    │
└───────────────────────────────┬─────────────────────────────────┘
                                │
┌───────────────────────────────▼─────────────────────────────────┐
│  Step 9: Generate appspec.json (Python script)                  │
│  Fetches ECS service network config (subnets, security groups)  │
│  Builds CodeDeploy revision with new task def ARN               │
└───────────────────────────────┬─────────────────────────────────┘
                                │
┌───────────────────────────────▼─────────────────────────────────┐
│  Step 10: Wait for existing deployment                          │
│  If another CodeDeploy deployment is InProgress, waits up to    │
│  20 minutes for it to finish before creating a new one          │
└───────────────────────────────┬─────────────────────────────────┘
                                │
┌───────────────────────────────▼─────────────────────────────────┐
│  Step 11: Create CodeDeploy deployment                          │
│  aws deploy create-deployment → returns DEPLOYMENT_ID           │
└───────────────────────────────┬─────────────────────────────────┘
                                │
┌───────────────────────────────▼─────────────────────────────────┐
│  Step 12: Wait for deployment (polls every 30s, up to 30 min)  │
│  Succeeded → exit 0  ✅                                         │
│  Failed/Stopped → exit 1  ❌                                    │
│  Timeout → exit 0 (check CodeDeploy console)                    │
└─────────────────────────────────────────────────────────────────┘
```

**GitHub Secrets required:**

| Secret | Value |
|--------|-------|
| `AWS_ACCESS_KEY_ID` | IAM user access key |
| `AWS_SECRET_ACCESS_KEY` | IAM user secret key |
| `AWS_REGION` | `ap-south-1` |

---

## Security Model

### Defence in Depth

```
Layer 1: Network — subnets + security groups
  ECS tasks in private subnets → not reachable from internet directly
  RDS in isolated subnets → only reachable from ECS security group

Layer 2: IAM — least privilege roles
  ECS task role: only CloudWatch + X-Ray
  ECS execution role: only ECR pull + SSM read + CloudWatch write
  CodeDeploy role: only ECS + ALB operations

Layer 3: Secrets — SSM Parameter Store
  DB password: KMS-encrypted SecureString
  Never in code, never in image, never in task definition plaintext

Layer 4: Encryption at rest
  RDS: encrypted gp3 storage
  SSM: KMS encryption
  S3 state bucket: SSE-S3 encryption
```

### IAM Role Breakdown

**ECS Task Execution Role** (used by ECS agent, not your code):
```
AmazonECSTaskExecutionRolePolicy (AWS managed):
  → ecr:GetAuthorizationToken
  → ecr:BatchGetImage
  → logs:CreateLogGroup, logs:PutLogEvents

Custom SSM policy:
  → ssm:GetParameter on /dev/expense-tracker-dev/DATABASE_URL only
  → kms:Decrypt on aws/ssm key
```

**ECS Task Role** (used by your application code):
```
→ cloudwatch:PutMetricData, GetMetricData
→ xray:PutTraceSegments, PutTelemetryRecords
```

**CodeDeploy Role:**
```
AWSCodeDeployRoleForECS (AWS managed):
  → ecs:UpdateService, ecs:CreateTaskSet, ecs:DeleteTaskSet
  → elasticloadbalancing:ModifyListener, ModifyRule
  → iam:PassRole (to pass task roles to ECS)
```

---

## Step-by-Step Setup Guide

### Prerequisites

- AWS account with admin access
- AWS CLI configured (`aws configure`)
- Terraform 1.6.6+ installed
- Docker installed
- GitHub repository created
- DigitalOcean account (for Atlantis server)

---

### Step 1: Create S3 State Bucket

```bash
aws s3api create-bucket \
  --bucket expense-tracker-tfstate-dev-<ACCOUNT_ID>-ap-south-1-an \
  --region ap-south-1 \
  --create-bucket-configuration LocationConstraint=ap-south-1

# Enable versioning (protects against accidental state deletion)
aws s3api put-bucket-versioning \
  --bucket expense-tracker-tfstate-dev-<ACCOUNT_ID>-ap-south-1-an \
  --versioning-configuration Status=Enabled

# Enable encryption
aws s3api put-bucket-encryption \
  --bucket expense-tracker-tfstate-dev-<ACCOUNT_ID>-ap-south-1-an \
  --server-side-encryption-configuration '{
    "Rules": [{"ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "AES256"}}]
  }'
```

---

### Step 2: Create ECR Repository

```bash
aws ecr create-repository \
  --repository-name expense-tracker \
  --region ap-south-1
```

---

### Step 3: Set Up Atlantis Server (DigitalOcean)

**3a. Create a droplet** (Ubuntu 22.04, 2GB RAM minimum)

**3b. Install Terraform and Atlantis:**

```bash
# Install Terraform
wget https://releases.hashicorp.com/terraform/1.6.6/terraform_1.6.6_linux_amd64.zip
unzip terraform_1.6.6_linux_amd64.zip
mv terraform /usr/local/bin/

# Install Atlantis
wget https://github.com/runatlantis/atlantis/releases/download/v0.28.0/atlantis_linux_amd64.zip
unzip atlantis_linux_amd64.zip
mv atlantis /usr/local/bin/
```

**3c. Create Atlantis environment file:**

```bash
cat > /etc/atlantis.env << 'EOF'
ATLANTIS_GH_USER=<your-github-username>
ATLANTIS_GH_TOKEN=<github-personal-access-token>
ATLANTIS_GH_WEBHOOK_SECRET=<random-secret>
ATLANTIS_REPO_ALLOWLIST=github.com/<your-org>/*
ATLANTIS_PORT=4141
AWS_ACCESS_KEY_ID=<aws-key>
AWS_SECRET_ACCESS_KEY=<aws-secret>
AWS_REGION=ap-south-1
TF_VAR_db_username=expenseadmin
TF_VAR_db_password=<strong-password>
TF_VAR_container_image=dummy
EOF
```

**3d. Create systemd service:**

```bash
cat > /etc/systemd/system/atlantis.service << 'EOF'
[Unit]
Description=Atlantis Terraform GitOps Server

[Service]
EnvironmentFile=/etc/atlantis.env
ExecStart=/usr/local/bin/atlantis server
Restart=always
User=atlantis

[Install]
WantedBy=multi-user.target
EOF

systemctl enable atlantis
systemctl start atlantis
```

---

### Step 4: Configure GitHub Webhook

In your repository: **Settings → Webhooks → Add webhook**

```
Payload URL:   http://<droplet-ip>:4141/events
Content type:  application/json
Secret:        <same as ATLANTIS_GH_WEBHOOK_SECRET>
Events:        Send me everything
```

---

### Step 5: Set GitHub Actions Secrets

In your repository: **Settings → Secrets and variables → Actions**

```
AWS_ACCESS_KEY_ID     = <your-aws-key>
AWS_SECRET_ACCESS_KEY = <your-aws-secret>
AWS_REGION            = ap-south-1
```

---

### Step 6: Deploy Infrastructure via Atlantis

```bash
# Create a feature branch with a small tf change
git checkout -b infra/initial-setup
# make a small change to any .tf file
git push origin infra/initial-setup
# Open a Pull Request on GitHub
# Atlantis will auto-post the plan
# Review the plan, then comment on the PR:
#   atlantis apply
# After apply succeeds, merge the PR
```

---

### Step 7: Deploy Application

```bash
# Merge any change to expense-tracker/ into main
git checkout main
git merge infra/initial-setup
git push origin main
# GitHub Actions will:
#   1. Build Docker image
#   2. Push to ECR
#   3. Create CodeDeploy blue/green deployment
#   4. Wait for deployment to succeed (~15 min)
```

---

### Step 8: Access the Application

```bash
# Get ALB DNS name
aws elbv2 describe-load-balancers \
  --region ap-south-1 \
  --query 'LoadBalancers[?contains(LoadBalancerName,`expense-tracker`)].DNSName' \
  --output text
```

Open: `http://<alb-dns-name>`

---

## Day-to-Day Operations

### Deploy a new app version

```bash
# Make your code changes in expense-tracker/
git add .
git commit -m "feat: your feature"
git push origin main
# GitHub Actions deploys automatically
```

### Change infrastructure

```bash
git checkout -b infra/my-change
# edit .tf files
git push origin infra/my-change
# Open PR → Atlantis plans → review → comment 'atlantis apply' → merge
```

### View application logs

```bash
aws logs tail /ecs/expense-tracker-dev/app --follow --region ap-south-1
```

### Force a new deployment (no code change)

```bash
# Bump app version to trigger deploy
sed -i 's/version="1.0.0"/version="1.0.1"/' expense-tracker/backend/app/main.py
git add . && git commit -m "chore: trigger redeploy" && git push origin main
```

### Check deployment status

```bash
aws deploy list-deployments \
  --application-name expense-tracker-dev-app \
  --deployment-group-name expense-tracker-dev-deployment-group \
  --region ap-south-1
```

### Tear down everything

```bash
# Destroy all Terraform-managed resources
terraform workspace select dev
terraform destroy -auto-approve

# Clean up manual resources
aws ecr delete-repository --repository-name expense-tracker --region ap-south-1 --force
aws s3 rm s3://<state-bucket> --recursive
aws s3api delete-bucket --bucket <state-bucket> --region ap-south-1
```

---

## Resource Summary

| # | Resource Type | Name | Module |
|---|--------------|------|--------|
| 1 | VPC | expense-tracker-dev-vpc | vpc |
| 2-3 | Public Subnets | expense-tracker-dev-public-* | vpc |
| 4-5 | Private App Subnets | expense-tracker-dev-private-app-* | vpc |
| 6-7 | Private DB Subnets | expense-tracker-dev-private-db-* | vpc |
| 8 | Internet Gateway | expense-tracker-dev-igw | vpc |
| 9-10 | NAT Gateways | expense-tracker-dev-nat-* | vpc |
| 11-12 | Elastic IPs | expense-tracker-dev-nat-eip-* | vpc |
| 13-16 | Route Tables | rt-public, rt-private-app-*, rt-private-db | vpc |
| 17 | ALB | expense-tracker-dev-alb | alb |
| 18 | ALB Security Group | expense-tracker-dev-alb-sg | alb |
| 19 | Blue Target Group | expense-tracker-dev-tg-blue | alb |
| 20 | Green Target Group | expense-tracker-dev-tg-green | alb |
| 21 | HTTP Listener (:80) | expense-tracker-dev-listener-http | alb |
| 22 | Test Listener (:8080) | expense-tracker-dev-listener-test | alb |
| 23 | ECS Cluster | expense-tracker-dev-cluster | ecs |
| 24 | Task Definition | expense-tracker-dev-app | ecs |
| 25 | ECS Service | expense-tracker-dev-service | ecs |
| 26 | ECS Security Group | expense-tracker-dev-ecs-tasks-sg | ecs |
| 27 | CloudWatch Log Group | /ecs/expense-tracker-dev/app | ecs |
| 28 | RDS Instance | expense-tracker-dev-postgres | rds |
| 29 | RDS Security Group | expense-tracker-dev-rds-sg | rds |
| 30 | DB Subnet Group | expense-tracker-dev-db-subnet-group | rds |
| 31 | SSM Parameter | /dev/expense-tracker-dev/DATABASE_URL | rds |
| 32 | IAM Role (execution) | expense-tracker-dev-ecs-task-execution-role | iam |
| 33 | IAM Role (task) | expense-tracker-dev-ecs-task-role | iam |
| 34 | IAM Role (codedeploy) | expense-tracker-dev-codedeploy-role | iam |
| 35 | IAM Policy (SSM) | expense-tracker-dev-ecs-execution-ssm | iam |
| 36 | IAM Policy (app) | expense-tracker-dev-ecs-task-app-policy | iam |
| 37 | CodeDeploy App | expense-tracker-dev-app | codedeploy |
| 38 | CodeDeploy Group | expense-tracker-dev-deployment-group | codedeploy |

**Total: 38 Terraform-managed resources**

Manual (not in Terraform):
- S3 state bucket
- ECR repository
