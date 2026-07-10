namespace :ealta do
  desc 'Refresh the station almanac (weather + tide + coords) into storage/almanac.json'
  task almanac_refresh: :environment do
    data = Almanac.refresh
    w = data[:weather]
    t = data[:tide]
    c = data[:coords] || {}
    place = c[:place].is_a?(Hash) ? c[:place][:en] : c[:place]
    puts 'almanac refreshed: ' \
         "#{place || format('%.2f,%.2f', c[:lat].to_f, c[:lon].to_f)} · " \
         "#{w ? "#{w[:emoji]} #{w[:temp]}°C #{w[:text]}" : 'weather —'} · " \
         "#{t ? t[:label] : 'tide —'}"
  end
end
