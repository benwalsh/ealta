FactoryBot.define do
  factory :event do
    event_type { 'species' }
    sci_name { 'Crex crex' }
    occurred_on { Date.current }
  end
end
