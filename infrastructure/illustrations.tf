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

resource "aws_cloudfront_distribution" "illustrations" {
  enabled         = true
  is_ipv6_enabled = true
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

  # No custom domain — the *.cloudfront.net URL is what the engine redirects to, so the
  # default CloudFront cert is all we need (no ACM/us-east-1 cert to manage).
  viewer_certificate {
    cloudfront_default_certificate = true
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
