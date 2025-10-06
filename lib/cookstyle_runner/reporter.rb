# frozen_string_literal: true
# typed: true

module CookstyleRunner
  # This class is responsible for reporting the results of the Cookstyle run.
  class Reporter
    extend T::Sig

    def initialize(logger, format: 'text')
      @logger = logger
      @format = format
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
          processed_count += 1 # Count successful processing without issues
        when :issues_found
          processed_count += 1
          issues_count += 1
        when :skipped
          skipped_count += 1
        when :error
          error_count += 1
          @logger.error("Error occurred processing repository: #{result[:repo_name]}. Message: #{result[:error_message]}")
        else
          @logger.warn("Unknown status '#{result[:status]}' received for repository: #{result[:repo_name]}")
          error_count += 1 # Treat unknown status as an error
        end
      end
      [processed_count, issues_count, skipped_count, error_count]
    end
    # rubocop:enable Metrics/MethodLength

    # Reports the summary of the application run
    # @param total_repos [Integer] Total repositories considered
    # @param processed_count [Integer] Number of repositories processed
    # @param issues_count [Integer] Number of repositories with issues
    # @param skipped_count [Integer] Number of repositories skipped
    # @param error_count [Integer] Number of repositories with errors
    # @param issues_created [Integer] Number of issues created
    # @param prs_created [Integer] Number of pull requests created
    # @param issue_errors [Integer] Number of issue creation errors
    # @param pr_errors [Integer] Number of pull request creation errors
    # @return [String] Summary report
    sig do
      params(total_repos: Integer, processed_count: Integer, issues_count: Integer, skipped_count: Integer, error_count: Integer,
             issues_created: Integer, prs_created: Integer, issue_errors: Integer, pr_errors: Integer).returns(String)
    end
    def summary(total_repos:, processed_count:, issues_count: 0, skipped_count: 0, error_count: 0,
                issues_created: 0, prs_created: 0, issue_errors: 0, pr_errors: 0)
      case @format
      when 'table'
        summary_table(total_repos, processed_count, issues_count, skipped_count, error_count,
                      issues_created, prs_created, issue_errors, pr_errors)
      when 'json'
        summary_json(total_repos, processed_count, issues_count, skipped_count, error_count,
                     issues_created, prs_created, issue_errors, pr_errors)
      else
        summary_text(total_repos, processed_count, issues_count, skipped_count, error_count,
                     issues_created, prs_created, issue_errors, pr_errors)
      end
    end

    def summary_text(total_repos, processed_count, issues_count, skipped_count, error_count,
                     issues_created, prs_created, issue_errors, pr_errors)
      summary = <<~SUMMARY

        --- Summary ---
        Total repositories considered: #{total_repos}
        Successfully processed: #{processed_count}
        Found issues in: #{issues_count} repositories.
        Skipped: #{skipped_count} repositories.
        Errors: #{error_count} repositories.

        --- Artifact Creation ---
        Issues Created: #{issues_created}
        Pull Requests Created: #{prs_created}
        Issue Creation Errors: #{issue_errors}
        PR Creation Errors: #{pr_errors}
      SUMMARY
      @logger.info(summary)
      summary
    end

    def summary_table(total_repos, processed_count, issues_count, skipped_count, error_count,
                      issues_created, prs_created, issue_errors, pr_errors)
      require_relative 'table_renderer'
      summary_data = {
        'Total Repositories' => total_repos,
        'Successfully Processed' => processed_count,
        'Found Issues In' => "#{issues_count} repositories",
        'Skipped' => "#{skipped_count} repositories",
        'Errors' => "#{error_count} repositories"
      }
      artifact_data = {
        'Issues Created' => issues_created,
        'Pull Requests Created' => prs_created,
        'Issue Creation Errors' => issue_errors,
        'PR Creation Errors' => pr_errors
      }
      output = "\n#{TableRenderer.render_summary(summary_data)}"
      output += "\n#{TableRenderer.render_summary(artifact_data)}"
      @logger.info(output)
      output
    end

    def summary_json(total_repos, processed_count, issues_count, skipped_count, error_count,
                     issues_created, prs_created, issue_errors, pr_errors)
      require 'json'
      data = {
        summary: {
          total_repositories: total_repos,
          successfully_processed: processed_count,
          found_issues_in: issues_count,
          skipped: skipped_count,
          errors: error_count
        },
        artifacts: {
          issues_created: issues_created,
          pull_requests_created: prs_created,
          issue_creation_errors: issue_errors,
          pr_creation_errors: pr_errors
        }
      }
      output = JSON.pretty_generate(data)
      @logger.info(output)
      output
    end

    sig { params(created_artifacts: T::Array[Hash]).returns(T::Array[String]) }
    def created_artifacts(created_artifacts:)
      report = ["--- Created Artifacts (#{created_artifacts.size}) ---"]

      created_artifacts.each do |artifact|
        report << <<~ARTIFACT_ENTRY
          Repository: #{artifact[:repo]}
          Artifact ##{artifact[:number]}: #{artifact[:title]}
          Type: #{artifact[:type]}
          URL: #{artifact[:url]}
        ARTIFACT_ENTRY
      end

      if created_artifacts.any?
        @logger.info(report.join("\n").strip)
      else
        @logger.info('No artifacts were created during this run.')
      end

      report
    end

    sig { params(artifact_creation_errors: T::Array[Hash]).returns(T::Array[String]) }
    def artifact_creation_errors(artifact_creation_errors = [])
      report = ["--- Artifact Creation Errors (#{artifact_creation_errors.size}) ---"]
      artifact_creation_errors.each do |error|
        report << <<~ARTIFACT_ERROR_ENTRY
          Repository: #{error[:repo]}
          Error: #{error[:message]}
          Type: #{error[:type]}
        ARTIFACT_ERROR_ENTRY
      end
      if artifact_creation_errors.any?
        @logger.info(report.join("\n").strip)
      else
        @logger.info('No artifact creation errors were reported.')
      end

      report
    end

    # Report cache statistics
    # @param stats_hash [Hash] Cache statistics hash
    # @return [String] Formatted cache stats
    def cache_stats(stats_hash)
      case @format
      when 'table'
        cache_stats_table(stats_hash)
      when 'json'
        cache_stats_json(stats_hash)
      else
        cache_stats_text(stats_hash)
      end
    end

    def cache_stats_text(stats_hash)
      @logger.info('') # Empty line for spacing
      output = "Cache Stats:\n"
      stats_hash.each do |key, value|
        output += "  #{key}: #{value}\n"
      end
      @logger.info(output.strip)
      output
    end

    def cache_stats_table(stats_hash)
      require_relative 'table_renderer'
      formatted_stats = {
        'Cache Hits' => stats_hash['cache_hits'] || 0,
        'Cache Misses' => stats_hash['cache_misses'] || 0,
        'Cache Updates' => stats_hash['cache_updates'] || 0,
        'Cache Hit Rate' => "#{stats_hash['cache_hit_rate'] || 0}%",
        'Time Saved (est.)' => "#{stats_hash['estimated_time_saved'] || 0}s",
        'Runtime' => "#{stats_hash['runtime'] || 0}s"
      }
      output = "\n#{TableRenderer.render_summary(formatted_stats)}"
      @logger.info(output)
      output
    end

    def cache_stats_json(stats_hash)
      require 'json'
      output = "\n#{JSON.pretty_generate(cache_stats: stats_hash)}"
      @logger.info(output)
      output
    end
  end
end
