FactoryBot.define do
  factory :heartbeat do
    at { Time.current }
    source { 'live-mic' }
  end
end
