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
  end
end
