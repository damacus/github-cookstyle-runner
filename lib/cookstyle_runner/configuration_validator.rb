# frozen_string_literal: true
# typed: strict

require 'sorbet-runtime'
require 'logger'

module CookstyleRunner
  # Validator for configuration settings
  class ConfigurationValidator
    extend T::Sig

    # @param logger [Logger, Object] Logger instance or test double
    sig { params(logger: T.any(Logger, T.untyped)).void }
    def initialize(logger)
      @logger = T.let(logger, T.any(Logger, T.untyped))
    end

    # Validates that all required environment variables are present
    # @return [void]
    sig { void }
    def validate_required_env_vars
      validate_github_auth
      validate_owner

      # If we get here, all validations have passed
      @logger.info('All required environment variables are present')
    end

    # Validate GitHub authentication variables
    # @return [void]
    # @raise [ArgumentError] if GitHub authentication is missing
    sig { void }
    def validate_github_auth
      github_token = ENV.fetch('GITHUB_TOKEN', nil)
      return unless github_token.nil? || github_token.empty?

      # If GitHub token is missing, check all GitHub App variables are present
      app_id = ENV.fetch('GITHUB_APP_ID', nil)
      installation_id = ENV.fetch('GITHUB_APP_INSTALLATION_ID', nil)
      private_key = ENV.fetch('GITHUB_APP_PRIVATE_KEY', nil)

      # Check if some but not all are present
      if ((app_id.nil? || app_id.empty?) && ((!installation_id.nil? && !installation_id.empty?) || (!private_key.nil? && !private_key.empty?))) ||
         ((installation_id.nil? || installation_id.empty?) && ((!app_id.nil? && !app_id.empty?) || (!private_key.nil? && !private_key.empty?))) ||
         ((private_key.nil? || private_key.empty?) && ((!app_id.nil? && !app_id.empty?) || (!installation_id.nil? && !installation_id.empty?)))
        error_msg = 'All three GitHub App credentials (GITHUB_APP_ID, GITHUB_APP_INSTALLATION_ID, ' \
                    'and GITHUB_APP_PRIVATE_KEY) are required when using GitHub App authentication'
        @logger.error(error_msg)
        raise ArgumentError, error_msg
      end

      # Now check if all are missing
      if app_id.nil? || app_id.empty? || installation_id.nil? || installation_id.empty? ||
         private_key.nil? || private_key.empty?
        error_msg = 'Either GITHUB_TOKEN or all GitHub App credentials ' \
                    '(GITHUB_APP_ID, GITHUB_APP_INSTALLATION_ID, and GITHUB_APP_PRIVATE_KEY) are required'
        @logger.error(error_msg)
        raise ArgumentError, error_msg
      end

      # If we reach here, all GitHub App variables are present
      @logger.info('Using GitHub App authentication')
    end

    # Validate GitHub App ID
    # @return [void]
    # @raise [ArgumentError] if GitHub App ID is missing
    sig { void }
    def validate_github_app_id
      app_id = ENV.fetch('GITHUB_APP_ID', nil)
      return unless app_id.nil? || app_id.empty?

      @logger.error('GITHUB_APP_ID environment variable is required when GITHUB_TOKEN is not set')
      raise ArgumentError, 'GITHUB_APP_ID environment variable is required when GITHUB_TOKEN is not set'
    end

    # Validate GitHub App Installation ID
    # @return [void]
    # @raise [ArgumentError] if GitHub App Installation ID is missing
    sig { void }
    def validate_github_app_installation_id
      installation_id = ENV.fetch('GITHUB_APP_INSTALLATION_ID', nil)
      return unless installation_id.nil? || installation_id.empty?

      @logger.error('GITHUB_APP_INSTALLATION_ID environment variable is required when GITHUB_TOKEN is not set')
      raise ArgumentError, 'GITHUB_APP_INSTALLATION_ID environment variable is required when GITHUB_TOKEN is not set'
    end

    # Validate GitHub App Private Key
    # @return [void]
    # @raise [ArgumentError] if GitHub App Private Key is missing
    sig { void }
    def validate_github_app_private_key
      private_key = ENV.fetch('GITHUB_APP_PRIVATE_KEY', nil)
      return unless private_key.nil? || private_key.empty?

      @logger.error('GITHUB_APP_PRIVATE_KEY environment variable is required when GITHUB_TOKEN is not set')
      raise ArgumentError, 'GITHUB_APP_PRIVATE_KEY environment variable is required when GITHUB_TOKEN is not set'
    end

    # Validate destination repository owner
    # @return [void]
    # @raise [ArgumentError] if repository owner is missing
    sig { void }
    def validate_owner
      owner = ENV.fetch('GCR_DESTINATION_REPO_OWNER', nil)
      return unless owner.nil? || owner.empty?

      @logger.error('GCR_DESTINATION_REPO_OWNER environment variable is required')
      raise ArgumentError, 'GCR_DESTINATION_REPO_OWNER environment variable is required'
    end

    # Validates if a string value represents a boolean
    # @param value [String] the value to check
    # @return [Boolean] whether the value is truthy
    sig { params(value: T.nilable(String)).returns(T::Boolean) }
    def validate_boolean_env_var(value)
      return false if value.nil? || value.empty?

      # Check for common truthy values
      %w[1 true yes].include?(value.downcase)
    end

    # Validates if a string value represents an integer
    # @param value [String] the value to check
    # @param default [Integer] default value to return if value is not an integer
    # @return [Integer] the integer value or default
    sig { params(value: T.nilable(String), default: Integer).returns(Integer) }
    def validate_integer_env_var(value, default = 0)
      return default if value.nil? || value.empty?

      begin
        Integer(value)
      rescue ArgumentError
        default
      end
    end
  end
end
