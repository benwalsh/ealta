# Route53 zone for the domain. If you registered the domain elsewhere, point
# the registrar's nameservers at the ones this outputs (see outputs.tf).
resource "aws_route53_zone" "main" {
  name = var.domain_name
}

# TLS cert for CloudFront — MUST be in us-east-1. DNS-validated via Route53.
resource "aws_acm_certificate" "cf" {
  provider                  = aws.us_east_1
  domain_name               = var.domain_name
  subject_alternative_names = ["www.${var.domain_name}"]
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "cert_validation" {
  for_each = {
    for o in aws_acm_certificate.cf.domain_validation_options : o.domain_name => o
  }
  zone_id         = aws_route53_zone.main.zone_id
  name            = each.value.resource_record_name
  type            = each.value.resource_record_type
  records         = [each.value.resource_record_value]
  ttl             = 60
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "cf" {
  provider                = aws.us_east_1
  certificate_arn         = aws_acm_certificate.cf.arn
  validation_record_fqdns = [for r in aws_route53_record.cert_validation : r.fqdn]

  # Fail fast rather than hanging the default 45m. Validation completes in ~1-2m
  # ONCE the domain is delegated to this zone's nameservers (see the zone comment
  # above). If this times out, delegation hasn't propagated yet — check with
  # `dig +short NS <your domain>` and re-apply.
  timeouts {
    create = "10m"
  }
}

# Cache key: path + the only query params the app reads; cookies ignored so
# anonymous public pages cache well. (Auth/session tuning is a later refinement —
# the Pi's push goes straight to App Runner, not through CloudFront.)
resource "aws_cloudfront_cache_policy" "app" {
  name        = "${var.station_name}-app"
  default_ttl = 300
  min_ttl     = 0
  max_ttl     = 3600

  parameters_in_cache_key_and_forwarded_to_origin {
    cookies_config {
      cookie_behavior = "none"
    }
    headers_config {
      header_behavior = "none"
    }
    query_strings_config {
      query_string_behavior = "whitelist"
      query_strings {
        items = ["h", "sort", "scope", "tab"]
      }
    }
    enable_accept_encoding_gzip   = true
    enable_accept_encoding_brotli = true
  }
}

data "aws_cloudfront_origin_request_policy" "all_viewer_except_host" {
  name = "Managed-AllViewerExceptHostHeader"
}

data "aws_cloudfront_cache_policy" "disabled" {
  name = "Managed-CachingDisabled"
}

resource "aws_cloudfront_distribution" "main" {
  enabled         = true
  is_ipv6_enabled = true
  aliases         = [var.domain_name, "www.${var.domain_name}"]
  price_class     = "PriceClass_100" # NA + Europe — cheapest
  comment         = "${var.domain_name} public mirror"

  origin {
    domain_name = local.ecs_origin_host
    origin_id   = "ecs"
    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
    # The Host header must stay the origin's (the shared ALB routes on it), so Rails
    # would otherwise see itself as *.on.aws — and reject sign-in POSTs with a 422: the
    # browser's Origin (the public domain) fails the CSRF same-origin check against that
    # base_url. Hand Rails its public identity the standard proxy way; cloud.rb allows
    # the host, and Rack derives base_url from X-Forwarded-Host.
    custom_header {
      name  = "X-Forwarded-Host"
      value = var.domain_name
    }
  }

  default_cache_behavior {
    target_origin_id         = "ecs"
    viewer_protocol_policy   = "redirect-to-https"
    allowed_methods          = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods           = ["GET", "HEAD"]
    compress                 = true
    cache_policy_id          = aws_cloudfront_cache_policy.app.id
    origin_request_policy_id = data.aws_cloudfront_origin_request_policy.all_viewer_except_host.id
  }

  # Auth + authenticated pages must never be cached and must carry cookies both ways:
  # the OAuth state and the login session live in a cookie, and a cached signed-in page
  # would leak it to the next visitor. Same origin-request policy as the default (forwards
  # cookies/query/headers but NOT Host, so the shared ALB still routes on the origin host)
  # — only the cache policy differs: CachingDisabled instead of our app cache.
  dynamic "ordered_cache_behavior" {
    for_each = toset(["/auth/*", "/logout", "/account", "/admin", "/jobs", "/jobs/*", "/subscriptions/*", "/favourites"])
    content {
      path_pattern             = ordered_cache_behavior.value
      target_origin_id         = "ecs"
      viewer_protocol_policy   = "redirect-to-https"
      allowed_methods          = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
      cached_methods           = ["GET", "HEAD"]
      compress                 = true
      cache_policy_id          = data.aws_cloudfront_cache_policy.disabled.id
      origin_request_policy_id = data.aws_cloudfront_origin_request_policy.all_viewer_except_host.id
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate_validation.cf.certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }
}

# Point the domain (apex + www) at CloudFront.
resource "aws_route53_record" "apex" {
  for_each = toset(["A", "AAAA"])
  zone_id  = aws_route53_zone.main.zone_id
  name     = var.domain_name
  type     = each.value
  alias {
    name                   = aws_cloudfront_distribution.main.domain_name
    zone_id                = aws_cloudfront_distribution.main.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "www" {
  for_each = toset(["A", "AAAA"])
  zone_id  = aws_route53_zone.main.zone_id
  name     = "www.${var.domain_name}"
  type     = each.value
  alias {
    name                   = aws_cloudfront_distribution.main.domain_name
    zone_id                = aws_cloudfront_distribution.main.hosted_zone_id
    evaluate_target_health = false
  }
}
