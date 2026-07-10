FactoryBot.define do
  factory :detection do
    Date { Date.current }
    Time { Time.current }
    Sci_Name { 'Erithacus rubecula' }
    Com_Name { 'European Robin' }
    Confidence { 0.8 }
    Week { Date.current.cweek }
  end
end
