require 'rails_helper'

# The bird endpoint resolves bytes local-first, then to a CDN — so a station can keep its
# art off the image (on S3/CloudFront) while dev and the Pi serve local copies.
RSpec.describe 'Bird illustrations' do
  around { |ex| with_station_profile(StationProfileHelpers::SAMPLE_PROFILE) { ex.run } }

  it 'streams an illustration that exists in the profile' do
    get '/birds/passer-domesticus.png'

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq('image/png')
  end

  context 'when the illustration is not on disk' do
    it 'redirects to ILLUSTRATIONS_BASE_URL when the station publishes to a CDN' do
      original = ENV.fetch('ILLUSTRATIONS_BASE_URL', nil)
      ENV['ILLUSTRATIONS_BASE_URL'] = 'https://cdn.example.test/birds'

      get '/birds/nonexistent-bird.png'

      expect(response).to have_http_status(:found)
      expect(response.headers['Location']).to eq('https://cdn.example.test/birds/nonexistent-bird.png')
    ensure
      ENV['ILLUSTRATIONS_BASE_URL'] = original
    end

    it '404s when there is no base URL (unchanged behaviour)' do
      original = ENV.delete('ILLUSTRATIONS_BASE_URL')

      get '/birds/nonexistent-bird.png'

      expect(response).to have_http_status(:not_found)
    ensure
      ENV['ILLUSTRATIONS_BASE_URL'] = original if original
    end
  end
end
