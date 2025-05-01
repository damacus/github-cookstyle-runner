#!/usr/bin/env ruby
# frozen_string_literal: true

# =============================================================================
# GitHub Cookstyle Runner - Main Application
# =============================================================================
#
# This is the main entry point for the GitHub Cookstyle Runner application.
# It orchestrates the entire workflow of finding repositories, running
# cookstyle checks, applying fixes, and creating pull requests.

#
# Required environment variables:
#   - GITHUB_TOKEN: Authentication token for GitHub API
#   - GCR_DESTINATION_REPO_OWNER: Target GitHub organization/user
#   - GCR_MANAGE_CHANGELOG: Whether to update changelog (0 or 1)
#
# Optional environment variables:
#   - GCR_DESTINATION_REPO_TOPICS: Repository topics to filter by (comma-separated)
#   - GCR_BRANCH_NAME: Branch name for cookstyle fixes (default: "cookstyle-fixes")
#   - GCR_PULL_REQUEST_TITLE: Title for pull requests (default: "Automated PR: Cookstyle Changes")
#   - GCR_CHANGELOG_LOCATION: Path to changelog file (default: "CHANGELOG.md")
#   - GCR_CHANGELOG_MARKER: Marker in changelog for adding entries (default: "## Unreleased")
#   - GCR_DEBUG_MODE: Enable debug logging (default: 0)
#

require 'English'
require 'logger'
require 'fileutils'
require 'octokit'
require 'json'
require 'open3'
require 'parallel'
require 'pp'

require_relative 'cookstyle_runner/git_operations'
require_relative 'cookstyle_runner/github_api'
require_relative 'cookstyle_runner/repository_manager'
require_relative 'cookstyle_runner/cookstyle_operations'
require_relative 'cookstyle_runner/config_manager'
require_relative 'cookstyle_runner/context_manager'
require_relative 'cookstyle_runner/cache'
require_relative 'cookstyle_runner/github_pr_manager'
require_relative 'cookstyle_runner/repository_processor'
require_relative 'cookstyle_runner/reporter'

# Main application class for GitHub Cookstyle Runner
module CookstyleRunner
  # Main application class for GitHub Cookstyle Runner
  # rubocop:disable Metrics/ClassLength
  class Application
    attr_reader :logger, :config, :cache, :pr_manager, :context_manager

    # Initializes the application with a logger and configuration
    def initialize
      _setup_logger
      _setup_configuration
      _setup_cache
      _setup_context_manager
      _setup_pr_manager
    end

    # Main entry point for the application
    # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
    def run
      # Fetch and filter repositories
      repositories = _fetch_and_filter_repositories
      return 0 if repositories.nil? # Exit if no repositories found

      # --- Parallel Processing ---
      results = _process_repositories_in_parallel(repositories)

      # Process the collected results sequentially after parallel execution
      reporter = CookstyleRunner::Reporter.new(@logger)
      processed_count, issues_found_count, skipped_count, error_count = reporter.aggregate_results(results)

      # --- Calculations for summary reporting ---
      @created_artifacts = []
      @artifact_creation_errors = []
      issues_created_count = @created_artifacts.count { |a| a[:type] == 'issue' }
      prs_created_count = @created_artifacts.count { |a| a[:type] == 'pull' }
      issue_errors_count = @artifact_creation_errors.count { |e| e[:type] == 'issue' }
      pr_errors_count = @artifact_creation_errors.count { |e| e[:type] == 'pull' }
      # ------------------------------------------------------- #

      # Report summary
      reporter.summary(
        total_repos: repositories.length,
        processed_count: processed_count,
        issues_count: issues_found_count,
        issues_created: issues_created_count,
        skipped_count: skipped_count,
        error_count: error_count,
        prs_created: prs_created_count,
        issue_errors: issue_errors_count,
        pr_errors: pr_errors_count
      )

      # Log cache runtime statistics if cache is enabled
      if @config[:use_cache] && @cache_manager&.stats
        # Call instance method on the stats object within cache_manager
        stats_hash = @cache_manager.stats.runtime_stats
        @logger.info("Cache Stats:\n#{PP.pp(stats_hash, +'')}")
      end

      # Report created artifacts
      reporter.created_artifacts(created_artifacts: @created_artifacts)
      # Report artifact creation errors
      reporter.artifact_creation_error(@artifact_creation_errors)

      # Return appropriate exit code (e.g., non-zero if errors occurred)
      error_count.zero? && @artifact_creation_errors.empty? ? 0 : 1
    end
    # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity

    private

    # Sets up the application logger
    def _setup_logger
      log_level_str = ENV.fetch('GCR_LOG_LEVEL', 'INFO').upcase
      log_level = begin
        Logger.const_get(log_level_str)
      rescue NameError
        logger&.warn("Invalid GCR_LOG_LEVEL '#{log_level_str}', defaulting to INFO.")
        Logger::INFO
      end
      @logger = Logger.new($stdout, level: log_level)
      logger.info("Log level set to: #{log_level_str}") # Log the *requested* level for clarity
    end

    def _setup_configuration
      @config = ConfigManager.load_config(logger)
    end

    def _setup_cache
      @cache = Cache.new(@config[:cache_dir], logger)
    end

    def _setup_context_manager
      @context_manager = ContextManager.instance
      @context_manager.set_global_config(@config, @logger)
    end

    def _setup_pr_manager
      @pr_manager = GitHubPRManager.new(@config, @logger)
    end

    # Fetches repositories from GitHub and applies filtering based on config
    # @return [Array<String>, nil] List of repository URLs or nil if none found/matched
    # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    def _fetch_and_filter_repositories
      # Use the GitHubAPI module to fetch repositories
      repositories = GitHubAPI.fetch_repositories(
        @config[:owner],
        @config[:topics],
        logger
      )

      if repositories.empty?
        logger.warn('No repositories found matching the initial criteria.')
        return nil
      end

      initial_count = repositories.length

      # Apply repository filtering if specified using the RepositoryManager module
      if @config[:filter_repos] && !@config[:filter_repos].empty?
        filtered_repos = RepositoryManager.filter_repositories(repositories, @config[:filter_repos], logger)
        logger.info("Filtered from #{initial_count} to #{filtered_repos.length} repositories based on include/exclude lists.")
        repositories = filtered_repos
      end

      if repositories.empty?
        logger.warn('No repositories remaining after filtering. Exiting.')
        return nil
      end

      logger.info("Found #{repositories.length} repositories to process.")
      repositories # Return the final list
    end
    # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

    # Process repositories in parallel
    def _process_repositories_in_parallel(repositories)
      total_repos = repositories.length
      thread_count = [@config[:thread_count], total_repos].min
      logger.info("Processing #{total_repos} repositories using #{thread_count} threads")

      # Instantiate a single RepositoryProcessor for all threads
      repo_processor = RepositoryProcessor.new(
        config: @config,
        logger: logger,
        cache_manager: @cache,
        pr_manager: @pr_manager,
        context_manager: @context_manager
      )

      # Process repositories in parallel using Parallel.map to collect results
      Parallel.map(repositories.each_with_index, in_threads: thread_count) do |repo_url, index|
        # Calculate current count for logging (1-based index)
        current_log_count = index + 1

        # Delegate all per-repository processing to RepositoryProcessor
        # process_repository now returns a hash
        repo_processor.process_repository(repo_url, current_log_count, total_repos)
      end
    end
  end
  # rubocop:enable Metrics/ClassLength

  # Run the application if this file is executed directly
  if __FILE__ == $PROGRAM_NAME
    runner = CookstyleRunner::Application.new
    exit runner.run
  end
end
