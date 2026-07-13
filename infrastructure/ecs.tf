# The cloud app runs on ECS Express Mode — AWS's successor to App Runner. One module
# gives us a Fargate service, a (shared) ALB, autoscaling, CloudWatch logs, and a
# public *.ecs.<region>.on.aws endpoint. CloudFront still fronts it for the domain
# (Express Mode doesn't do custom domains, and we don't need it to).

# Express Mode needs an existing cluster — it doesn't create one.
resource "aws_ecs_cluster" "main" {
  name = var.station_name
}

# KNOWN WARNING (harmless): the module's own `current_deployment` output reads an
# attribute the AWS provider has deprecated, so every plan prints a deprecation
# warning. Unfixed upstream as of module 7.5.0. Safe to ignore: the removal can only
# land in provider 7.x and versions.tf pins ~> 6.x. When upstream drops that output,
# bump the module version here and the warning goes with it.
module "express_service" {
  source  = "terraform-aws-modules/ecs/aws//modules/express-service"
  version = "~> 7.4"

  name    = var.station_name
  cluster = aws_ecs_cluster.main.name
  region  = var.aws_region

  cpu               = "1024"
  memory            = "2048"
  health_check_path = "/up"

  # Express Mode creates + manages its own log group (/aws/ecs/<name>/<svc-hash>),
  # so the module's default one is dead weight — don't create it.
  create_cloudwatch_log_group = false

  primary_container = {
    image          = "${aws_ecr_repository.app.repository_url}:${var.image_tag}"
    container_port = var.container_port

    environment = [
      { name = "RAILS_ENV", value = "cloud" },
      # The station profile, baked into the image at build time (see
      # .github/workflows/deploy.yml) — this makes the cloud mirror render AS the station
      # (place, Irish names, lore, féilire) rather than the neutral example fallback.
      { name = "STATION_PROFILE", value = "/app/stations/${var.station_name}" },
      # Bird art isn't baked into the image — /birds/<slug>.png redirects here, the
      # illustrations bucket's CloudFront (illustrations.tf). Wired from the distribution so
      # there's no URL to copy by hand.
      { name = "ILLUSTRATIONS_BASE_URL", value = "https://${aws_cloudfront_distribution.illustrations.domain_name}" },
      # Station coordinates — the almanac's location gate (Almanac.build returns nil
      # without these), driving weather (Open-Meteo), the nearest tide station, and the
      # sun/moon lines. On-device these come from .env; the cloud task needs them too or
      # the whole almanac row (weather + tide + sparkline) renders empty. Not secret —
      # just the place — so plain env alongside the other non-credential config.
      { name = "BIRD_LAT", value = "53.35" },
      { name = "BIRD_LON", value = "-9.88" },
      { name = "DB_HOST", value = aws_db_instance.main.address },
      { name = "DB_PORT", value = "3306" },
      { name = "DB_NAME", value = var.db_name },
      { name = "DB_USER", value = var.db_username },
      # Enables the alert Notifier (SES). Sends fail-soft until SES is verified +
      # out of sandbox, so it's safe to set now.
      { name = "ALERTS_FROM", value = "alerts@${var.domain_name}" },
      { name = "SITE_URL", value = "https://${var.domain_name}" },
      # LLM "today" summary (Bedrock Nova Lite, EU inference profile). Defaults match
      # these, but pin them explicitly; refresh runs on ingest via bedrock:InvokeModel.
      { name = "BEDROCK_REGION", value = var.aws_region },
      { name = "BEDROCK_MODEL_ID", value = "eu.amazon.nova-lite-v1:0" },
      # Enrichment sourcing model (Stage 1 Claude, tool-use). Current Sonnet profile
      # (Bedrock retires older ones as "Legacy"); bump when a newer one is enabled.
      { name = "ENRICH_MODEL_ID", value = "eu.anthropic.claude-sonnet-4-5-20250929-v1:0" },
      # Run Solid Queue's supervisor inside this Puma so the once-a-day enrichment +
      # digest sweep (DailyEmailSweep, recurring 06:00) needs no separate worker
      # container. DB-backed against RDS — no Redis. See config/puma.rb + recurring.yml.
      { name = "SOLID_QUEUE_IN_PUMA", value = "true" },
    ]

    # Injected from SSM SecureString at task start — fetched by the EXECUTION role
    # (see execution_ssm_param_arns below), never in plaintext.
    secret = [
      { name = "SECRET_KEY_BASE", value_from = aws_ssm_parameter.secret_key_base.arn },
      { name = "DB_PASSWORD", value_from = aws_ssm_parameter.db_password.arn },
      { name = "CLOUD_INGEST_TOKEN", value_from = aws_ssm_parameter.ingest_token.arn },
      { name = "GOOGLE_CLIENT_ID", value_from = aws_ssm_parameter.google_client_id.arn },
      { name = "GOOGLE_CLIENT_SECRET", value_from = aws_ssm_parameter.google_client_secret.arn },
    ]
  }

  # Run the task in the default VPC with our own SG (defined in rds.tf) so RDS can
  # allow it, and so the ALB (in-VPC) can reach the app port. Not the module's SG —
  # keeping it hand-rolled avoids a module<->RDS dependency cycle.
  create_security_group = false
  network_configuration = {
    subnets         = data.aws_subnets.default.ids
    security_groups = [aws_security_group.ecs_tasks.id]
  }

  # The module does NOT infer secret permissions from the secret blocks; grant the
  # execution role ssm:GetParameters on exactly our three params. (No KMS statement
  # needed — the params use the AWS-managed aws/ssm key, and GetParameters-only
  # already worked for the App Runner instance role.)
  execution_ssm_param_arns = [
    aws_ssm_parameter.secret_key_base.arn,
    aws_ssm_parameter.db_password.arn,
    aws_ssm_parameter.ingest_token.arn,
    aws_ssm_parameter.google_client_id.arn,
    aws_ssm_parameter.google_client_secret.arn,
  ]

  # One warm task, scale to two on CPU — parity with the old App Runner min=1/max=2.
  # NB: Express Mode's own metric enum (AVERAGE_CPU|AVERAGE_MEMORY|REQUEST_COUNT_PER_TARGET),
  # not the classic ECS "ECSServiceAverageCPUUtilization" predefined-metric name.
  scaling_target = {
    min_task_count            = 1
    max_task_count            = 2
    auto_scaling_metric       = "AVERAGE_CPU"
    auto_scaling_target_value = 70
  }
}

# NB: the module's service_url output naively builds the host from the service NAME
# (<station>.ecs...on.aws), but AWS assigns a RANDOM-suffixed ingress endpoint
# (cu-<hash>.ecs...on.aws) — the name-based one doesn't resolve. Use the real PUBLIC
# ingress endpoint, stripped of scheme, for CloudFront's origin.domain_name.
locals {
  ecs_origin_host = replace(module.express_service.ingress_paths[0].endpoint, "https://", "")
}

# Let the ECS task call Bedrock (Converse → InvokeModel) — Nova Lite for the "today"
# summary, and Claude for the enrichment pass. Bedrock no longer requires per-model
# access grants, so this allows InvokeModel across foundation models + inference
# profiles rather than naming one model.
resource "aws_iam_role_policy" "task_bedrock" {
  name = "${var.station_name}-task-bedrock"
  role = module.express_service.task_iam_role_name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "InvokeBedrock"
      Effect = "Allow"
      Action = ["bedrock:InvokeModel", "bedrock:InvokeModelWithResponseStream"]
      Resource = [
        "arn:aws:bedrock:*::foundation-model/*",
        "arn:aws:bedrock:${var.aws_region}:${data.aws_caller_identity.current.account_id}:inference-profile/*"
      ]
    }]
  })
}
