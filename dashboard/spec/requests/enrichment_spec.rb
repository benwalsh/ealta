require 'rails_helper'

RSpec.describe 'On-demand enrichment' do
  let(:sci) { 'Erithacus rubecula' }
  let(:auth) do
    OmniAuth::AuthHash.new(provider: 'google_oauth2', uid: 'e1',
                           info: { email: 'me@example.com', name: 'Me' })
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

  def robin_bundle(**over)
    EnrichmentBundle.new(sci_name: sci, date: Date.current, common_name: 'European Robin',
                         blocks: [{ type: 'fact', id: 'f', text: 'Robins hold winter territories.',
                                    sources: [{ host: 'rspb.org.uk', url: 'https://rspb.org.uk/robin' }] }], **over)
  end

  it 'requires login' do
    post "/species/#{ERB::Util.url_encode(sci)}/enrichment"
    expect(response).to redirect_to('/')
  end

  context 'when signed in' do
    before { sign_in }

    it 'returns an already-sourced bundle without looking it up again' do
      robin_bundle.save!
      expect(Enrichment::Builder).not_to receive(:build_one)
      post "/species/#{ERB::Util.url_encode(sci)}/enrichment"
      expect(response.parsed_body.dig('enrichment', 'blocks', 0, 'text')).to eq('Robins hold winter territories.')
    end

    it 'sources on demand when nothing is stored yet' do
      allow(Enrichment::Builder).to receive(:build_one).
        with(date: Date.current, sci_name: sci).and_return(robin_bundle)
      post "/species/#{ERB::Util.url_encode(sci)}/enrichment"
      expect(response.parsed_body.dig('enrichment', 'blocks', 0, 'text')).to eq('Robins hold winter territories.')
    end

    it 'returns null when the look-up finds nothing (e.g. the model is unavailable)' do
      allow(Enrichment::Builder).to receive(:build_one).and_return(nil)
      post "/species/#{ERB::Util.url_encode(sci)}/enrichment"
      expect(response.parsed_body['enrichment']).to be_nil
    end
  end
end
