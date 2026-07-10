require 'rails_helper'

RSpec.describe 'Favourites' do
  let(:auth) do
    OmniAuth::AuthHash.new(
      provider: 'google_oauth2', uid: 'fav-1',
      info: { email: 'follower@example.com', name: 'Follower', image: nil }
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

  it 'rejects an unauthenticated follow with 401' do
    post '/favourites', params: { sci_name: 'Crex crex' }, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(Subscription.count).to eq(0)
  end

  context 'when signed in' do
    before { sign_in }

    def user = User.find_by(email: 'follower@example.com')

    it 'follows a species (creates an active species subscription)' do
      expect do
        post '/favourites', params: { sci_name: 'Crex crex' }, as: :json
      end.to change(Subscription, :count).by(1)

      expect(response.parsed_body).to eq('sci_name' => 'Crex crex', 'following' => true)
      sub = user.subscriptions.sole
      expect(sub).to have_attributes(alert_type: 'species', sci_name: 'Crex crex', active: true)
    end

    it 'is idempotent — following the same bird twice keeps one row' do
      2.times { post '/favourites', params: { sci_name: 'Crex crex' }, as: :json }
      expect(user.subscriptions.where(sci_name: 'Crex crex').count).to eq(1)
    end

    it 're-following reactivates a previously-unfollowed row' do
      sub = user.subscriptions.create!(alert_type: 'species', sci_name: 'Crex crex', active: false)
      post '/favourites', params: { sci_name: 'Crex crex' }, as: :json
      expect(sub.reload.active).to be(true)
    end

    it 'unfollows by deactivating (keeps the row, so history/token survive)' do
      user.subscriptions.create!(alert_type: 'species', sci_name: 'Crex crex')
      expect do
        delete '/favourites', params: { sci_name: 'Crex crex' }, as: :json
      end.not_to change(Subscription, :count)

      expect(response.parsed_body).to eq('sci_name' => 'Crex crex', 'following' => false)
      expect(user.subscriptions.for_species('Crex crex')).to be_empty
    end

    it 'unfollowing a bird never followed is a no-op success' do
      delete '/favourites', params: { sci_name: 'Crex crex' }, as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['following']).to be(false)
    end
  end

  it 'seeds the SPA bootstrap with the followed sci_names' do
    sign_in
    User.find_by(email: 'follower@example.com').
      subscriptions.create!(alert_type: 'species', sci_name: 'Crex crex')
    get '/'
    expect(response.body).to include('Crex crex')
  end
end
