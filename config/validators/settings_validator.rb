# frozen_string_literal: true

require 'dry-schema'

module CookstyleRunner
  # Validates the configuration settings using dry-schema
  class SettingsValidator
    # Define the schema for configuration validation
    SCHEMA = Dry::Schema.Params do
      # Required settings
      required(:owner).filled(:string)
      
      # GitHub PR & Issue settings
      required(:branch_name).filled(:string)
      required(:pr_title).filled(:string)
      optional(:issue_labels).array(:string)
      required(:create_manual_fix_issues).filled(:bool)
      
      # GitHub auth settings
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
    end

    # Define a custom validation method
    # @param [Config::Options] config The options to validate
    # @return [Hash] A hash with validation errors (empty if valid)
    def validate(config)
      # Validate against the schema
      result = SCHEMA.call(config.to_h)
      
      # Process the errors
      result.errors.to_h
    end
  end
end
