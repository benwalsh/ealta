# Generated secrets, stored as SSM SecureString and injected into App Runner as
# runtime secrets (never in plaintext env or state output, except the ingest
# token which the Pi also needs — see outputs.tf).
resource "random_password" "db" {
  length  = 32
  special = false # keep it URL/CLI-safe
}

resource "random_id" "secret_key_base" {
  byte_length = 64
}

resource "random_id" "ingest_token" {
  byte_length = 24
}

locals {
  ssm_prefix = "/${var.station_name}"
}

resource "aws_ssm_parameter" "db_password" {
  name  = "${local.ssm_prefix}/DB_PASSWORD"
  type  = "SecureString"
  value = random_password.db.result
}

resource "aws_ssm_parameter" "secret_key_base" {
  name  = "${local.ssm_prefix}/SECRET_KEY_BASE"
  type  = "SecureString"
  value = random_id.secret_key_base.hex
}

resource "aws_ssm_parameter" "ingest_token" {
  name  = "${local.ssm_prefix}/CLOUD_INGEST_TOKEN"
  type  = "SecureString"
  value = random_id.ingest_token.hex
}

# Google OAuth — supplied by you (terraform.tfvars / TF_VAR_*), not generated.
resource "aws_ssm_parameter" "google_client_id" {
  name  = "${local.ssm_prefix}/GOOGLE_CLIENT_ID"
  type  = "SecureString"
  value = var.google_client_id
}

resource "aws_ssm_parameter" "google_client_secret" {
  name  = "${local.ssm_prefix}/GOOGLE_CLIENT_SECRET"
  type  = "SecureString"
  value = var.google_client_secret
}
