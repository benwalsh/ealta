# NB: managed with OpenTofu (the `tofu` CLI), not Terraform. The `terraform {}` block name
# and .tf files are unchanged; only the command differs (tofu init/plan/apply).
terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # >= 6.34 required for aws_ecs_express_gateway_service (ECS Express Mode),
      # which the express-service module wraps.
      version = "~> 6.34"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # Remote state in S3, locked via a DynamoDB table (works on every OpenTofu version).
  # Backend settings can't reference variables, so this is a PARTIAL configuration:
  # per-station values live in infrastructure/backend.hcl (copy backend.hcl.example in
  # your fork, gitignored) and are supplied at init:
  #     tofu init -backend-config=backend.hcl
  # Bootstrap the bucket + lock table once (see infrastructure/README.md); moving an
  # existing local state up is `tofu init -backend-config=backend.hcl -migrate-state`.
  # (On OpenTofu ≥ 1.10 you can drop dynamodb_table for `use_lockfile = true` instead.)
  backend "s3" {
    key     = "cloud/terraform.tfstate"
    encrypt = true
  }
}

provider "aws" {
  region = var.aws_region
  default_tags {
    tags = {
      Project = "ealta-${var.station_name}"
      Managed = "terraform"
    }
  }
}

# CloudFront + its ACM certificate must live in us-east-1, regardless of where
# the app runs.
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
  default_tags {
    tags = {
      Project = "ealta-${var.station_name}"
      Managed = "terraform"
    }
  }
}
