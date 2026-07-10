require 'rails_helper'

RSpec.describe 'Sessions' do
  let(:auth) do
    OmniAuth::AuthHash.new(
      provider: 'google_oauth2', uid: '123',
      info: { email: 'boss@example.com', name: 'Boss', image: 'https://example.com/a.png' }
    )
  end

  before do
    OmniAuth.config.test_mode = true
    OmniAuth.config.mock_auth[:google_oauth2] = auth
    Rails.application.env_config['omniauth.auth'] = auth
  end

  after do
    OmniAuth.config.test_mode = false
    OmniAuth.config.mock_auth[:google_oauth2] = nil
    Rails.application.env_config.delete('omniauth.auth')
  end

  # The signed-in user surfaces in the React bootstrap blob on `/` (the chrome is
  # React-rendered, so we assert on the server-observable bootstrap, not markup).
  it 'creates a user and signs in on the callback' do
    expect { get '/auth/google_oauth2/callback' }.to change(User, :count).by(1)
    follow_redirect!
    expect(response.body).to include('boss@example.com')
  end

  it 'is idempotent for the same Google account' do
    get '/auth/google_oauth2/callback'
    expect { get '/auth/google_oauth2/callback' }.not_to change(User, :count)
  end

  it 'signs out' do
    get '/auth/google_oauth2/callback'
    delete '/logout'
    follow_redirect!
    expect(response.body).not_to include('boss@example.com')
  end

  it 'bootstraps no user when logged out' do
    get '/'
    expect(response.body).not_to include('boss@example.com')
  end
end
