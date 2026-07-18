# Long-lived, least-privilege credentials for the unattended wall device.
#
# In development the Pi can authenticate with `aws sso login`, but the wall device is a
# headless service that runs for months with nobody present to refresh an SSO session.
# It needs *static* credentials scoped to exactly what it does on its own:
#   - Litestream — replicate/restore its offsite DB backup (the backup bucket below)
#   - Bedrock    — invoke Nova Lite for the daily summary (only if the summary timer is on)
#   - S3 read    — pull the illustration PNGs at provision / refresh time
#
# One IAM user, one access key, no console login, no wider reach. The key goes in the
# Pi's .env (LITESTREAM_ACCESS_KEY_ID/_SECRET and AWS_ACCESS_KEY_ID/_SECRET — see
# .env.example). Stations that back up to Backblaze B2 or another non-AWS store can
# ignore all of this and keep their own provider's keys.

# The offsite backup target for the detection history (Litestream replicates here).
# Private, versioned so a bad replication can't erase good history, and old versions
# expire so it doesn't grow without bound.
resource "aws_s3_bucket" "backup" {
  bucket = "${var.station_name}-backup"
}

resource "aws_s3_bucket_public_access_block" "backup" {
  bucket                  = aws_s3_bucket.backup.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "backup" {
  bucket = aws_s3_bucket.backup.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "backup" {
  bucket = aws_s3_bucket.backup.id
  rule {
    id     = "expire-old-versions"
    status = "Enabled"
    filter {} # all objects
    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
}

# The device's own identity. Programmatic only — there is no console password.
resource "aws_iam_user" "device" {
  name = "${var.station_name}-device"
}

resource "aws_iam_access_key" "device" {
  user = aws_iam_user.device.name
}

data "aws_iam_policy_document" "device" {
  # Litestream reads/writes the replica and lists it to restore.
  statement {
    sid    = "Backup"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket",
    ]
    resources = [
      aws_s3_bucket.backup.arn,
      "${aws_s3_bucket.backup.arn}/*",
    ]
  }

  # bin/sync-illustrations pull fetches the art at provision / refresh time.
  statement {
    sid     = "Illustrations"
    effect  = "Allow"
    actions = ["s3:GetObject", "s3:ListBucket"]
    resources = [
      aws_s3_bucket.illustrations.arn,
      "${aws_s3_bucket.illustrations.arn}/*",
    ]
  }

  # The daily-summary timer narrates DailyFacts via Bedrock. Mirrors the ECS task's
  # Bedrock grant (ecs.tf) — InvokeModel across foundation models + inference profiles.
  statement {
    sid     = "Bedrock"
    effect  = "Allow"
    actions = ["bedrock:InvokeModel", "bedrock:InvokeModelWithResponseStream"]
    resources = [
      "arn:aws:bedrock:*::foundation-model/*",
      "arn:aws:bedrock:${var.aws_region}:${data.aws_caller_identity.current.account_id}:inference-profile/*",
    ]
  }
}

resource "aws_iam_user_policy" "device" {
  name   = "${var.station_name}-device"
  user   = aws_iam_user.device.name
  policy = data.aws_iam_policy_document.device.json
}
