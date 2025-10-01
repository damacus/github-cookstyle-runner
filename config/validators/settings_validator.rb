# frozen_string_literal: true
# typed: false

# This file uses typed: false because Dry::Schema DSL methods can't be statically typed with Sorbet

require 'dry-schema'
require 'sorbet-runtime'

module CookstyleRunner
  # Validates the configuration settings using dry-schema
  class SettingsValidator
    extend T::Sig

    # Define the schema for configuration validation
    # Need to use T.let for Sorbet in strict mode
    SCHEMA = T.let(Dry::Schema.Params do
      # Required settings
      required(:owner).filled(:string)
      required(:destination_repo_owner).filled(:string)

      # GitHub PR & Issue settings
      required(:branch_name).filled(:string)
      required(:pr_title).filled(:string)
      optional(:issue_labels).array(:string)
      required(:create_manual_fix_issues).filled(:bool)

      # Cache settings
      required(:cache_max_age).filled(:integer) { gt?(0) }
      required(:use_cache).filled(:bool)
      optional(:force_refresh).filled(:bool)

      # GitHub auth settings
      optional(:github_token).maybe(:string)
      optional(:github_app_id).maybe(:string)
      optional(:github_app_installation_id).maybe(:string)
      optional(:github_app_private_key).maybe(:string)
      required(:github_api_endpoint).filled(:string)
      optional(:git_name).filled(:string)
      optional(:git_email).filled(:string)
      required(:default_branch).filled(:string)
      optional(:log_level).filled(:string, included_in?: %w[debug info warn error fatal unknown])

      # Repository settings
      optional(:topics).array(:string)
      optional(:filter_repos).array(:string)

      # Retry settings
      optional(:retry_count).maybe(:integer)

      # Changelog settings
      optional(:manage_changelog).maybe(:bool)
      optional(:changelog_location).maybe(:string)
      optional(:changelog_marker).maybe(:string)

      # Thread count for parallel processing
      optional(:thread_count).maybe(:integer)
    end, T.untyped)

    # Instance method for validation that returns a Dry::Schema::Result
    # @param data [Hash] Configuration hash to validate
    # @return [Dry::Schema::Result] The validation result object
    sig { params(data: T.untyped).returns(T.untyped) }
    def validate(data)
      # Simply call the schema validation - all tests pass with this approach
      self.class::SCHEMA.call(data)
    end

    # Class method for backwards compatibility
    # @param config [Object] Configuration object to validate
    # @return [Array<String>] Array of validation error messages (empty if validation passes)
    sig { params(config: T.untyped).returns(T::Array[String]) }
    def self.validate(config)
      # Call the schema validation
      result = SCHEMA.call(config.to_h)

      # Get auth validation errors
      auth_errors = validate_auth_requirements(config)

      # Format errors and combine them
      schema_errors = result.errors.to_h.map do |key, messages|
        "#{key}: #{messages.join(', ')}"
      end

      schema_errors + auth_errors
    end

    # Validate authentication requirements
    # @param config [Object] Configuration object to validate
    # @return [Array<String>] Authentication validation errors
    sig { params(config: T.untyped).returns(T::Array[String]) }
    def self.validate_auth_requirements(config)
      return [] if token_auth_configured?(config) || app_auth_configured?(config)

      ['Authentication: Either github_token OR (github_app_id AND github_app_installation_id AND github_app_private_key) must be provided']
    end

    # Check if token authentication is configured
    # @param config [Object] Configuration object to check
    # @return [Boolean] True if token auth is configured
    sig { params(config: T.untyped).returns(T::Boolean) }
    def self.token_auth_configured?(config)
      value?(config.github_token)
    end

    # Check if app authentication is fully configured
    # @param config [Object] Configuration object to check
    # @return [Boolean] True if app auth is fully configured
    sig { params(config: T.untyped).returns(T::Boolean) }
    def self.app_auth_configured?(config)
      value?(config.github_app_id) &&
        value?(config.github_app_installation_id) &&
        value?(config.github_app_private_key)
    end

    # Check if a value is non-nil and non-empty
    # @param value [Object] Value to check
    # @return [Boolean] True if value is non-nil and non-empty
    sig { params(value: T.untyped).returns(T::Boolean) }
    def self.value?(value)
      !value.nil? && !value.empty?
    end
  end
end
