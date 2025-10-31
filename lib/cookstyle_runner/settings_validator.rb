# frozen_string_literal: true
# typed: true

require 'dry-schema'

module CookstyleRunner
  # Validates application settings using dry-schema
  class SettingsValidator
    class << self
      # Validate the settings object against our schema
      # @param settings [Object] The settings object to validate
      # @return [Array<String>] Array of error messages (empty if valid)
      def validate(settings)
        settings_hash = settings.to_h
        # Convert symbol keys to strings for Dry::Schema::Params
        settings_hash = settings_hash.transform_keys(&:to_s)

        # Debug output
        if ENV['DEBUG']
          warn "Settings hash keys: #{settings_hash.keys.inspect}"
          warn "Settings hash: #{settings_hash.inspect}"
        end

        result = schema.call(settings_hash)

        if result.success?
          []
        else
          format_errors(result.errors.to_h)
        end
      end

      private

      # Format error messages into readable strings
      # @param errors [Hash] The validation errors
      # @return [Array<String>] Array of formatted error messages
      def format_errors(errors)
        errors.map do |key, messages|
          "#{key}: #{Array(messages).join(', ')}"
        end
      end

      # Define the validation schema
      # @return [Dry::Schema::Params] The schema object
      def schema
        # We need to use Dry::Schema directly here - Sorbet can't track methods
        # inside a DSL block, so we disable type checking for this file
        Dry::Schema.Params do
          # Required settings
          required(:owner).filled(:string)

          # GitHub PR & Issue settings
          required(:branch_name).filled(:string)
          required(:pr_title).filled(:string)
          optional(:issue_labels).array(:string)
          required(:create_manual_fix_issues).filled(:bool)
          required(:auto_assign_manual_fixes).filled(:bool)
          optional(:copilot_assignee).filled(:string)

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

          # Thread count for parallel processing
          required(:thread_count).filled(:integer, gteq?: 1)

          # Output format
          optional(:output_format).filled(:string, included_in?: %w[text table json])
        end
      end
    end
  end
end
