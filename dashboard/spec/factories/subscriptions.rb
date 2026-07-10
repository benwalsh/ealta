FactoryBot.define do
  factory :subscription do
    user
    alert_type { 'species' }
    sci_name { 'Crex crex' }
    active { true }
  end
end
