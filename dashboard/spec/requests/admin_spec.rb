require 'rails_helper'

RSpec.describe 'Admin' do
  # The sample profile is bilingual (ga, en) with an Irish default — so the language picker
  # and the language-change assertions have two languages to work with.
  around { |example| with_station_profile(StationProfileHelpers::SAMPLE_PROFILE) { example.run } }

  let(:auth) do
    OmniAuth::AuthHash.new(
      provider: 'google_oauth2', uid: 'admin-1',
      info: { email: 'boss@example.com', name: 'Boss', image: nil }
    )
  end

  def sign_in
    OmniAuth.config.test_mode = true
    OmniAuth.config.mock_auth[:google_oauth2] = auth
    Rails.application.env_config['omniauth.auth'] = auth
    get '/auth/google_oauth2/callback'
  end

  after do
    OmniAuth.config.test_mode = false
    OmniAuth.config.mock_auth[:google_oauth2] = nil
    Rails.application.env_config.delete('omniauth.auth')
  end

  it 'bounces anonymous visitors home' do
    get '/admin'
    expect(response).to redirect_to('/')
  end

  it 'bounces signed-in non-admins home (fail-closed)' do
    sign_in # not in ADMIN_EMAILS
    get '/admin'
    expect(response).to redirect_to('/')
  end

  it 'boots the SPA with the admin panel open (HTML) for admins' do
    allow_any_instance_of(User).to receive(:admin?).and_return(true)
    sign_in
    get '/admin'
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('id="ealta-app"')
    expect(response.body).to include('&quot;open_panel&quot;:&quot;admin&quot;')
  end

  it 'serves the health snapshot as JSON for admins' do
    allow_any_instance_of(User).to receive(:admin?).and_return(true)
    sign_in
    get '/admin', headers: { 'Accept' => 'application/json' }
    expect(response).to have_http_status(:ok)
    body = response.parsed_body
    expect(body).to include('listening', 'alerts', 'system', 'station')
    expect(body['station']['options'].pluck('name')).to include('English', 'Gaeilge')
  end

  it 'returns 403 (not an HTML redirect) to a non-admin JSON caller' do
    sign_in # not in ADMIN_EMAILS
    get '/admin', headers: { 'Accept' => 'application/json' }
    expect(response).to have_http_status(:forbidden)
  end

  it 'lets an admin change the station language' do
    allow_any_instance_of(User).to receive(:admin?).and_return(true)
    sign_in
    expect { patch '/admin/station', params: { station: { language: 'en' } } }.
      to change(Station, :language).from(:ga).to(:en)
    expect(response).to redirect_to('/admin')
  end

  it 'ignores a bad language and keeps the current one' do
    allow_any_instance_of(User).to receive(:admin?).and_return(true)
    sign_in
    expect { patch '/admin/station', params: { station: { language: 'fr' } } }.
      not_to change(Station, :language)
  end

  it 'refuses the settings change for non-admins (fail-closed)' do
    sign_in # not an admin
    expect { patch '/admin/station', params: { station: { language: 'en' } } }.
      not_to change(Station, :language)
    expect(response).to redirect_to('/')
  end
end
