require 'rails_helper'

RSpec.describe Enrichment::Builder do
  let(:date) { Date.new(2026, 7, 4) }
  let(:sci)  { 'Aegithalos caudatus' }
  let(:url)  { 'https://en.wikipedia.org/wiki/Long-tailed_tit' }

  # Fake Converse content items exposing the .text / .tool_use accessors the builder
  # reads, and the response's stop_reason + output.message.content.
  def text_item(str) = double(text: str, tool_use: nil)
  def response(stop, items) = double(stop_reason: stop, output: double(message: double(content: items)))

  def use_item(id, src)
    double(text: nil, tool_use: double(tool_use_id: id, name: 'fetch_source', input: { 'url' => src }))
  end

  before do
    allow(Bedrock).to receive_messages(disabled?: false, available?: true) # exercise the LLM sourcing path
    # The one real network boundary — everything else in SourceFetcher runs for real
    # (trusted-host check, the source_fetch_log write, text extraction).
    allow_any_instance_of(Enrichment::SourceFetcher).to receive(:http_get).
      and_return('<html><body><p>Long-tailed tits build a domed nest of moss and feathers.</p></body></html>')
  end

  it 'sources cited blocks from a fetched page and stores them as one bundle' do
    final = [
      { type: 'fact', id: 'nest', text: 'They build a domed nest of moss and feathers.',
        sources: [{ host: 'en.wikipedia.org', url: url }] },
      { type: 'folklore', id: 'bottle', gated: true, text: 'It was once called the bottle-tit for its nest.',
        sources: [{ host: 'en.wikipedia.org', url: url }] }
    ].to_json
    allow(Bedrock).to receive(:converse_tools).and_return(
      response('tool_use', [use_item('t1', url)]),
      response('end_turn', [text_item(final)])
    )

    bundle = described_class.build_one(date: date, sci_name: sci)

    expect(bundle).to be_persisted
    expect(bundle.block_objects.map(&:type)).to contain_exactly('fact', 'folklore')
    expect(SourceFetchLog.where(sci_name: sci)).to be_present
  end

  it 'drops a block whose citation was never actually fetched (no fabricated sources)' do
    final = [
      { type: 'fact', id: 'real', text: 'A domed nest of moss.', sources: [{ host: 'en.wikipedia.org', url: url }] },
      { type: 'fact', id: 'fake', text: 'An invented claim.',
        sources: [{ host: 'en.wikipedia.org', url: 'https://en.wikipedia.org/wiki/Never_fetched' }] }
    ].to_json
    allow(Bedrock).to receive(:converse_tools).and_return(
      response('tool_use', [use_item('t1', url)]),
      response('end_turn', [text_item(final)])
    )

    expect(described_class.build_one(date: date, sci_name: sci).block_objects.map(&:id)).to eq(['real'])
  end

  it 'stores nothing (nil) when no block survives validation' do
    allow(Bedrock).to receive(:converse_tools).and_return(response('end_turn', [text_item('[]')]))
    expect(described_class.build_one(date: date, sci_name: sci)).to be_nil
    expect(EnrichmentBundle.where(sci_name: sci)).to be_empty
  end

  it 'falls back to a Wikipedia fact block when no LLM is configured' do
    allow(Bedrock).to receive(:available?).and_return(false)
    wiki = Enrichment::Block.from(
      type: 'fact', id: 'wikipedia-x', text: 'A small woodland thrush.',
      sources: [{ host: 'en.wikipedia.org', url: 'https://en.wikipedia.org/wiki/x' }]
    )
    allow(Enrichment::Wikipedia).to receive(:blocks_for).and_return([wiki])

    bundle = described_class.build_one(date: date, sci_name: sci, common_name: 'Long-tailed Tit')
    expect(bundle.block_objects.map(&:id)).to eq(['wikipedia-x'])
  end

  describe '.run daily floor (so a quiet station still builds a library)' do
    let(:routine_facts) do
      { items: [
        { sci_name: 'Passer domesticus', common_name: 'House Sparrow', irish_name: 'Gealbhan binne',
          importance: 5, flags: %w[routine most_common] },
        { sci_name: 'Pica pica', common_name: 'Eurasian Magpie', irish_name: 'Snag breac',
          importance: 5, flags: %w[routine] }
      ] }
    end

    before do
      allow(DailyFacts).to receive(:for).and_return(routine_facts)
      allow(described_class).to receive(:build_one) { |**kw|
        instance_double(EnrichmentBundle, sci_name: kw[:sci_name])
      }
    end

    # A specific expectation refines the general build_one stub from the `before` block:
    # the matching call is asserted here, any other falls through to that stub.
    def expect_build_one(sci)
      expect(described_class).to receive(:build_one).
        with(hash_including(sci_name: sci)) { |**kw| instance_double(EnrichmentBundle, sci_name: kw[:sci_name]) }
    end

    it 'sources the day\'s top due bird even though nothing clears the notable bar' do
      expect_build_one('Passer domesticus').once
      result = described_class.run(date: date)
      expect(result.size).to eq(1) # DAILY_FLOOR
    end

    it 'moves the floor to the next bird once the first is already sourced' do
      allow(Enrichment::Policy).to receive(:due?).and_return(false, true) # sparrow done, magpie due
      expect_build_one('Pica pica')
      described_class.run(date: date)
    end

    it 'still prefers a genuinely notable species over the floor' do
      allow(EnrichmentGate).to receive(:species_for).and_return(
        [{ sci_name: 'Cuculus canorus', common_name: 'Common Cuckoo', irish_name: 'Cuach' }]
      )
      expect_build_one('Cuculus canorus').once
      described_class.run(date: date)
    end
  end
end
