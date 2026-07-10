FactoryBot.define do
  factory :user do
    provider { 'google_oauth2' }
    sequence(:uid) { |n| "uid-#{n}" }
    sequence(:email) { |n| "birder#{n}@example.com" }
    name { 'Test Birder' }
  end
end
