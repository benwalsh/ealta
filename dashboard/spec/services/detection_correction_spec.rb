require 'rails_helper'

RSpec.describe DetectionCorrection do
  describe '.apply' do
    it 'relabels a detection to a valid species, updating both names together' do
      det = create(:detection, Sci_Name: 'Turdus merula', Com_Name: 'Eurasian Blackbird')
      result = described_class.apply(det.id, sci_name: 'Erithacus rubecula')
      expect(result).to include(ok: true)
      expect(det.reload.Sci_Name).to eq('Erithacus rubecula')
      expect(det.Com_Name).to eq('European Robin')
    end

    it 'refuses an unknown scientific name and changes nothing' do
      det = create(:detection, Sci_Name: 'Turdus merula')
      result = described_class.apply(det.id, sci_name: 'Not aspecies')
      expect(result).to include(ok: false)
      expect(det.reload.Sci_Name).to eq('Turdus merula')
    end

    it 'reports a missing detection rather than raising' do
      expect(described_class.apply(0, sci_name: 'Erithacus rubecula')).to include(ok: false)
    end
  end
end
