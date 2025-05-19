# typed: strict
# frozen_string_literal: true

require 'sorbet-runtime'

module CookstyleBot
  # Runner is responsible for executing Cookstyle on a repository
  # and processing the results.
  class Runner
    extend T::Sig

    sig { returns(String) }
    attr_reader :repo_path

    sig { returns(T::Hash[Symbol, T.untyped]) }
    attr_reader :options

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
    end

    sig { returns(T::Hash[Symbol, T.untyped]) }
    def run
      @logger.info("Starting Cookstyle run on #{@repo_path}")

      begin
        # Require cookstyle dynamically to avoid loading it until needed
        require 'cookstyle'

        # Run Cookstyle and capture the result
        runner = initialize_runner
        success = runner.run([@repo_path])
        result = build_result(success)

        @logger.info("Completed Cookstyle run on #{@repo_path}")
        result
      rescue StandardError => e
        handle_error(e)
      end
    end

    private

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

    sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
    def extract_offenses
      # In a real implementation, this would parse the output from RuboCop
      # and extract information about each offense.
      #
      # For now, we'll return an empty array since we're mocking this in tests
      # Until we have a better understanding of how to extract this information
      # from the RuboCop API.

      [] # Placeholder for now
    end
  end
end
