# frozen_string_literal: true
# typed: strict

require 'semantic_logger'
require 'sorbet-runtime'

module CookstyleRunner
  # =============================================================================
  # GitHub Cookstyle Runner - Retry with Exponential Backoff
  # =============================================================================
  #
  # This module provides retry logic with exponential backoff for handling
  # GitHub API rate limits and temporary failures.
  #
  module RetryWithBackoff
    extend T::Sig

    # Default exponential backoff sequence in seconds: 1, 2, 4, 8, 16
    DEFAULT_BACKOFF_SEQUENCE = T.let([1, 2, 4, 8, 16], T::Array[Integer])

    # Module-level logger
    @log = T.let(SemanticLogger[self], SemanticLogger::Logger)

    sig { returns(SemanticLogger::Logger) }
    def self.log
      @log
    end

    # Execute a block with exponential backoff retry logic
    # @param max_retries [Integer] Maximum number of retry attempts
    # @param operation_name [String] Name of the operation for logging
    # @param context [Hash] Additional context for logging
    # @param backoff_sequence [Array<Integer>] Custom backoff sequence in seconds
    # @yield The block to execute
    # @return [Object] The result of the block execution
    sig do
      params(
        max_retries: Integer,
        operation_name: String,
        context: T::Hash[Symbol, Object],
        backoff_sequence: T::Array[Integer]
      ).returns(T.anything)
    end
    def self.with_exponential_backoff(max_retries:, operation_name:, context:, backoff_sequence: DEFAULT_BACKOFF_SEQUENCE)
      retries = T.let(0, Integer)

      begin
        yield
      rescue StandardError => e
        if retries < max_retries && should_retry?(e)
          retry_after = extract_retry_after(e, retries, backoff_sequence)

          log_message = if e.message.include?('Rate limit')
                          'Rate limit exceeded, retrying with exponential backoff'
                        else
                          'GitHub server error, retrying with exponential backoff'
                        end

          log.warn(log_message, payload: {
            operation: operation_name,
            attempt: retries + 1,
            max_retries: max_retries,
            delay: retry_after,
            error: e.message
          }.merge(context))

          sleep(retry_after)
          retries += 1
          retry
        else
          log.error('Operation failed after all retries', payload: {
            operation: operation_name,
            max_retries: max_retries,
            total_attempts: retries + 1,
            error: e.message
          }.merge(context))
          raise
        end
      end
    end

    class << self
      private

      # Determine if an error should be retried
      # @param exception [StandardError] The exception to check
      # @return [Boolean] True if the error should be retried
      def should_retry?(exception)
        # Retry rate limit errors and server errors
        exception.message.include?('Rate limit') ||
          exception.message.include?('Server error')
      end

      # Extract retry-after time from response headers or use exponential backoff
      # @param exception [StandardError] The exception
      # @param attempt [Integer] Current attempt number (0-based)
      # @param backoff_sequence [Array<Integer>] Backoff sequence to use
      # @return [Integer] Number of seconds to wait before retry
      def extract_retry_after(exception, attempt, backoff_sequence)
        # First try to use the retry-after header from GitHub
        retry_after_header = (exception.response_headers&.dig('retry-after') if exception.respond_to?(:response_headers))

        if retry_after_header
          retry_after = retry_after_header.to_i
          # Ensure retry_after is reasonable (between 1 and 60 seconds)
          return retry_after.clamp(1, 60)
        end

        # Fall back to exponential backoff sequence
        backoff_sequence[attempt] || backoff_sequence.last
      end
    end
  end
end
