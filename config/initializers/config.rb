# frozen_string_literal: true
# typed: true

begin
  require 'pathname'
  require 'config'
  require 'dry-schema'
  require 'logger'
  # Create a local reference to the Config constant to avoid lint issues
  # Use Object.const_get to help Sorbet understand this constant resolution
  ConfigGem = Object.const_get('Config')
rescue LoadError => e
  raise "Required gem not available: #{e.message}. Please run bundle install."
end

# Initialize logger for configuration debugging
config_logger = Logger.new($stdout)
config_logger.level = ENV['DEBUG'] ? Logger::DEBUG : Logger::INFO

# Helper method to map external environment variables to GCR-prefixed ones
# This ensures consistent access pattern through Settings
def map_github_token(logger = nil)
  return unless ENV.fetch('GITHUB_TOKEN', nil)

  ENV['GCR_GITHUB_TOKEN'] = ENV.fetch('GITHUB_TOKEN', nil)
  logger&.debug('Mapped GITHUB_TOKEN to GCR_GITHUB_TOKEN')
end

def map_github_app_vars(logger = nil)
  # Map GitHub App ID
  if ENV.fetch('APP_ID', nil)
    ENV['GCR_APP_ID'] = ENV.fetch('APP_ID', nil)
    logger&.debug('Mapped APP_ID to GCR_APP_ID')
  end

  # Map Installation ID
  if ENV.fetch('INSTALLATION_ID', nil)
    ENV['GCR_INSTALLATION_ID'] = ENV.fetch('INSTALLATION_ID', nil)
    logger&.debug('Mapped INSTALLATION_ID to GCR_INSTALLATION_ID')
  end

  # Map Private Key
  return unless ENV.fetch('GITHUB_APP_PRIVATE_KEY', nil)

  ENV['GCR_GITHUB_APP_PRIVATE_KEY'] = ENV.fetch('GITHUB_APP_PRIVATE_KEY', nil)
  logger&.debug('Mapped GITHUB_APP_PRIVATE_KEY to GCR_GITHUB_APP_PRIVATE_KEY')
end

# Main function to map all environment variables
# This is used by both the initializer and tests
def map_environment_variables(logger = nil)
  map_github_token(logger)
  map_github_app_vars(logger)
  logger&.debug('Mapped all environment variables')
  true
end
# Apply environment variable mapping
map_environment_variables(config_logger)

# Configure the config gem
ConfigGem.setup do |config|
  # Name of the constant exposing loaded settings
  config.const_name = 'Settings'

  # Determine environment
  environment = ENV.fetch('COOKSTYLE_ENV', 'development')
  config_logger.info("Loading configuration for environment: #{environment}")

  # Define configuration files to load with proper precedence
  # 1. Default settings (always loaded)
  # 2. Environment-specific settings (development, test, production)
  # 3. Local settings override (optional, for development)
  settings_files = [
    File.join(File.dirname(__FILE__), '..', 'settings', 'default.yml'),
    File.join(File.dirname(__FILE__), '..', 'settings', "#{environment}.yml")
  ]

  # Only include local.yml if it exists (optional developer overrides)
  local_config = File.join(File.dirname(__FILE__), '..', 'settings', 'local.yml')
  settings_files << local_config if File.exist?(local_config)

  # Configure environment variable handling
  # Use a separator that won't conflict with our setting names
  config.use_env = true
  config.env_prefix = 'GCR'
  config.env_separator = '__' # Use double underscore to avoid conflicts
  config.env_converter = :downcase
  config.env_parse_values = false # Don't parse as JSON

  # Don't fail on missing settings - we'll validate what we need later
  config.fail_on_missing = false

  # Log which files are being loaded
  settings_files.each do |file|
    if File.exist?(file)
      config_logger.debug("Loading configuration file: #{file}")
    else
      config_logger.warn("Configuration file not found: #{file}")
    end
  end

  # Load the configuration files
  config.load_and_set_settings(*settings_files)
end

# Load the validator after config is initialized
require_relative '../validators/settings_validator'

config_logger.debug('Configuration initialization complete')
