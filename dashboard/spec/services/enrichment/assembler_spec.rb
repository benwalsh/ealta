require 'rails_helper'

RSpec.describe Enrichment::Assembler do
  let(:date) { Date.new(2026, 7, 4) }
  let(:user) { create(:user) }

  before do
    user.subscriptions.create!(alert_type: 'species', sci_name: 'Passer domesticus', cadence: 'digest')
    create_list(:detection, 4, Sci_Name: 'Passer domesticus', Date: date, Confidence: 0.9)
    EnrichmentBundle.create!(
      sci_name: 'Passer domesticus', date: date, common_name: 'House Sparrow', irish_name: 'Gealbhan binne',
      blocks: [{ type: 'fact', id: 'colony', text: 'House sparrows nest in loose colonies near buildings.',
                 sources: [{ host: 'en.wikipedia.org', url: 'https://en.wikipedia.org/wiki/House_sparrow' }] }]
    )
  end

  it 'falls back (nil) when Bedrock is disabled' do
    allow(Bedrock).to receive(:disabled?).and_return(true)
    expect(described_class.for(user: user, date: date)).to be_nil
  end

  it 'falls back (nil) when the day has no enrichment to add' do
    allow(Bedrock).to receive(:disabled?).and_return(false)
    EnrichmentBundle.delete_all
    expect(described_class.for(user: user, date: date)).to be_nil
  end

  it 'builds a catalogue that leads with the reader’s followed bird, its count and block text' do
    facts = DigestFacts.for(user: user, date: date)
    line = described_class.catalogue_for(facts, date).first
    expect(line).to include('House Sparrow', 'reader follows', '4×', 'loose colonies')
  end

  it 'passes the block text into the prompt so Nova can only reuse sourced facts' do
    facts = DigestFacts.for(user: user, date: date)
    msg = described_class.user_message(facts, described_class.catalogue_for(facts, date))
    expect(msg).to include('CATALOGUE').and include('loose colonies near buildings')
  end

  it 'returns the assembled note when Nova produces valid prose' do
    note = 'Your house sparrows were about today, four calls in all; they nest in loose colonies near buildings.'
    allow(Bedrock).to receive_messages(disabled?: false, converse: note)
    expect(described_class.for(user: user, date: date)).to eq([note])
  end

  it 'rejects a shouting note and falls back' do
    allow(Bedrock).to receive_messages(disabled?: false, converse: 'House sparrows everywhere today!')
    expect(described_class.for(user: user, date: date)).to be_nil
  end
end
