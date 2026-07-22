require 'rails_helper'

RSpec.describe GenerateIllustrationJob do
  it 'does nothing when illustrations are off (no bucket — the Pi)' do
    allow(Illustrations).to receive(:enabled?).and_return(false)
    expect(Illustrations).not_to receive(:generate)
    described_class.new.perform('Pluvialis apricaria')
  end

  it 'skips a bird already in the bucket — idempotent across duplicate enqueues' do
    allow(Illustrations).to receive_messages(enabled?: true, exists?: true)
    expect(Illustrations).not_to receive(:generate)
    described_class.new.perform('Pluvialis apricaria')
  end

  it 'renders a bird we cannot yet picture' do
    allow(Illustrations).to receive_messages(enabled?: true, exists?: false)
    expect(Illustrations).to receive(:generate).with('Pluvialis apricaria', 'European Golden Plover')
    described_class.new.perform('Pluvialis apricaria', 'European Golden Plover')
  end

  it 'logs and swallows a failed render so one bad bird cannot wedge the queue' do
    allow(Illustrations).to receive_messages(enabled?: true, exists?: false)
    allow(Illustrations).to receive(:generate).and_raise('gemini exploded')
    expect(Rails.logger).to receive(:warn).with(/GenerateIllustrationJob: Pluvialis apricaria failed/)
    expect { described_class.new.perform('Pluvialis apricaria') }.not_to raise_error
  end
end
