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
  count   = 3
  zone_id = aws_route53_zone.main.zone_id
  name    = "${aws_sesv2_email_identity.main.dkim_signing_attributes[0].tokens[count.index]}._domainkey.${var.domain_name}"
  type    = "CNAME"
  ttl     = 600
  records = ["${aws_sesv2_email_identity.main.dkim_signing_attributes[0].tokens[count.index]}.dkim.amazonses.com"]
}

# Custom MAIL FROM (mail.<domain>) so SPF aligns with the From domain.
resource "aws_sesv2_email_identity_mail_from_attributes" "main" {
  email_identity         = aws_sesv2_email_identity.main.email_identity
  mail_from_domain       = "mail.${var.domain_name}"
  behavior_on_mx_failure = "USE_DEFAULT_VALUE"
}

resource "aws_route53_record" "ses_mail_from_mx" {
  zone_id = aws_route53_zone.main.zone_id
  name    = aws_sesv2_email_identity_mail_from_attributes.main.mail_from_domain
  type    = "MX"
  ttl     = 600
  records = ["10 feedback-smtp.${var.aws_region}.amazonses.com"]
}

resource "aws_route53_record" "ses_mail_from_spf" {
  zone_id = aws_route53_zone.main.zone_id
  name    = aws_sesv2_email_identity_mail_from_attributes.main.mail_from_domain
  type    = "TXT"
  ttl     = 600
  records = ["v=spf1 include:amazonses.com ~all"]
}

# Minimal DMARC (monitor-only) so mailbox providers see a policy.
resource "aws_route53_record" "dmarc" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "_dmarc.${var.domain_name}"
  type    = "TXT"
  ttl     = 600
  records = ["v=DMARC1; p=none;"]
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
