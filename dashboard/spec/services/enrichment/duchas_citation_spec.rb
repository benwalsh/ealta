require 'rails_helper'

RSpec.describe Enrichment::DuchasCitation do
  describe '.source' do
    it 'builds the exact attribution the Schools\' Collection requires' do
      src = described_class.source(
        url: 'https://www.duchas.ie/en/cbes/4602757/4601680/4633452',
        volume: '0199', page: '012', collector: 'Ethel Gillmor',
        school: 'Drom Dhá Eithear, Dromahair, Co. Leitrim'
      )

      expect(src[:host]).to eq("The Schools' Collection, Volume 0199, Page 012")
      expect(src[:url]).to eq('https://www.duchas.ie/en/cbes/4602757/4601680/4633452')
      expect(src[:holder]).to eq('© National Folklore Collection, UCD')
      expect(src[:licence]).to eq('CC BY-NC 4.0')
      expect(src[:licence_url]).to eq('https://creativecommons.org/licenses/by-nc/4.0/')
      expect(src[:collector]).to eq('Ethel Gillmor')
    end

    it 'drops a missing volume or page from the reference and omits blank credits' do
      src = described_class.source(url: 'https://www.duchas.ie/en/cbes/1/2/3', page: '  ')

      expect(src[:host]).to eq("The Schools' Collection")
      expect(src).not_to have_key(:collector)
      expect(src).not_to have_key(:informant)
      expect(src).not_to have_key(:school)
    end
  end
end
