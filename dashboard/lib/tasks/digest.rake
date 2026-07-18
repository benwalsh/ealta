namespace :ealta do
  desc "Send the daily digest to 'digest'-cadence users (yesterday; DIGEST_DATE=YYYY-MM-DD overrides)"
  task digest: :environment do
    date = ENV['DIGEST_DATE'].present? ? Date.parse(ENV['DIGEST_DATE']) : Date.yesterday
    sent = DailyLetter.deliver_all(date: date)
    puts "digest: sent #{sent} email(s) for #{date}"
  end
end
