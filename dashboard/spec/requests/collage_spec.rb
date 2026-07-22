require 'rails_helper'

RSpec.describe 'Collage' do
  # `/` is now the React SPA shell: a mount point + a bootstrap blob. The bird
  # data it renders is covered by the /api/overview request spec.
  describe 'GET /' do
    it 'mounts the React SPA with a bootstrap blob' do
      get '/'
      expect(response).to have_http_status(:success)
      expect(response.body).to include('ealta-app').and include('data-bootstrap')
    end

    # The collage images live on the art CDN and are the LCP; the SPA can't name them in the
    # initial HTML (it injects them after /api/overview), so a preconnect to that origin is what
    # takes DNS+TLS off the critical path. Guard that it's present and points at the same host the
    # images resolve from.
    it 'preconnects to the illustration CDN when art is CDN-served' do
      allow(Station).to receive(:setting).and_call_original
      allow(Station).to receive(:setting).with('illustrations.base_url', env: 'ILLUSTRATIONS_BASE_URL').
        and_return('https://assets.example.net/')

      get '/'

      expect(response.body).to include('rel="preconnect"').and include('href="https://assets.example.net"')
    end

    it 'omits the preconnect when art is served locally' do
      allow(Station).to receive(:setting).and_call_original
      allow(Station).to receive(:setting).with('illustrations.base_url', env: 'ILLUSTRATIONS_BASE_URL').
        and_return(nil)

      get '/'

      expect(response.body).not_to include('rel="preconnect"')
    end
  end
end
