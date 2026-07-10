require 'rails_helper'

RSpec.describe DataReset do
  describe '.clear!' do
    it 'wipes the detection history only on the exact typed confirmation' do
      create_list(:detection, 3)
      result = described_class.clear!(confirm: 'DELETE')
      expect(result).to include(ok: true)
      expect(Detection.count).to eq(0)
    end

    it 'refuses and deletes nothing without the confirmation' do
      create_list(:detection, 2)
      result = described_class.clear!(confirm: 'delete') # wrong case
      expect(result).to include(ok: false)
      expect(Detection.count).to eq(2)
    end
  end
end
