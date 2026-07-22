require 'rails_helper'

RSpec.describe Illustrations do
  let(:s3) { instance_double(Aws::S3::Client) }

  before do
    allow(described_class).to receive(:client).and_return(s3)
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with('ILLUSTRATIONS_BUCKET').and_return('station-illustrations')
  end

  describe '.slug' do
    it "matches the app's /birds/<slug>.png convention" do
      expect(described_class.slug('Pluvialis apricaria')).to eq('pluvialis-apricaria')
    end
  end

  describe '.enabled?' do
    it 'is on when there is a bucket to publish to (the cloud)' do
      expect(described_class).to be_enabled
    end

    it 'is off without a bucket — the Pi, which loads finished assets and never generates' do
      allow(ENV).to receive(:[]).with('ILLUSTRATIONS_BUCKET').and_return(nil)
      expect(described_class).not_to be_enabled
    end
  end

  describe '.exists?' do
    it 'is true when the bucket already has the art' do
      expect(s3).to receive(:head_object).
        with(bucket: 'station-illustrations', key: 'pluvialis-apricaria.png')
      expect(described_class.exists?('Pluvialis apricaria')).to be(true)
    end

    it 'is false when the bucket has nothing there yet' do
      allow(s3).to receive(:head_object).and_raise(Aws::S3::Errors::NotFound.new(nil, 'nope'))
      expect(described_class.exists?('Pluvialis apricaria')).to be(false)
    end
  end

  describe '.generate' do
    it 'renders in the station style then publishes, logging each step' do
      allow(described_class).to receive_messages(render: nil, publish: ['pluvialis-apricaria.png', 'masks.json'])
      expect(described_class).to receive(:render).with('Pluvialis apricaria', 'European Golden Plover')
      expect(Rails.logger).to receive(:info).at_least(:twice)
      described_class.generate('Pluvialis apricaria', 'European Golden Plover')
    end
  end
end
