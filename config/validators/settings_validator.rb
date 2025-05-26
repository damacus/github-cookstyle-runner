# frozen_string_literal: true
# typed: true

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

    # Class method to validate configuration
    # @param [Config::Options] config The options to validate
    # @return [Array<String>] Array of validation error messages (empty if valid)
    sig { params(config: T.untyped).returns(T::Array[String]) }
    def self.validate(config)
      # Extract authentication settings for validation
      github_token = config.github_token
      github_app_id = config.github_app_id
      github_app_installation_id = config.github_app_installation_id
      github_app_private_key = config.github_app_private_key

      # Check if token auth is configured
      has_token = !github_token.nil? && !github_token.empty?

      # Check if app auth is configured (all three parts required)
      has_app_id = !github_app_id.nil? && !github_app_id.empty?
      has_installation_id = !github_app_installation_id.nil? && !github_app_installation_id.empty?
      has_private_key = !github_app_private_key.nil? && !github_app_private_key.empty?
      has_app_auth = has_app_id && has_installation_id && has_private_key

      # Validate against the schema
      result = SCHEMA.call(config.to_h)

      # Process the errors
      errors = result.errors.to_h.map do |key, messages|
        "#{key}: #{messages.join(', ')}"
      end

      # Add auth validation
      unless has_token || has_app_auth
        errors << 'Authentication: Either github_token OR (github_app_id AND github_app_installation_id AND github_app_private_key) must be provided'
      end

      errors
    end
  end
end
