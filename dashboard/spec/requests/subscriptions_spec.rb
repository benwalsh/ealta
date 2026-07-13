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

  context 'when signed in' do
    before { sign_in }

    it 'renders the account page' do
      get '/account'
      expect(response).to have_http_status(:ok)
      # bi() renders both languages; apostrophes are html-escaped, so assert on stable fragments.
      expect(response.body).to include('The daily letter', 'Species you', 'Speicis a leanann tú')
      expect(response.body).not_to include('Breaking news') # trimmed: the page is the letter + following only
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
end
