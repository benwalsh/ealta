output "ecr_repository_url" {
  description = "Push the Docker image here."
  value       = aws_ecr_repository.app.repository_url
}

output "site_url" {
  description = "The public site (once DNS + cert are live)."
  value       = "https://${var.domain_name}"
}

output "cloudfront_domain" {
  description = "CloudFront distribution domain (for testing before DNS cuts over)."
  value       = aws_cloudfront_distribution.main.domain_name
}

output "illustrations_base_url" {
  description = "Base URL for the bird illustrations CDN. Feeds ILLUSTRATIONS_BASE_URL on the ECS task; the Pi's bin/sync-illustrations pulls from the bucket behind it."
  value       = "https://${aws_cloudfront_distribution.illustrations.domain_name}"
}

output "ecs_service_url" {
  description = "The ECS Express Mode endpoint (behind CloudFront in normal use)."
  value       = module.express_service.ingress_paths[0].endpoint
}

output "ingest_url" {
  description = "Set as CLOUD_INGEST_URL on the Pi — push goes direct to the ECS service, bypassing CloudFront."
  value       = "${module.express_service.ingress_paths[0].endpoint}/ingest/detections"
}

output "cloud_ingest_token" {
  description = "Set as CLOUD_INGEST_TOKEN on the Pi (matches the cloud app's token)."
  value       = random_id.ingest_token.hex
  sensitive   = true
}

output "rds_endpoint" {
  description = "RDS host (private; reachable only from the ECS service)."
  value       = aws_db_instance.main.address
}

output "route53_nameservers" {
  description = "Point the domain at these at your registrar."
  value       = aws_route53_zone.main.name_servers
}

output "alerts_from_address" {
  description = "Alert emails send from here. Needs SES domain verification + production access."
  value       = "alerts@${var.domain_name}"
}

output "github_deploy_role_arn" {
  description = "Role the GitHub Actions deploy workflow assumes via OIDC."
  value       = aws_iam_role.github_deploy.arn
}
