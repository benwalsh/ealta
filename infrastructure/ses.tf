# Alert emails via SES (eu-west-1, same region as the app). The domain is verified
# by Easy DKIM; a custom MAIL FROM gives SPF alignment; the template lives here so
# the Rails Notifier just passes data. NB: SES starts in the SANDBOX — it can only
# email *verified* addresses until you request production access (a support ticket,
# a day or two of lead time). See the README.

resource "aws_sesv2_email_identity" "main" {
  email_identity = var.domain_name # Easy DKIM by default
}

# Publish the 3 Easy-DKIM CNAMEs so SES can verify + sign for the domain.
resource "aws_route53_record" "ses_dkim" {
  count           = 3
  allow_overwrite = true
  zone_id         = aws_route53_zone.main.zone_id
  name            = "${aws_sesv2_email_identity.main.dkim_signing_attributes[0].tokens[count.index]}._domainkey.${var.domain_name}"
  type            = "CNAME"
  ttl             = 600
  records         = ["${aws_sesv2_email_identity.main.dkim_signing_attributes[0].tokens[count.index]}.dkim.amazonses.com"]
}

# Custom MAIL FROM (mail.<domain>) so SPF aligns with the From domain.
resource "aws_sesv2_email_identity_mail_from_attributes" "main" {
  email_identity         = aws_sesv2_email_identity.main.email_identity
  mail_from_domain       = "mail.${var.domain_name}"
  behavior_on_mx_failure = "USE_DEFAULT_VALUE"
}

resource "aws_route53_record" "ses_mail_from_mx" {
  zone_id         = aws_route53_zone.main.zone_id
  allow_overwrite = true
  name            = aws_sesv2_email_identity_mail_from_attributes.main.mail_from_domain
  type            = "MX"
  ttl             = 600
  records         = ["10 feedback-smtp.${var.aws_region}.amazonses.com"]
}

resource "aws_route53_record" "ses_mail_from_spf" {
  zone_id         = aws_route53_zone.main.zone_id
  allow_overwrite = true
  name            = aws_sesv2_email_identity_mail_from_attributes.main.mail_from_domain
  type            = "TXT"
  ttl             = 600
  records         = ["v=spf1 include:amazonses.com ~all"]
}

# Minimal DMARC (monitor-only) so mailbox providers see a policy.
resource "aws_route53_record" "dmarc" {
  zone_id         = aws_route53_zone.main.zone_id
  allow_overwrite = true
  name            = "_dmarc.${var.domain_name}"
  type            = "TXT"
  ttl             = 600
  records         = ["v=DMARC1; p=none;"]
}

# --- Bounce & complaint feedback loop -------------------------------------------------
# Every send is stamped with this configuration set; its event destination fans bounce,
# complaint and delivery events to an SNS topic, which POSTs them to the app
# (SesNotificationsController) so it can suppress bad addresses on the first hard bounce
# or complaint and keep our rates under the SES thresholds (5% bounce / 0.1% complaint).
# Without this the only signal would be the aggregate CloudWatch numbers — too coarse to
# act on per-address, and exactly what SES reviewers ask you to handle.
resource "aws_sesv2_configuration_set" "main" {
  configuration_set_name = "${var.station_name}-events"
}

resource "aws_sns_topic" "ses_events" {
  name = "${var.station_name}-ses-events"
}

# Let SES publish to the topic, scoped to this account.
resource "aws_sns_topic_policy" "ses_events" {
  arn = aws_sns_topic.ses_events.arn
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowSESPublish"
      Effect    = "Allow"
      Principal = { Service = "ses.amazonaws.com" }
      Action    = "sns:Publish"
      Resource  = aws_sns_topic.ses_events.arn
      Condition = { StringEquals = { "AWS:SourceAccount" = data.aws_caller_identity.current.account_id } }
    }]
  })
}

resource "aws_sesv2_configuration_set_event_destination" "sns" {
  configuration_set_name = aws_sesv2_configuration_set.main.configuration_set_name
  event_destination_name = "sns-feedback"

  event_destination {
    enabled              = true
    matching_event_types = ["BOUNCE", "COMPLAINT", "DELIVERY"]
    sns_destination {
      topic_arn = aws_sns_topic.ses_events.arn
    }
  }
}

# SNS delivers each event to the app over HTTPS. We point at the ECS ingress endpoint
# directly (valid TLS, allowed host — see cloud.rb), bypassing CloudFront exactly like
# the Pi's /ingest push. The secret token in the path authenticates the callback
# (SES_WEBHOOK_TOKEN) and the app additionally verifies the SNS signature; the app
# confirms the subscription itself by GETting the SubscribeURL SNS sends.
#
# DEPLOY ORDER MATTERS. This can only be created once an app image serving POST
# /webhooks/ses/<token> is live: SNS posts its confirmation to that path immediately, and
# against an older image it 404s, nothing confirms, and `tofu apply` sits until it times
# out. That is a deploy-ordering problem and reads like a Terraform fault, so: ship the app
# carrying ses_notifications_controller (+ SES_WEBHOOK_TOKEN) FIRST, then apply this.
resource "aws_sns_topic_subscription" "ses_events" {
  topic_arn              = aws_sns_topic.ses_events.arn
  protocol               = "https"
  endpoint               = "${module.express_service.ingress_paths[0].endpoint}/webhooks/ses/${random_id.ses_webhook_token.hex}"
  endpoint_auto_confirms = true
}

# No email template lives here. Both the alert and the digest are built as SES *simple*
# content in the Rails Notifier (app/services/notifier.rb) — the HTML/text belong with
# the app, not in Terraform. This file only proves the domain + authorises sending.

# Let the ECS task send mail as this domain (SES v2 SendEmail authorises on the
# "From" identity). Attached to the module-created task role.
resource "aws_iam_role_policy" "task_ses" {
  name = "${var.station_name}-task-ses"
  role = module.express_service.task_iam_role_name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "SendAlertEmail"
      Effect   = "Allow"
      Action   = ["ses:SendEmail"]
      Resource = [aws_sesv2_email_identity.main.arn]
    }]
  })
}
