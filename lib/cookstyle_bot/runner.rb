# typed: strict
# frozen_string_literal: true

require 'sorbet-runtime'
require 'json'
require 'tempfile'

module CookstyleBot
  # Runner is responsible for executing Cookstyle on a repository
  # and processing the results.
  # rubocop:disable Metrics/ClassLength
  class Runner
    extend T::Sig

    sig { returns(String) }
    attr_reader :repo_path

    sig { returns(T::Hash[Symbol, T.untyped]) }
    attr_reader :options

    sig { returns(T.nilable(String)) }
    attr_reader :rubocop_output

    sig do
      params(
        repo_path: String,
        options: T::Hash[Symbol, T.untyped]
      ).void
    end
    def initialize(repo_path, options = {})
      @repo_path = repo_path
      @options = {
        auto_correct: options[:auto_correct] || false,
        format: options[:format] || 'json'
      }
      @logger = CookstyleBot::Logging.logger
      @rubocop_output = nil
    end

    sig { returns(T::Hash[Symbol, T.untyped]) }
    def run
      @logger.info("Starting Cookstyle run on #{@repo_path}")

      begin
        # Require cookstyle dynamically to avoid loading it until needed
        require 'cookstyle'

        # Run Cookstyle and capture the result
        runner, output_file = initialize_runner_with_output
        success = runner.run([@repo_path])

        # Read the captured output
        @rubocop_output = File.read(output_file.path) if File.exist?(output_file.path)
        output_file.unlink

        result = build_result(success)

        @logger.info("Completed Cookstyle run on #{@repo_path}")
        result
      rescue StandardError => e
        handle_error(e)
      end
    end

    sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
    def extract_offenses
      return [] if @rubocop_output.nil? || @rubocop_output.empty?

      begin
        parsed_output = JSON.parse(@rubocop_output)
        extract_offenses_from_parsed_output(parsed_output)
      rescue JSON::ParserError => e
        @logger.error("Failed to parse RuboCop JSON output: #{e.message}")
        []
      end
    end

    private

    sig { returns([RuboCop::Runner, Tempfile]) }
    def initialize_runner_with_output
      # Create temporary file for capturing JSON output
      output_file = Tempfile.new(['rubocop_output', '.json'])
      output_file.close

      # Initialize RuboCop runner with JSON formatter
      runner_options = {
        auto_correct: @options[:auto_correct],
        formatters: [[@options[:format], output_file.path]]
      }

      # Load RuboCop configuration
      config = RuboCop::ConfigStore.new
      config.options_config = RuboCop::ConfigLoader.default_configuration

      runner = RuboCop::Runner.new(runner_options, config)
      [runner, output_file]
    end

    sig { returns(RuboCop::Runner) }
    def initialize_runner
      # Initialize RuboCop runner
      runner_options = {
        auto_correct: @options[:auto_correct],
        format: @options[:format]
      }

      # Load RuboCop configuration
      config = RuboCop::ConfigStore.new
      config.options_config = RuboCop::ConfigLoader.default_configuration

      RuboCop::Runner.new(runner_options, config)
    end

    sig { params(success: T::Boolean).returns(T::Hash[Symbol, T.untyped]) }
    def build_result(success)
      {
        success: success,
        offenses: extract_offenses,
        timestamp: Time.now.to_i
      }
    end

    sig { params(error: StandardError).returns(T::Hash[Symbol, T.untyped]) }
    def handle_error(error)
      @logger.error("Error running Cookstyle: #{error.message}")
      @logger.debug(error.backtrace.join("\n"))

      {
        success: false,
        error: error.message,
        backtrace: error.backtrace,
        timestamp: Time.now.to_i
      }
    end

    sig { params(parsed_output: T::Hash[String, T.untyped]).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
    def extract_offenses_from_parsed_output(parsed_output)
      offenses = []

      parsed_output['files']&.each do |file_data|
        file_path = file_data['path']

        file_data['offenses']&.each do |offense_data|
          offense = build_offense_hash(file_path, offense_data)
          offenses << offense
        end
      end

      offenses
    end

    sig { params(file_path: String, offense_data: T::Hash[String, T.untyped]).returns(T::Hash[Symbol, T.untyped]) }
    def build_offense_hash(file_path, offense_data)
      location = offense_data['location'] || {}

      {
        path: file_path,
        line: location['line'] || location['start_line'],
        column: location['column'] || location['start_column'],
        severity: offense_data['severity'],
        cop_name: offense_data['cop_name'],
        message: offense_data['message'],
        corrected: offense_data['corrected'] || false,
        correction: nil, # RuboCop doesn't provide suggested corrections in output
        source: nil # Would need to read from file to get original source
      }
    end
  end
  # rubocop:enable Metrics/ClassLength
end
