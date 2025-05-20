# typed: strict
# frozen_string_literal: true

require 'config'
require 'sorbet-runtime'

module CookstyleBot
  # Load and set the Settings object using the config gem's recommended pattern.
  config_root = File.expand_path('../../config', __dir__)
  current_env = ENV.fetch('APP_ENV', nil)
  Config.load_and_set_settings(Config.setting_files(config_root, current_env))

  # Configuration module provides methods for accessing and validating application settings
  module Configuration
    extend T::Sig

    class << self
      extend T::Sig

      sig { returns(T::Boolean) }
      def validate!
        validator = ConfigurationValidator.new
        validator.validate!
        true
      end

      sig { returns(T::Array[String]) }
      def validation_errors
        validator = ConfigurationValidator.new
        validator.valid? # Run validation
        validator.errors
      end

      sig { returns(T::Boolean) }
      def valid?
        ConfigurationValidator.new.valid?
      end

      sig { returns(String) }
      def github_token
        Settings.github.token
      end

      sig { returns(String) }
      def github_api_root
        Settings.github.api_root
      end

      sig { returns(String) }
      def log_level
        Settings.logging.level
      end

      sig { returns(String) }
      def log_output
        Settings.logging.output
      end

      # Add more typed accessors for commonly used configuration values
    end
  end
end

# Load the validator after defining the Configuration module
require_relative 'configuration_validator'
