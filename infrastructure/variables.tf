# Per-station settings. The three with no default (station_name, domain_name,
# github_repository) MUST be set — put them in infrastructure/terraform.tfvars
# (gitignored; copy terraform.tfvars.example) in your fork.

variable "station_name" {
  description = "Short lowercase name for this station (e.g. yourstation). Prefixes every AWS resource, names the ECR repo/ECS service, and selects stations/<station_name> as the baked-in profile."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,30}$", var.station_name))
    error_message = "station_name must be short lowercase kebab-case (it names S3 buckets and ECS services)."
  }
}

variable "domain_name" {
  description = "Public apex domain served by CloudFront (e.g. yourstation.net)."
  type        = string
}

variable "github_repository" {
  description = "owner/name of the GitHub fork allowed to deploy via OIDC (e.g. benwalsh/yourstation)."
  type        = string
}

variable "aws_region" {
  description = "Primary region for the app + RDS."
  type        = string
  default     = "eu-west-1"
}

variable "image_tag" {
  description = "ECR image tag the service deploys (push the Docker image with this tag)."
  type        = string
  default     = "latest"
}

variable "db_username" {
  description = "RDS MySQL master username."
  type        = string
  default     = "ealta"
}

variable "db_name" {
  description = "Database name inside RDS (the app's DB_NAME)."
  type        = string
  default     = "ealta"
}

variable "db_instance_class" {
  description = "RDS instance class — a small ARM Graviton box; it's a derived mirror, not the source of truth."
  type        = string
  default     = "db.t4g.micro"
}

variable "container_port" {
  description = "Port the Rails/Puma container listens on."
  type        = number
  default     = 3000
}

variable "google_client_id" {
  description = "Google OAuth client ID. Set in infrastructure/terraform.tfvars (gitignored) or TF_VAR_google_client_id."
  type        = string
  sensitive   = true
}

variable "google_client_secret" {
  description = "Google OAuth client secret. Set in infrastructure/terraform.tfvars (gitignored) or TF_VAR_google_client_secret."
  type        = string
  sensitive   = true
}
