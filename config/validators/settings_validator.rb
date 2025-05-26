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

      # GitHub PR & Issue settings
      required(:branch_name).filled(:string)
      required(:pr_title).filled(:string)
      optional(:issue_labels).array(:string)
      required(:create_manual_fix_issues).filled(:bool)

      # GitHub auth settings
      optional(:github_token).maybe(:string)
      optional(:github_app_id).maybe(:string)
      optional(:github_app_installation_id).maybe(:string)
      optional(:github_app_private_key).maybe(:string)
      required(:github_api_endpoint).filled(:string)
      optional(:git_name).filled(:string)
      optional(:git_email).filled(:string)
      required(:default_branch).filled(:string)

      # Cache settings
      required(:cache_dir).filled(:string)
      required(:use_cache).filled(:bool)
      required(:cache_max_age).filled(:integer, gt?: 0)
      required(:force_refresh).filled(:bool)

      # Repository settings
      optional(:topics).array(:string)
      optional(:filter_repos).array(:string)

      # Retry settings
      required(:retry_count).filled(:integer, gteq?: 1)

      # Changelog settings
      required(:manage_changelog).filled(:bool)
      required(:changelog_location).filled(:string)
      required(:changelog_marker).filled(:string)

      # Thread count for parallel processing
      required(:thread_count).filled(:integer, gteq?: 1)
    end, T.untyped)

    # Validate configuration settings against the schema
    # @param config [Object] Configuration object to validate
    # @return [Array<String>] Array of validation error messages (empty if validation passes)
    sig { params(config: T.untyped).returns(T::Array[String]) }
    def self.validate(config)
      schema_errors = validate_schema(config)
      auth_errors = validate_auth_requirements(config)

      schema_errors + auth_errors
    end

    # Validate configuration against the schema
    # @param config [Object] Configuration object to validate
    # @return [Array<String>] Array of schema validation errors
    sig { params(config: T.untyped).returns(T::Array[String]) }
    def self.validate_schema(config)
      result = SCHEMA.call(config.to_h)
      format_validation_errors(result.errors.to_h)
    end

    # Format validation errors from Dry::Schema
    # @param errors_hash [Hash] Errors hash from Dry::Schema
    # @return [Array<String>] Formatted error messages
    sig { params(errors_hash: T::Hash[Symbol, T.untyped]).returns(T::Array[String]) }
    def self.format_validation_errors(errors_hash)
      errors_hash.map do |key, messages|
        "#{key}: #{messages.join(', ')}"
      end
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
