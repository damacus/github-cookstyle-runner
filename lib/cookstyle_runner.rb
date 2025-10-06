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
#
# Optional environment variables:
#   - GCR_DESTINATION_REPO_TOPICS: Repository topics to filter by (comma-separated)
#   - GCR_BRANCH_NAME: Branch name for cookstyle fixes (default: "cookstyle-fixes")
#   - GCR_PULL_REQUEST_TITLE: Title for pull requests (default: "Automated PR: Cookstyle Changes")
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

# First, set up configuration to ensure Settings is available everywhere
require 'config'
require_relative '../config/initializers/config'

# Then load the rest of the application files
require_relative 'cookstyle_runner/logger'
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
      if @configuration.use_cache && @cache&.stats
        # Call instance method on the stats object within cache
        stats_hash = @cache.stats.runtime_stats
        @logger.info("Cache Stats:\n#{PP.pp(stats_hash, +'')}")
      end

      # Report created artifacts
      reporter.created_artifacts(created_artifacts: @created_artifacts)
      # Report artifact creation errors
      reporter.artifact_creation_errors(@artifact_creation_errors)

      # Return appropriate exit code (e.g., non-zero if errors occurred)
      error_count.zero? && @artifact_creation_errors.empty? ? 0 : 1
    end
    # rubocop:enable Metrics/MethodLength

    private

    # Sets up the application logger
    def _setup_logger
      log_level_str = ENV.fetch('GCR_LOG_LEVEL', Settings.log_level.to_s).upcase
      log_level = _parse_log_level(log_level_str)
      log_format = _get_log_format(Settings)
      debug_components = _get_debug_components(Settings)

      @logger = CookstyleRunner::Logger.new(
        $stdout,
        level: log_level,
        format: log_format,
        components: debug_components
      )

      _log_logger_info(log_level_str, log_format, debug_components)
    end

    # Parse a log level string into a Logger constant
    # @param level_str [String] The log level string (e.g., 'INFO', 'DEBUG')
    # @return [Integer] The corresponding Logger constant value
    def _parse_log_level(level_str)
      ::Logger.const_get(level_str)
    rescue NameError
      logger&.warn("Invalid log level '#{level_str}', defaulting to INFO.")
      ::Logger::INFO
    end

    # Get log format from ENV or settings
    def _get_log_format(settings)
      format_value = ENV.fetch('GCR_LOG_FORMAT', settings.log_format).to_s.strip
      format_value = 'text' if format_value.empty?
      format_value.downcase.to_sym
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

    # Log logger initialization info
    def _log_logger_info(log_level_str, log_format, debug_components)
      logger.info("Log level set to: #{log_level_str}")
      logger.info("Log format: #{log_format}")
      return if debug_components.empty?

      logger.info("Debug components: #{debug_components.join(', ')}")
    end

    def _setup_configuration
      _validate_settings
      @configuration = Configuration.new(logger)
      ConfigManager.log_config_summary(logger)
    end

    def _load_settings
      ConfigGem.load_and_set_settings(
        ConfigGem.setting_files(File.expand_path('../config', __dir__), ENV['ENVIRONMENT'] || 'development')
      )
    end

    def _validate_settings
      errors = SettingsValidator.validate(Settings)
      return if errors.empty?

      errors.each { |error| logger.error("Configuration error: #{error}") }
      raise "Invalid configuration: #{errors.join(', ')}"
    end

    def _setup_cache
      cache_dir = Settings.cache_dir
      @cache = Cache.new(cache_dir, logger)
    end

    def _setup_context_manager
      @context_manager = ContextManager.instance

      # Pass the Settings object to the context manager instead of a hash
      @context_manager.set_global_config(Settings, @logger)
    end

    # Sets up the GitHub client for API operations
    # Uses CookstyleRunner::Authentication.client for PAT or App auth
    def _setup_github_client
      @github_client = Authentication.client
    end

    def _setup_pr_manager
      @pr_manager = GitHubPRManager.new(Settings, @logger, @github_client)
    end

    # Fetches repositories from GitHub and applies filtering based on config
    # @return [Array<String>, nil] List of repository URLs or nil if none found/matched
    # rubocop:disable Metrics/MethodLength
    def fetch_and_filter_repositories
      # Use the GitHubAPI module to fetch repositories
      repositories = GitHubAPI.fetch_repositories(
        Settings.owner,
        logger,
        Settings.topics
      )

      if repositories.empty?
        logger.error('No repositories found matching the initial criteria. Exiting.')
        exit(1)
      end

      initial_count = repositories.length

      # Apply repository filtering if specified using the RepositoryManager module
      filter_repos = settings.filter_repos
      if filter_repos && !filter_repos.empty?
        filtered_repos = CookstyleRunner::RepositoryManager.filter_repositories(repositories, filter_repos, logger)
        logger.info("Filtered from #{initial_count} to #{filtered_repos.length} repositories based on include/exclude lists.")
        repositories = filtered_repos
      end

      if repositories.empty?
        logger.error('No repositories remaining after filtering. Exiting.')
        exit(1)
      end

      logger.info("Found #{repositories.length} repositories to process.")
      repositories # Return the final list
    end
    # rubocop:enable Metrics/MethodLength

    # Process repositories in parallel
    def _process_repositories_in_parallel(repositories)
      total_repos = repositories.length
      thread_count = [@configuration.thread_count, total_repos].min
      logger.info("Processing #{total_repos} repositories using #{thread_count} threads")

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
        logger: logger,
        cache_manager: @cache,
        pr_manager: @pr_manager,
        context_manager: @context_manager
      )
    end

    # Process a single repository
    def _process_single_repository(repo_processor, repo_url, current_count, total_repos)
      repo_name = File.basename(repo_url, '.git')
      logger.debug("Processing repository #{current_count}/#{total_repos}: #{repo_name}")
      repo_processor.process_repository(repo_name, repo_url)
    end
  end

  # Run the application if this file is executed directly
  if __FILE__ == $PROGRAM_NAME
    runner = Application.new
    exit runner.run
  end
end
