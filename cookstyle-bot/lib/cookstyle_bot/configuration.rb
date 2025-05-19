# typed: strict
# frozen_string_literal: true

require 'config'
require 'sorbet-runtime'

module CookstyleBot
  # Load and set the Settings object using the config gem's recommended pattern.
  config_root = File.expand_path('../../config', __dir__)
  current_env = ENV.fetch('APP_ENV', nil)
  Config.load_and_set_settings(Config.setting_files(config_root, current_env))
end
