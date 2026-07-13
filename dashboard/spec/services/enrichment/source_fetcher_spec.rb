require 'rails_helper'

RSpec.describe Enrichment::SourceFetcher do
  # Run against the sample profile, whose sources.yml trusts the Irish host set and
  # enables the dúchas adapter — the allowlist + adapter are now station config, not constants.
  subject(:fetcher) { described_class.new(sci_name: 'Cuculus canorus', run_id: 'run-1') }

  around { |example| with_station_profile(StationProfileHelpers::SAMPLE_PROFILE) { example.run } }

  describe '#trusted?' do
    it 'accepts exact trusted hosts and BirdWatch county affiliates' do
      expect(fetcher.trusted?('duchas.ie')).to be(true)
      expect(fetcher.trusted?('birdwatchireland.ie')).to be(true)
      expect(fetcher.trusted?('birdwatchgalway.org')).to be(true) # discovered affiliate
      expect(fetcher.trusted?('en.wikipedia.org')).to be(true)
    end

    it 'refuses anything off the allowlist' do
      expect(fetcher.trusted?('example.com')).to be(false)
      expect(fetcher.trusted?('evil-birdwatchireland.ie.attacker.com')).to be(false)
      expect(fetcher.trusted?(nil)).to be(false)
    end
  end

  # Stubbing the fetcher's own http_get is the network boundary — there's no webmock
  # in this project, and it's exactly what a unit test of the allowlist/logging wants.
  # rubocop:disable RSpec/SubjectStub
  describe '#fetch' do
    it 'refuses an untrusted URL without a request or a log row' do
      expect(fetcher).not_to receive(:http_get)
      result = fetcher.fetch('https://example.com/cuckoo')
      expect(result).to include(error: a_string_matching(/untrusted host/))
      expect(SourceFetchLog.count).to eq(0)
    end

    it 'fetches a trusted URL, strips it to text, and logs exactly one hit' do
      html = '<html><body><script>x()</script><p>Cuckoos are brood parasites.</p></body></html>'
      allow(fetcher).to receive(:http_get).and_return(html)
      result = fetcher.fetch('https://www.duchas.ie/en/cbes/1')
      expect(result[:text]).to eq('Cuckoos are brood parasites.')
      expect(result[:host]).to eq('www.duchas.ie')
      expect(SourceFetchLog.count).to eq(1)
      expect(SourceFetchLog.last).to have_attributes(host: 'www.duchas.ie', sci_name: 'Cuculus canorus')
    end

    # Stripping hrefs was why dúchas/CELT searches dead-ended: the model saw result titles
    # but no URL to follow. Trusted on-site links are now appended (relative → absolute),
    # off-allowlist ones excluded, so a search page can be navigated to the actual entry.
    it 'appends trusted on-site links so an index page can be navigated' do
      html = '<html><body><p>Stories about crows.</p>' \
             '<a href="/en/cbes/4602668">A story mentioning crows</a>' \
             '<a href="https://evil.example.com/x">off-site</a></body></html>'
      allow(fetcher).to receive(:http_get).and_return(html)
      result = fetcher.fetch('https://www.duchas.ie/en/cbes/browse')
      expect(result[:text]).to include('LINKS').and include('https://www.duchas.ie/en/cbes/4602668')
      expect(result[:text]).not_to include('evil.example.com')
    end

    # A dúchas STORY page is fetched via its clean open-data XML transcript, but cited by
    # the human /en/ URL the model followed — so the block's source matches the fetch log.
    it 'reads a dúchas story from the XML endpoint yet cites the /en/ page' do
      xml = '<pPage><story url="https://www.duchas.ie/xml/cbes/4758602/4757997/4955154">' \
            '<transcript>The magpie and the wren build nests with a roof.</transcript></story></pPage>'
      expect(fetcher).to receive(:http_get).with('https://www.duchas.ie/xml/cbes/4758602/4757997').and_return(xml)
      result = fetcher.fetch('https://www.duchas.ie/en/cbes/4758602/4757997')
      expect(result[:text]).to include('The magpie and the wren build nests with a roof.')
      # the entry (story) URL is surfaced as a human /en/ link so a spanning story can be isolated
      expect(result[:text]).to include('https://www.duchas.ie/en/cbes/4758602/4757997/4955154')
      expect(result[:url]).to eq('https://www.duchas.ie/en/cbes/4758602/4757997')
    end

    # dúchas's on-site search is a dead JS app server-side, so a SEARCH goes through the JSON
    # API instead: each hit's transcript text + a citable /en/cbes/…/…/… URL (logged so the
    # model may cite the story it retells).
    it 'runs a dúchas SEARCH through the JSON API, returning story text + citable URLs' do
      json = { entries: [{ id: 4_955_154, chapterID: 4_758_602, pageID: 4_757_997, title: 'The Magpie',
                           text: 'The <span class="exact">magpie</span> and the wren build a domed nest.' }] }.to_json
      expect(fetcher).to receive(:http_get).
        with(a_string_starting_with('https://beta.duchas.ie/api/en/cbes/transcripts?SearchText=magpie')).
        and_return(json)
      result = fetcher.fetch('https://www.duchas.ie/en/cbes?Search=magpie')
      expect(result[:text]).to include('The magpie and the wren build a domed nest.')
      expect(result[:text]).to include('https://www.duchas.ie/en/cbes/4758602/4757997/4955154')
      expect(SourceFetchLog.where(host: 'duchas.ie').pluck(:url)).
        to include('https://www.duchas.ie/en/cbes/4758602/4757997/4955154')
    end

    it 'returns an error (no raise, no log) when the request fails' do
      allow(fetcher).to receive(:http_get).and_return(nil)
      result = fetcher.fetch('https://duchas.ie/x')
      expect(result).to include(:error)
      expect(SourceFetchLog.count).to eq(0)
    end
  end
  # rubocop:enable RSpec/SubjectStub

  # dúchas.ie and CELT answer a 301 before serving the page, so http_get MUST follow
  # redirects — otherwise every Irish-folklore fetch reads as failed and the model falls
  # back to Wikipedia. Real Net::HTTP response objects so the case/when class match holds.
  describe '#http_get redirects' do
    def redirect(location)
      Net::HTTPFound.new('1.1', '302', 'Found').tap { |r| r['location'] = location }
    end

    def ok(body)
      Net::HTTPOK.new('1.1', '200', 'OK').tap { |r| allow(r).to receive(:body).and_return(body) }
    end

    it 'follows a redirect to another trusted host and returns the final body' do
      allow(Net::HTTP).to receive(:start).and_return(redirect('https://www.duchas.ie/final'), ok('<p>lore</p>'))
      expect(fetcher.send(:http_get, 'https://duchas.ie/start')).to eq('<p>lore</p>')
    end

    it 'refuses to follow a redirect off the allowlist' do
      allow(Net::HTTP).to receive(:start).and_return(redirect('https://evil.example.com/x'))
      expect(fetcher.send(:http_get, 'https://celt.ucc.ie/x')).to be_nil
    end

    it 'gives up after MAX_REDIRECTS rather than looping' do
      allow(Net::HTTP).to receive(:start).and_return(redirect('https://celt.ucc.ie/loop'))
      expect(fetcher.send(:http_get, 'https://celt.ucc.ie/loop')).to be_nil
    end
  end
end
