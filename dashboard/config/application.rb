require_relative 'boot'

require 'rails'
require 'active_model/railtie'
require 'active_job/railtie'
require 'active_record/railtie'
require 'action_controller/railtie'
require 'action_view/railtie'
require 'action_cable/engine'
Bundler.require(*Rails.groups)

module Ealta
  class Application < Rails::Application
    config.load_defaults 8.1
    config.autoload_lib(ignore: %w[assets tasks])
    # The station's clock — every day boundary (the Journal's frozen days, the daily
    # letter, "today" on the panel) follows it. Config: station.yml `timezone:` (an IANA
    # name), default Europe/Dublin. Read directly from the profile YAML because this runs
    # before the app's classes load; an unknown zone falls back loudly rather than booting
    # a wall display onto the wrong day.
    config.time_zone = begin
      profile = ENV['STATION_PROFILE'].to_s
      zone = File.file?(File.join(profile, 'station.yml')) &&
             YAML.safe_load_file(File.join(profile, 'station.yml'))&.fetch('timezone', nil)
      if zone && ActiveSupport::TimeZone[zone].nil?
        warn "station.yml timezone #{zone.inspect} is not a known zone — using Europe/Dublin"
        zone = nil
      end
      zone.presence || 'Europe/Dublin'
    end
    if defined?(MissionControl::Jobs)
      config.mission_control.jobs.base_controller_class = 'JobsBaseController'
      config.mission_control.jobs.http_basic_auth_enabled = false
    end

    config.generators do |g|
      g.template_engine :haml
      g.test_framework :rspec, fixtures: false, view_specs: false,
                               helper_specs: false, routing_specs: false
      g.system_tests = nil
    end
  end
end
