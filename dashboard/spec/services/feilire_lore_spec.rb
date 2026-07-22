require 'rails_helper'

RSpec.describe FeilireLore do
  def stub_lore(data)
    allow(StationProfile).to receive(:yaml).with('content/felire_lore.yml').and_return(data)
  end

  describe '.for' do
    it 'returns nil for a day the calendar does not cover (the Journal falls back to the season)' do
      stub_lore({})
      expect(described_class.for(Date.new(2026, 7, 20))).to be_nil
    end

    it 'features the chief entry, with a credit composed from the shared _meta provenance' do
      stub_lore(
        '_meta' => { 'source_work' => 'The Martyrology of Óengus', 'editor' => 'Whitley Stokes',
                     'year_translation' => 1905 },
        '01-15' => [{ 'saints' => ['Íte of Cluain'], 'gloss' => 'Íte the devout of Cluain.',
                      'lead' => 'gloss', 'note' => 'Íte of Killeedy.' }]
      )
      out = described_class.for(Date.new(2026, 1, 15))

      expect(out).to include(saints: ['Íte of Cluain'], verse: false,
                             text: 'Íte the devout of Cluain.', note: 'Íte of Killeedy.')
      expect(out[:credit]).to eq('The Martyrology of Óengus, trans. Whitley Stokes (1905)')
    end

    it 'sets the quatrain in verse only when the entry promotes it to lead' do
      stub_lore('02-01' => [{ 'gloss' => 'g', 'quatrain' => "They magnify February's calends…",
                              'lead' => 'quatrain' }])
      out = described_class.for(Date.new(2026, 2, 1))
      expect(out).to include(verse: true)
      expect(out[:text]).to start_with('They magnify')
    end

    it 'shows the quatrain as plain text when a machine-extracted day has no gloss' do
      stub_lore('03-04' => [{ 'quatrain' => 'A quatrain and nothing else.', 'lead' => 'gloss' }])
      out = described_class.for(Date.new(2026, 3, 4))
      expect(out).to include(verse: false, text: 'A quatrain and nothing else.')
    end

    it 'falls back to the season (returns nil) on a source-gap or empty day' do
      stub_lore('02-16' => [{ 'saints' => [], 'lead' => 'gloss',
                              'gloss' => '[SOURCE GAP — verify against Stokes; falls back to season]' }])
      expect(described_class.for(Date.new(2026, 2, 16))).to be_nil
    end

    it 'hides an Old Irish quatrain until a fluent reader has verified it' do
      base = { 'quatrain_ga' => 'Morait calaind Febrai', 'gloss' => 'g' }
      stub_lore('02-01' => [base.merge('ga_verified' => false)])
      expect(described_class.for(Date.new(2026, 2, 1))[:quatrain_ga]).to be_nil

      stub_lore('02-01' => [base.merge('ga_verified' => true)])
      expect(described_class.for(Date.new(2026, 2, 1))[:quatrain_ga]).to eq('Morait calaind Febrai')
    end
  end
end
