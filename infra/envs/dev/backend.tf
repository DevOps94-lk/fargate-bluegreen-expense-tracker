terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Remote state in S3 (no DynamoDB locking).
  # Bucket must exist before running `terraform init`.
  backend "s3" {
    bucket  = "expense-tracker-tfstate-dev-697502032879-ap-south-1-an"
    key     = "dev/terraform.tfstate"
    region  = "ap-south-1"
    encrypt = true
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "expense-tracker"
      Environment = "dev"
      ManagedBy   = "terraform"
      Repo        = "expense-tracker-infra"
    }
  }
}
