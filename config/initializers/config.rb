# frozen_string_literal: true
# typed: true

begin
  require 'config'
  require 'dry-schema'
  # Create a local reference to the Config constant to avoid lint issues
  # Use Object.const_get to help Sorbet understand this constant resolution
  ConfigGem = Object.const_get('Config')
rescue LoadError => e
  raise "Required gem not available: #{e.message}. Please run bundle install."
end

require_relative '../validators/settings_validator'

# Map critical environment variables so they're accessible in our app
ENV['GCR_GITHUB_TOKEN'] = ENV['GITHUB_TOKEN'] if ENV['GITHUB_TOKEN']
ENV['GCR_APP_ID'] = ENV['APP_ID'] if ENV['APP_ID']
ENV['GCR_INSTALLATION_ID'] = ENV['INSTALLATION_ID'] if ENV['INSTALLATION_ID']

# Configure the config gem
# Use Object.const_get to ensure the linter doesn't complain about unresolved constants
ConfigGem.setup do |config|
  # Name of the constant exposing loaded settings
  config.const_name = 'Settings'

  # Load environment variables from ENV
  config.use_env = true

  # Prefix for environment variables
  config.env_prefix = 'GCR'

  # What string to use as separator for nested options
  config.env_separator = '_'

  # Convert environment variable values to the proper type
  config.env_converter = :downcase

  # Parse environment variables values as JSON
  config.env_parse_values = true

  # Fail if any required environment variables are missing
  config.fail_on_missing = true
end
