require 'rails_helper'

RSpec.describe 'Subscriptions' do
  let(:auth) do
    OmniAuth::AuthHash.new(
      provider: 'google_oauth2', uid: 'sub-1',
      info: { email: 'watcher@example.com', name: 'Watcher', image: 'https://example.com/a.png' }
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

  it 'redirects the account page home when signed out' do
    get '/account'
    expect(response).to redirect_to('/')
  end

  it 'returns 401 to a signed-out JSON caller' do
    get '/account', headers: { 'Accept' => 'application/json' }
    expect(response).to have_http_status(:unauthorized)
  end

  context 'when signed in' do
    before { sign_in }

    it 'boots the SPA with the account panel open (HTML)' do
      get '/account'
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('id="ealta-app"')
      # The bootstrap tells the SPA to open the account panel on a hard nav.
      expect(response.body).to include('&quot;open_panel&quot;:&quot;account&quot;')
    end

    it 'serves the account data as JSON' do
      get '/account', headers: { 'Accept' => 'application/json' }
      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body).to include('roundup' => false)
      expect(body['species']).to be_present
      expect(body['species'].first).to include('sci', 'en')
    end

    it 'creates a species subscription' do
      expect do
        post '/subscriptions', params: { subscription: { alert_type: 'species', sci_name: 'Crex crex' } }
      end.to change(Subscription, :count).by(1)
      expect(User.find_by(email: 'watcher@example.com').subscriptions.first.sci_name).to eq('Crex crex')
    end

    it 'removes a subscription' do
      sub = User.find_by(email: 'watcher@example.com').
            subscriptions.create!(alert_type: 'species', sci_name: 'Crex crex')
      expect { delete "/subscriptions/#{sub.id}" }.to change(Subscription, :count).by(-1)
    end

    describe 'setting a delivery cadence' do
      def me = User.find_by(email: 'watcher@example.com')

      it 'turns breaking news on — every newsworthy kind at immediate delivery' do
        post '/subscriptions/cadence', params: { alert_type: 'breaking', cadence: 'immediate' }
        news = me.subscriptions.where(alert_type: %w[rarity first_ever seasonal])
        expect(news.pluck(:cadence)).to contain_exactly('immediate', 'immediate', 'immediate')
      end

      it 'turns breaking news off — removing every newsworthy standing rule' do
        %w[rarity first_ever seasonal].each { |t| me.subscriptions.create!(alert_type: t, cadence: 'immediate') }
        expect { post '/subscriptions/cadence', params: { alert_type: 'breaking', cadence: 'off' } }.
          to change { me.subscriptions.where(alert_type: %w[rarity first_ever seasonal]).count }.from(3).to(0)
      end

      it 'bulk-sets the cadence of every followed species, keeping the follows' do
        me.subscriptions.create!(alert_type: 'species', sci_name: 'Crex crex')
        me.subscriptions.create!(alert_type: 'species', sci_name: 'Apus apus')
        post '/subscriptions/cadence', params: { alert_type: 'species', cadence: 'off' }
        expect(me.subscriptions.where(alert_type: 'species').pluck(:cadence)).to all(eq('off'))
        expect(me.subscriptions.where(alert_type: 'species').count).to eq(2) # still following
      end
    end
  end

  it 'unsubscribes via a token link without login' do
    sub = create(:user).subscriptions.create!(alert_type: 'species', sci_name: 'Crex crex')
    get "/subscriptions/#{sub.token}/unsubscribe"
    expect(response).to have_http_status(:ok)
    expect(sub.reload.active).to be(false)
  end

  it 'honours a mailbox provider one-click POST (no CSRF token, no login)' do
    sub = create(:user).subscriptions.create!(alert_type: 'species', sci_name: 'Crex crex')
    post "/subscriptions/#{sub.token}/unsubscribe"
    expect(response).to have_http_status(:ok)
    expect(sub.reload.active).to be(false)
  end

  describe 'the daily-letter one-click unsubscribe' do
    it 'drops the reader out of the letter — roundup off, digesting follow silenced' do
      user = create(:user)
      user.subscriptions.create!(alert_type: 'roundup', cadence: 'digest')
      follow = user.subscriptions.create!(alert_type: 'species', sci_name: 'Crex crex', cadence: 'digest')

      get "/letter/#{user.letter_token}/unsubscribe"

      expect(response).to have_http_status(:ok)
      expect(user.subscriptions.active.digesting).to be_empty       # no longer a letter recipient
      expect(follow.reload.active).to be(true)                      # still followed, just silent
      expect(follow.cadence).to eq('off')
    end

    it 'accepts the one-click POST too' do
      user = create(:user)
      user.subscriptions.create!(alert_type: 'roundup', cadence: 'digest')
      post "/letter/#{user.letter_token}/unsubscribe"
      expect(response).to have_http_status(:ok)
      expect(user.subscriptions.active.digesting).to be_empty
    end

    it 'shows a friendly page for an unknown token' do
      get '/letter/nope/unsubscribe'
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("isn't valid")
    end
  end
end
