require 'rails_helper'

RSpec.describe DigestSummary do
  let(:facts) do
    DigestFacts::Result.new(
      date:    Date.new(2026, 7, 4),
      follows: [{ sci: 'Crex crex', en: 'Corncrake', ga: 'Traonach', count: 2 }],
      alerts:  [{ kind: 'rarity', sci: 'Anser anser', en: 'Greylag Goose', ga: 'Gé ghlas' }],
      roundup: nil
    )
  end

  it 'falls back (nil) when Bedrock is disabled — the list email stands alone' do
    allow(Bedrock).to receive(:disabled?).and_return(true)
    expect(described_class.for(facts)).to be_nil
  end

  it 'serialises the facts verbatim into the prompt (follows led, counts exact)' do
    msg = described_class.user_message(facts)
    expect(msg).to include('Corncrake (Traonach) x2')
    expect(msg).to include('rarity: Greylag Goose')
  end

  it 'returns the note when the model produces valid prose' do
    allow(Bedrock).to receive_messages(disabled?: false,
                                       converse:  'Your corncrake called twice today, a quiet day otherwise.')
    expect(described_class.for(facts)).to eq(['Your corncrake called twice today, a quiet day otherwise.'])
  end

  it 'rejects a shouting note (house rule: no exclamation marks) and falls back' do
    allow(Bedrock).to receive_messages(disabled?: false,
                                       converse:  'Your corncrake was heard twice today, and nothing else you follow!')
    expect(described_class.for(facts)).to be_nil
  end
end
