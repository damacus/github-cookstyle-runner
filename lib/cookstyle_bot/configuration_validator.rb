# typed: strict
# frozen_string_literal: true

require 'sorbet-runtime'
require 'config'

module CookstyleBot
  # ConfigurationError is raised when there's an issue with the configuration
  class ConfigurationError < StandardError; end

  # ConfigurationValidator validates the application configuration
  # rubocop:disable Metrics/ClassLength
  # TODO: Refactor this class
  class ConfigurationValidator
    extend T::Sig

    # Schema defines the expected structure and types of the configuration
    SCHEMA = {
      logging: {
        level: { type: :string, required: false, allowed_values: %w[DEBUG INFO WARN ERROR FATAL] },
        output: { type: :string, required: false, allowed_values: %w[stdout stderr file] }
      },
      github: {
        api_root: { type: :string, required: false },
        token: { type: :string, required: true },
        destination_repo_owner: { type: :string, required: true },
        destination_repo_topics_csv: { type: :string, required: true },
        branch_name: { type: :string, required: false },
        default_git_branch: { type: :string, required: false },
        pull_request: {
          title: { type: :string, required: false },
          labels: { type: :string, required: false },
          body_header: { type: :string, required: false },
          body_topic_template: { type: :string, required: false }
        }
      },
      git: {
        name: { type: :string, required: false },
        email: { type: :string, required: false }
      },
      changelog: {
        location: { type: :string, required: false },
        marker: { type: :string, required: false },
        manage: { type: :boolean, required: false }
      },
      cookstyle: {
        version_check_regex: { type: :string, required: false }
      }
    }.freeze

    sig { void }
    def initialize
      @errors = T.let([], T::Array[String])
    end

    sig { returns(T::Boolean) }
    def valid?
      validate
      @errors.empty?
    end

    sig { returns(T::Array[String]) }
    attr_reader :errors

    sig { void }
    def validate!
      validate
      return if @errors.empty?

      error_message = "Configuration validation failed:\n"
      error_message += @errors.map { |e| "  - #{e}" }.join("\n")
      raise ConfigurationError, error_message
    end

    private

    sig { returns(T::Boolean) }
    def validate
      @errors = []
      validate_schema(Settings.to_hash, SCHEMA)
      validate_combinations
      @errors.empty?
    end

    sig { params(config: T::Hash[T.untyped, T.untyped], schema: T::Hash[T.untyped, T.untyped], path: String).void }
    def validate_schema(config, schema, path = '')
      schema.each do |key, definition|
        current_path = path.empty? ? key.to_s : "#{path}.#{key}"

        if definition.is_a?(Hash) && !definition.key?(:type)
          # This is a nested schema
          if !config.key?(key) || !config[key].is_a?(Hash)
            @errors << "Missing or invalid section: #{current_path}"
            next
          end
          validate_schema(config[key], definition, current_path)
        else
          # This is a field definition
          validate_field(config, key, definition, current_path)
        end
      end
    end

    # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    # TODO: Refactor this method
    sig do
      params(config: T::Hash[T.untyped, T.untyped], key: T.untyped, definition: T::Hash[T.untyped, T.untyped],
             path: String).void
    end
    def validate_field(config, key, definition, path)
      # Check if required field is present
      if definition[:required] && (!config.key?(key) || config[key].nil?)
        @errors << "Missing required configuration: #{path}"
        return
      end

      # Skip validation if field is not present and not required
      return unless config.key?(key) && !config[key].nil?

      # Validate type
      case definition[:type]
      when :string
        @errors << "#{path} must be a string" unless config[key].is_a?(String)
      when :integer
        @errors << "#{path} must be an integer" unless config[key].is_a?(Integer)
      when :boolean
        @errors << "#{path} must be a boolean" unless [true, false].include?(config[key])
      when :array
        @errors << "#{path} must be an array" unless config[key].is_a?(Array)
      end

      # Validate allowed values if specified
      return unless definition[:allowed_values] && !definition[:allowed_values].include?(config[key])

      @errors << "#{path} must be one of: #{definition[:allowed_values].join(', ')}"
    end
    # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

    sig { void }
    def validate_combinations
      # Example: validate that if changelog.manage is true, changelog.location and changelog.marker are set
      if Settings.changelog.manage && (Settings.changelog.location.empty? || Settings.changelog.marker.empty?)
        @errors << 'When changelog.manage is true, changelog.location and changelog.marker must be set'
      end

      # Add more combination validations as needed
    end
  end
  # rubocop:enable Metrics/ClassLength
end
