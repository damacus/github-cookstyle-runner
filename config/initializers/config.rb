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

# Map critical environment variables so they're accessible in our app
# GitHub token-based auth
ENV['GCR_GITHUB_TOKEN'] = ENV['GITHUB_TOKEN'] if ENV['GITHUB_TOKEN']

# GitHub App-based auth
ENV['GCR_APP_ID'] = ENV['APP_ID'] if ENV['APP_ID']
ENV['GCR_INSTALLATION_ID'] = ENV['INSTALLATION_ID'] if ENV['INSTALLATION_ID']
ENV['GCR_GITHUB_APP_PRIVATE_KEY'] = ENV['GITHUB_APP_PRIVATE_KEY'] if ENV['GITHUB_APP_PRIVATE_KEY']

# Configure the config gem
ConfigGem.setup do |config|
  # Name of the constant exposing loaded settings
  config.const_name = 'Settings'

  # Determine environment
  environment = ENV['COOKSTYLE_ENV'] || 'development'
  
  # Load configuration files according to environment
  config.load_and_set_settings(
    File.join(File.dirname(__FILE__), '..', 'settings', 'default.yml'),
    File.join(File.dirname(__FILE__), '..', 'settings', "#{environment}.yml"),
    File.join(File.dirname(__FILE__), '..', 'settings', 'local.yml')
  )

  # Load environment variables from ENV
  config.use_env = true

  # Prefix for environment variables
  config.env_prefix = 'GCR'

  # What string to use as separator for nested options
  config.env_separator = '_'

  # Convert environment variable values to the proper type
  config.env_converter = :downcase

  # Parse environment variable values as JSON
  config.env_parse_values = true

  # Don't fail on missing env vars - we'll validate what we need later
  config.fail_on_missing = false
end

# Load the validator after config is initialized
require_relative '../validators/settings_validator'
