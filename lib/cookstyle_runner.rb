#!/usr/bin/env ruby
# typed: true
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
#
# Optional environment variables:
#   - GCR_DESTINATION_REPO_TOPICS: Repository topics to filter by (comma-separated)
#   - GCR_BRANCH_NAME: Branch name for cookstyle fixes (default: "cookstyle-fixes")
#   - GCR_PULL_REQUEST_TITLE: Title for pull requests (default: "Automated PR: Cookstyle Changes")
#   - GCR_DEBUG_MODE: Enable debug logging (default: 0)
#

require 'English'
require 'logger'
require 'semantic_logger'
require 'fileutils'
require 'octokit'
require 'json'
require 'open3'
require 'parallel'
require 'pp'

# First, set up configuration to ensure Settings is available everywhere
require 'config'
require_relative '../config/initializers/config'

# Then load the rest of the application files
require_relative 'cookstyle_runner/git'
require_relative 'cookstyle_runner/github_api'
require_relative 'cookstyle_runner/repository_manager'
require_relative 'cookstyle_runner/cookstyle_operations'
require_relative 'cookstyle_runner/config_manager'
require_relative 'cookstyle_runner/cache_entry'
require_relative 'cookstyle_runner/cache'
require_relative 'cookstyle_runner/cache_stats'
require_relative 'cookstyle_runner/context_manager'
require_relative 'cookstyle_runner/configuration'
require_relative 'cookstyle_runner/formatter'
require_relative 'cookstyle_runner/github_pr_manager'
require_relative 'cookstyle_runner/metrics'
require_relative 'cookstyle_runner/repository_processor'
require_relative 'cookstyle_runner/settings_validator'
require_relative 'cookstyle_runner/reporter'

# Main application class for GitHub Cookstyle Runner
module CookstyleRunner
  # Main application class for GitHub Cookstyle Runner
  class Application
    attr_reader :logger, :configuration, :cache, :pr_manager, :context_manager

    # Initializes the application with a logger and configuration
    def initialize
      _load_settings
      _setup_logger
      _setup_configuration
      _setup_cache
      _setup_context_manager
      _setup_github_client
      _setup_pr_manager
      _setup_metrics_server
    end

    # Main entry point for the application
    # rubocop:disable Metrics/MethodLength
    def run
      # Fetch and filter repositories
      repositories = fetch_and_filter_repositories
      return 0 if repositories.nil? # Exit if no repositories found

      # --- Parallel Processing ---
      results = _process_repositories_in_parallel(repositories)

      # Process the collected results sequentially after parallel execution
      reporter = CookstyleRunner::Reporter.new
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
      if @configuration.use_cache && @cache&.stats
        stats_hash = @cache.stats.runtime_stats
        reporter.cache_stats(stats_hash)
      end

      # Report created artifacts
      reporter.created_artifacts(created_artifacts: @created_artifacts)
      # Report artifact creation errors
      reporter.artifact_creation_errors(@artifact_creation_errors)

      # Return appropriate exit code (e.g., non-zero if errors occurred)
      error_count.zero? && @artifact_creation_errors.empty? ? 0 : 1
    end
    # rubocop:enable Metrics/MethodLength

    # Fetches repositories from GitHub and applies filtering based on config
    # @return [Array<String>, nil] List of repository URLs or nil if none found/matched
    # rubocop:disable Metrics/MethodLength
    def fetch_and_filter_repositories
      settings = Object.const_get('Settings')

      # Use the GitHubAPI module to fetch repositories
      repositories = GitHubAPI.fetch_repositories(
        settings.owner,
        settings.topics
      )

      if repositories.empty?
        logger.error('No repositories found', topics: settings.topics)
        exit(1)
      end

      initial_count = repositories.length

      # Apply repository filtering if specified using the RepositoryManager module
      filter_repos = settings.filter_repos
      if filter_repos && !filter_repos.empty?
        filtered_repos = CookstyleRunner::RepositoryManager.filter_repositories(repositories, filter_repos, logger)
        logger.info('Repositories filtered', initial_count: initial_count, filtered_count: filtered_repos.length, filters: filter_repos)
        repositories = filtered_repos
      end

      if repositories.empty?
        logger.error('No repositories after filtering', filters: filter_repos)
        exit(1)
      end

      logger.info('Repositories ready for processing', count: repositories.length)
      repositories # Return the final list
    end
    # rubocop:enable Metrics/MethodLength

    private

    # Sets up the application logger
    def _setup_logger
      settings = Object.const_get('Settings')
      log_level_str = ENV.fetch('GCR_LOG_LEVEL', settings.log_level.to_s).upcase
      log_level_str = 'INFO' if log_level_str.empty?
      log_level = _parse_log_level(log_level_str)
      log_format = _get_log_format(settings)

      # Set SemanticLogger default level
      SemanticLogger.default_level = log_level

      # Configure appender based on format
      if log_format == :json
        SemanticLogger.add_appender(io: $stdout, formatter: :json)
      else
        SemanticLogger.add_appender(io: $stdout, formatter: :color)
      end

      # Get logger instance for this application
      @logger = SemanticLogger[self.class]

      @logger.debug('Logger initialized', level: log_level_str, format: log_format)
    end

    # Parse a log level string into a SemanticLogger level symbol
    # @param level_str [String] The log level string (e.g., 'INFO', 'DEBUG')
    # @return [Symbol] The corresponding log level symbol
    def _parse_log_level(level_str)
      level_str.downcase.to_sym
    rescue StandardError
      :info
    end

    # Get log format from ENV or settings
    # Maps 'text' to 'color' for backward compatibility
    def _get_log_format(settings)
      format_value = ENV.fetch('GCR_LOG_FORMAT', settings.log_format).to_s.strip.downcase

      # Map legacy 'text' format to 'color'
      format_value = 'color' if format_value == 'text' || format_value.empty?

      # Validate format
      format_value = 'json' unless %w[color json].include?(format_value)

      format_value.to_sym
    end

    # Get debug components from ENV or settings
    def _get_debug_components(settings)
      env_components = ENV.fetch('GCR_LOG_DEBUG_COMPONENTS', nil)

      components = if env_components
                     env_components.split(',').map(&:strip)
                   else
                     Array(settings.log_debug_components).map(&:to_s)
                   end

      components.compact!
      components.reject!(&:empty?)

      components
    end

    def _setup_configuration
      _validate_settings
      @configuration = Configuration.new
      ConfigManager.log_config_summary
    end

    def _load_settings
      ConfigGem.load_and_set_settings(
        ConfigGem.setting_files(File.expand_path('../config', __dir__), ENV['ENVIRONMENT'] || 'development')
      )
    end

    def _validate_settings
      settings = Object.const_get('Settings')
      errors = SettingsValidator.validate(settings)
      return if errors.empty?

      logger.error('Configuration validation failed', payload: {
                     errors: errors
                   })
      raise "Invalid configuration: #{errors.join(', ')}"
    end

    def _setup_cache
      settings = Object.const_get('Settings')
      cache_dir = settings.cache_dir
      @cache = Cache.new(cache_dir)
    end

    def _setup_context_manager
      @context_manager = ContextManager.instance

      # Pass the Settings object to the context manager instead of a hash
      @context_manager.global_config = Object.const_get('Settings')
    end

    # Sets up the GitHub client for API operations
    # Uses CookstyleRunner::Authentication.client for PAT or App auth
    def _setup_github_client
      @github_client = Authentication.client
    end

    def _setup_pr_manager
      settings = Object.const_get('Settings')
      @pr_manager = GitHubPRManager.new(settings, @github_client)
    end

    def _setup_metrics_server
      settings = Object.const_get('Settings')
      metrics_port = settings.respond_to?(:metrics_port) ? settings.metrics_port : 9394

      return unless settings.respond_to?(:enable_metrics) && settings.enable_metrics

      Metrics.start_server(port: metrics_port)
      logger.info('Prometheus metrics server started', payload: {
                    port: metrics_port,
                    metrics_endpoint: "http://localhost:#{metrics_port}/metrics"
                  })
    end

    # Process repositories in parallel
    def _process_repositories_in_parallel(repositories)
      total_repos = repositories.length
      thread_count = [@configuration.thread_count, total_repos].min
      logger.debug('Starting parallel processing', payload: {
                     total_repos: total_repos,
                     thread_count: thread_count,
                     action: 'process_repositories'
                   })

      repo_processor = _create_repository_processor

      # Process repositories in parallel using Parallel.map to collect results
      Parallel.map(repositories.each_with_index, in_threads: thread_count) do |repo_url, index|
        _process_single_repository(repo_processor, repo_url, index + 1, total_repos)
      end
    end

    # Create a repository processor instance
    def _create_repository_processor
      RepositoryProcessor.new(
        configuration: @configuration,
        cache_manager: @cache,
        pr_manager: @pr_manager,
        context_manager: @context_manager
      )
    end

    # Process a single repository
    def _process_single_repository(repo_processor, repo_url, current_count, total_repos)
      repo_name = File.basename(repo_url, '.git')
      logger.debug('Processing repository', payload: {
                     repo_name: repo_name,
                     current: current_count,
                     total: total_repos
                   })
      repo_processor.process_repository(repo_name, repo_url)
    end
  end

  # Run the application if this file is executed directly
  if __FILE__ == $PROGRAM_NAME
    runner = Application.new
    exit runner.run
  end
end
