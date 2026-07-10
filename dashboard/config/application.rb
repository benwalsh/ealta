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
    config.time_zone = 'Europe/Dublin'
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
