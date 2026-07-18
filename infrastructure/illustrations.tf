# The station's 412 bird illustrations (~225 MB) live here, not in the repo or the app
# image. The engine serves /birds/<slug>.png from the local profile when present (dev, and
# the Pi after it syncs) and otherwise redirects to ILLUSTRATIONS_BASE_URL — this bucket,
# fronted by CloudFront. Private bucket; only this distribution (via OAC) can read it.
# Publish/refresh the art with `bin/sync-illustrations push`.

resource "aws_s3_bucket" "illustrations" {
  bucket = "${var.station_name}-illustrations"
}

resource "aws_s3_bucket_public_access_block" "illustrations" {
  bucket                  = aws_s3_bucket.illustrations.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Origin Access Control — CloudFront signs its origin requests (SigV4) so the bucket can
# stay fully private; nothing is world-readable directly on S3.
resource "aws_cloudfront_origin_access_control" "illustrations" {
  name                              = "${var.station_name}-illustrations"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# Immutable, content-addressed-ish art: cache hard at the edge. Managed-CachingOptimized
# gives long TTLs and gzip/brotli; a new slug is a new object, so no invalidation dance.
data "aws_cloudfront_cache_policy" "optimized" {
  name = "Managed-CachingOptimized"
}

# A clean vanity host for the art, so a URL just resolves — assets.<domain>/<slug>.webp —
# rather than the opaque *.cloudfront.net name. Mirrors the app cert in cdn.tf: an ACM cert
# in us-east-1 (CloudFront's required region), DNS-validated against the same Route53 zone.
# The zone is already delegated (the app cert validates there too), so this validates in ~1-2m.
locals {
  illustrations_domain = "assets.${var.domain_name}"
}

resource "aws_acm_certificate" "illustrations" {
  provider          = aws.us_east_1
  domain_name       = local.illustrations_domain
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "illustrations_cert_validation" {
  for_each = {
    for o in aws_acm_certificate.illustrations.domain_validation_options : o.domain_name => o
  }
  zone_id         = aws_route53_zone.main.zone_id
  name            = each.value.resource_record_name
  type            = each.value.resource_record_type
  records         = [each.value.resource_record_value]
  ttl             = 60
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "illustrations" {
  provider                = aws.us_east_1
  certificate_arn         = aws_acm_certificate.illustrations.arn
  validation_record_fqdns = [for r in aws_route53_record.illustrations_cert_validation : r.fqdn]

  # The app cert's 10m fail-fast guards against an undelegated domain — but this domain IS
  # delegated (the apex resolves through this zone), so failing fast here only aborts a
  # validation that may still be in flight. Give ACM the AWS default instead. NOTE: a
  # correctly-published CNAME validates in 1-5m; if this still times out, the record is
  # wrong or missing, not slow — check it rather than raising this again.
  timeouts {
    create = "45m"
  }
}

resource "aws_cloudfront_distribution" "illustrations" {
  enabled         = true
  is_ipv6_enabled = true
  aliases         = [local.illustrations_domain]
  price_class     = "PriceClass_100" # NA + Europe — cheapest, matches the app distribution
  comment         = "${var.station_name} bird illustrations"

  origin {
    domain_name              = aws_s3_bucket.illustrations.bucket_regional_domain_name
    origin_id                = "illustrations-s3"
    origin_access_control_id = aws_cloudfront_origin_access_control.illustrations.id
  }

  default_cache_behavior {
    target_origin_id       = "illustrations-s3"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true
    cache_policy_id        = data.aws_cloudfront_cache_policy.optimized.id
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate_validation.illustrations.certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }
}

# Point assets.<domain> at the illustrations distribution (A + AAAA alias, like the apex).
resource "aws_route53_record" "illustrations" {
  for_each        = toset(["A", "AAAA"])
  zone_id         = aws_route53_zone.main.zone_id
  name            = local.illustrations_domain
  type            = each.value
  allow_overwrite = true
  alias {
    name                   = aws_cloudfront_distribution.illustrations.domain_name
    zone_id                = aws_cloudfront_distribution.illustrations.hosted_zone_id
    evaluate_target_health = false
  }
}

# Let only this distribution read the bucket (OAC principal + SourceArn condition).
data "aws_iam_policy_document" "illustrations_oac" {
  statement {
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.illustrations.arn}/*"]
    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.illustrations.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "illustrations" {
  bucket = aws_s3_bucket.illustrations.id
  policy = data.aws_iam_policy_document.illustrations_oac.json
}
