# frozen_string_literal: true
# typed: true

module CookstyleRunner
  # This class is responsible for reporting the results of the Cookstyle run.
  class Reporter
    extend T::Sig

    T::Sig::WithoutRuntime.sig { params(logger: T.nilable(SemanticLogger::Logger)).void }
    def initialize(logger: nil)
      @logger = logger || SemanticLogger[self.class]
    end

    # Aggregates results from parallel processing
    # @param results [Array<Hash>] Array of result hashes from RepositoryProcessor
    # @return [Array<Integer>] counts for [processed, issues, skipped, errors]
    # rubocop:disable Metrics/MethodLength
    sig { params(results: T::Array[Hash]).returns(T::Array[Integer]) }
    def aggregate_results(results)
      processed_count = 0
      issues_count = 0
      skipped_count = 0
      error_count = 0

      results.each do |result|
        case result[:status]
        when :no_issues
          message = 'No issues in repository'
          processed_count += 1 # Count successful processing without issues
        when :issues_found
          message = 'Cookstyle issues found'
          processed_count += 1
          issues_count += 1
        when :skipped
          message = 'Skipped'
          skipped_count += 1
        when :error
          error_count += 1
          message = 'Repository processing error'
        else
          message = 'Unknown repository status'
          error_count += 1 # Treat unknown status as an error
        end

        @logger.info(message, payload: {
                       status: result[:status],
                       repo_name: result[:repo_name]
                     })
      end
      [processed_count, issues_count, skipped_count, error_count]
    end
    # rubocop:enable Metrics/MethodLength

    # Reports the summary of the application run using structured logging
    # @param total_repos [Integer] Total repositories considered
    # @param processed_count [Integer] Number of repositories processed
    # @param issues_count [Integer] Number of repositories with issues
    # @param skipped_count [Integer] Number of repositories skipped
    # @param error_count [Integer] Number of repositories with errors
    # @param issues_created [Integer] Number of issues created
    # @param prs_created [Integer] Number of pull requests created
    # @param issue_errors [Integer] Number of issue creation errors
    # @param pr_errors [Integer] Number of pull request creation errors
    sig do
      params(total_repos: Integer, processed_count: Integer, issues_count: Integer, skipped_count: Integer, error_count: Integer,
             issues_created: Integer, prs_created: Integer, issue_errors: Integer, pr_errors: Integer).void
    end
    def summary(total_repos:, processed_count:, issues_count: 0, skipped_count: 0, error_count: 0,
                issues_created: 0, prs_created: 0, issue_errors: 0, pr_errors: 0)
      @logger.info('Run summary', payload: {
                     summary: {
                       total_repositories: total_repos, successfully_processed: processed_count,
                       found_issues_in: issues_count, skipped: skipped_count, errors: error_count
                     },
                     artifacts: {
                       issues_created: issues_created, pull_requests_created: prs_created,
                       issue_creation_errors: issue_errors, pr_creation_errors: pr_errors
                     }
                   })
    end

    sig { params(created_artifacts: T::Array[Hash]).void }
    def created_artifacts(created_artifacts:)
      if created_artifacts.any?
        @logger.info('Artifacts created', payload: { artifacts: created_artifacts, count: created_artifacts.size })
      else
        @logger.info('No artifacts created')
      end
    end

    sig { params(artifact_creation_errors: T::Array[Hash]).void }
    def artifact_creation_errors(artifact_creation_errors = [])
      if artifact_creation_errors.any?
        @logger.error('Artifact creation errors', payload: { errors: artifact_creation_errors, count: artifact_creation_errors.size })
      else
        @logger.info('No artifact creation errors')
      end
    end

    # Report cache statistics using structured logging
    # @param stats_hash [Hash] Cache statistics hash
    sig { params(stats_hash: T::Hash[String, T.untyped]).void }
    def cache_stats(stats_hash)
      hits = stats_hash['cache_hits'] || 0
      misses = stats_hash['cache_misses'] || 0
      updates = stats_hash['cache_updates'] || 0
      hit_rate = stats_hash['cache_hit_rate'] || 0.0
      time_saved = stats_hash['estimated_time_saved'] || 0.0
      runtime = stats_hash['runtime'] || 0.0

      @logger.info('Cache statistics',
                   cache_hits: hits,
                   cache_misses: misses,
                   cache_updates: updates,
                   cache_hit_rate: hit_rate,
                   estimated_time_saved: time_saved,
                   runtime: runtime)
    end
  end
end
