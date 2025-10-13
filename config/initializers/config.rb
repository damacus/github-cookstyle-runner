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

  # Determine environment - default to 'test' if running under RSpec
  default_env = defined?(RSpec) ? 'test' : 'production'
  environment = ENV.fetch('ENVIRONMENT', default_env)
  config_logger.info("Loading configuration for environment: #{environment}")

  # Configure environment variable handling
  # Use a separator that won't conflict with our setting names
  config.use_env = true
  config.env_prefix = 'GCR'
  config.env_separator = '__' # Use double underscore to avoid conflicts
  config.env_converter = :downcase
  config.env_parse_values = false # Don't parse as JSON

  # Don't fail on missing settings - we'll validate what we need later
  config.fail_on_missing = false
end

# Load configuration files using automatic file discovery
# This uses Config.setting_files which automatically loads in priority order:
# 1. config/settings.yml
# 2. config/settings/#{environment}.yml
# 3. config/environments/#{environment}.yml
# 4. config/settings.local.yml (excluded in test)
# 5. config/settings/#{environment}.local.yml (excluded in test)
# 6. config/environments/#{environment}.local.yml (excluded in test)
# Files lower in the list override settings from files higher up
environment = ENV.fetch('ENVIRONMENT', 'production')
config_root = File.join(File.dirname(__FILE__), '..')

# Get the standard setting files and load them
setting_files = ConfigGem.setting_files(config_root, environment)

# In test environment, exclude ALL local.yml files to ensure predictable test behavior
if environment == 'test'
  original_count = setting_files.length
  setting_files = setting_files.reject { |file| file.include?('.local.yml') || file.include?('/local.yml') }
  config_logger.info("Test environment: filtered #{original_count - setting_files.length} local config files")
end

config_logger.info("Loading #{setting_files.length} configuration files for environment: #{environment}")
config_logger.debug("Files: #{setting_files.join(', ')}")
ConfigGem.load_and_set_settings(setting_files)

# Load the validator after config is initialized
require_relative '../validators/settings_validator'

config_logger.debug('Configuration initialization complete')
