# The public cloud mirror (App Runner behind CloudFront), on RDS MySQL. It's
# production with a few flips, so inherit production.rb wholesale and override
# only what differs — the Pi is a plain-HTTP LAN appliance that serves its own
# assets; the cloud sits behind TLS-terminating CloudFront and an S3/CDN asset
# host. Keeping this DRY means production tuning stays in one place.
require_relative 'production'

Rails.application.configure do
  # CloudFront terminates TLS and forwards plain HTTP to App Runner; trust it and
  # force HTTPS (the opposite of the Pi, which has no TLS in front).
  config.assume_ssl = true
  config.force_ssl = true

  # CloudFront can't forward the viewer's Host (the shared ALB routes on the origin
  # host), so it adds X-Forwarded-Host = the public domain instead (infrastructure/
  # cdn.tf). Rack derives base_url from that header — which is what makes browser
  # sign-in POSTs pass the CSRF same-origin check (Origin == base_url) instead of
  # 422ing. Host authorization must therefore allow the public host alongside the
  # origin host the ALB health checks arrive on; SITE_URL carries the public domain.
  config.hosts << URI(ENV['SITE_URL']).host if ENV['SITE_URL'].present?
  config.hosts << /.*\.on\.aws/ # the ECS Express origin endpoint (direct hits)
  # Health checks don't carry a real host: the ALB probes /up with the task's private IP
  # as Host, and the container HEALTHCHECK curls localhost — an allow-list would 403 both,
  # fail every probe, and the deployment circuit breaker rolls the service back (it did).
  # Exempt the health endpoint from host authorization; everything else stays enforced.
  config.host_authorization = { exclude: ->(request) { request.path == '/up' } }

  # First cut: the container serves its own static assets (digested JS/CSS under
  # /assets, the Vite bundle under /vite, the bird PNGs under /birds) and
  # CloudFront caches them in front. Later optimisation to slim the image —
  # offload the ~225 MB of illustrations to S3: set RAILS_SERVE_STATIC_FILES=false
  # and point ASSET_HOST at the CDN.
  config.public_file_server.enabled = ENV.fetch('RAILS_SERVE_STATIC_FILES', 'true') == 'true'
  config.asset_host = ENV['ASSET_HOST'] if ENV['ASSET_HOST'].present?

  # Background jobs run only in the cloud (the daily enrichment + digest sweep). Solid
  # Queue is DB-backed against the same RDS (no Redis) and its supervisor runs inside
  # Puma when SOLID_QUEUE_IN_PUMA=true (see config/puma.rb), so there's no extra
  # container. connects_to is left unset → Solid Queue uses the app's default (primary)
  # connection, so its tables live in the one cloud database (no separate queue DB).
  config.active_job.queue_adapter = :solid_queue
end
