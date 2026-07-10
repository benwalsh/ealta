# Google sign-in. Credentials come from the environment (never committed) — set
# GOOGLE_CLIENT_ID / GOOGLE_CLIENT_SECRET, and register the callback URL
# (<host>/auth/google_oauth2/callback) in the Google Cloud console.
# Behind a CDN the app sees the origin host, not the public domain,
# so OmniAuth would build a callback that doesn't match the one registered with
# Google. When SITE_URL is set (cloud), pin the redirect_uri to the public callback;
# locally (no SITE_URL) OmniAuth derives it from the request (http://localhost:…).
google_options = { scope: 'email,profile', prompt: 'select_account' }
google_options[:redirect_uri] = "#{ENV.fetch('SITE_URL')}/auth/google_oauth2/callback" if ENV['SITE_URL'].present?

Rails.application.config.middleware.use OmniAuth::Builder do
  provider :google_oauth2, ENV.fetch('GOOGLE_CLIENT_ID', nil), ENV.fetch('GOOGLE_CLIENT_SECRET', nil), google_options
end

OmniAuth.config.logger = Rails.logger
# Redirect (don't raise) if a sign-in is abandoned or fails.
OmniAuth.config.on_failure = proc do |env|
  SessionsController.action(:failure).call(env)
end

# Dev-only convenience: FAKE_LOGIN=1 mocks the Google round-trip so the admin UI
# can be built and previewed locally without real credentials. Never active
# outside development.
if Rails.env.development? && ENV['FAKE_LOGIN'].present?
  OmniAuth.config.test_mode = true
  OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
    provider: 'google_oauth2',
    uid:      'dev-001',
    info:     { email: 'dev@example.com', name: 'Dev Admin', image: nil }
  )
end
