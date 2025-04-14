#!/usr/bin/env ruby
# frozen_string_literal: true

require 'logger'
require 'fileutils'

module CookstyleRunner
  # Module for configuration and logging management
  module ConfigManager
    # Setup logger with appropriate configuration
    # @param debug_mode [Boolean] Whether to enable debug logging
    # @return [Logger] Configured logger instance
    def self.setup_logger(debug_mode: false)
      logger = Logger.new($stdout)
      logger.level = debug_mode ? Logger::DEBUG : Logger::INFO
      logger.formatter = proc do |severity, datetime, _progname, msg|
        "[#{datetime.utc.strftime('%Y-%m-%dT%H:%M:%SZ')}] #{severity}: #{msg}\n"
      end
      logger
    end

    # Load configuration from environment variables
    # @param logger [Logger] Logger instance
    # @return [Hash] Configuration hash
    def self.load_config(logger)
      # Required environment variables for GitHub App authentication
      app_id = ENV['GITHUB_APP_ID']
      installation_id = ENV['GITHUB_APP_INSTALLATION_ID']
      private_key = ENV['GITHUB_APP_PRIVATE_KEY']
      owner = ENV['GCR_DESTINATION_REPO_OWNER']

      # Validate required environment variables
      github_token = ENV['GITHUB_TOKEN']
      if github_token.nil? || github_token.empty?
        # Only require app-based variables if token is missing
        if app_id.nil? || app_id.empty?
          logger.error('GITHUB_APP_ID environment variable is required when GITHUB_TOKEN is not set')
          exit 1
        end
        if installation_id.nil? || installation_id.empty?
          logger.error('GITHUB_APP_INSTALLATION_ID environment variable is required when GITHUB_TOKEN is not set')
          exit 1
        end
        if private_key.nil? || private_key.empty?
          logger.error('GITHUB_APP_PRIVATE_KEY environment variable is required when GITHUB_TOKEN is not set')
          exit 1
        end
      end

      if owner.nil? || owner.empty?
        logger.error('GCR_DESTINATION_REPO_OWNER environment variable is required')
        exit 1
      end

      # Optional environment variables with defaults
      config = {
        owner: owner,
        topics: ENV['GCR_DESTINATION_REPO_TOPICS']&.split(',')&.map(&:strip),
        branch_name: ENV['GCR_BRANCH_NAME'] || 'cookstyle-fixes',
        pr_title: ENV['GCR_PULL_REQUEST_TITLE'] || 'Automated PR: Cookstyle Changes',
        pr_labels: ENV['GCR_PR_LABELS']&.split(',')&.map(&:strip),
        default_branch: ENV['GCR_DEFAULT_BRANCH'] || 'main',
        cache_dir: ENV['GCR_CACHE_DIR'] || '/tmp/cookstyle-runner',
        use_cache: ENV['GCR_USE_CACHE'] != '0',
        cache_max_age: (ENV['GCR_CACHE_MAX_AGE'] || '7').to_i,
        force_refresh: ENV['GCR_FORCE_REFRESH'] == '1',
        force_refresh_repos: ENV['GCR_FORCE_REFRESH_REPOS']&.split(',')&.map(&:strip),
        include_repos: ENV['GCR_INCLUDE_REPOS']&.split(',')&.map(&:strip),
        exclude_repos: ENV['GCR_EXCLUDE_REPOS']&.split(',')&.map(&:strip),
        retry_count: (ENV['GCR_RETRY_COUNT'] || '3').to_i,
        thread_count: (ENV['GCR_THREAD_COUNT'] || '4').to_i,
        manage_changelog: ENV['GCR_MANAGE_CHANGELOG'] != '0',
        changelog_location: ENV['GCR_CHANGELOG_LOCATION'] || 'CHANGELOG.md',
        changelog_marker: ENV['GCR_CHANGELOG_MARKER'] || '## Unreleased',
        create_manual_fix_prs: ENV['GCR_CREATE_MANUAL_FIX_PRS'] == '1',
        git_name: ENV['GCR_GIT_NAME'] || 'GitHub Cookstyle Runner',
        git_email: ENV['GCR_GIT_EMAIL'] || 'cookstyle-runner@example.com'
      }

      # Log configuration
      log_config_summary(config, logger)

      config
    end

    # Log configuration summary
    # @param config [Hash] Configuration hash
    # @param logger [Logger] Logger instance
    def self.log_config_summary(config, logger)
      # Convert cache age back to days for logging consistency
      cache_age_days = config[:cache_max_age] / (24 * 60 * 60)

      log_message = <<~SUMMARY
        --- Configuration ---
        Destination Repo Owner: #{config[:owner]}
        Destination Repo Topics: #{config[:topics]&.join(', ') || 'None'}
        Branch Name: #{config[:branch_name]}
        PR Title: #{config[:pr_title]}
        PR Labels: #{config[:pr_labels]&.join(', ') || 'None'}
        Git Author: #{config[:git_name]} <#{config[:git_email]}>
        Default Branch: #{config[:default_branch]}
        Cache Dir: #{config[:cache_dir]}
        Cache Enabled: #{config[:use_cache] ? 'Yes' : 'No'}
        Cache Max Age: #{cache_age_days} days
        Force Refresh: #{config[:force_refresh] ? 'Yes' : 'No'}
        Retry Count: #{config[:retry_count]}
        Manage Changelog: #{config[:manage_changelog] ? 'Yes' : 'No'}
        Changelog Location: #{config[:changelog_location]}
        Changelog Marker: #{config[:changelog_marker]}
        Excluding Repos: #{config[:exclude_repos]&.join(', ') || 'None'}
        Force Refresh Repos: #{config[:force_refresh_repos]&.join(', ') || 'None'}
        Include Only Repos: #{config[:include_repos]&.join(', ') || 'None'}
        Filter Repos: #{config[:filter_repos]&.join(', ') || 'None'}
        Create Manual Fix Issues: #{config[:create_manual_fix_issues] ? 'Yes' : 'No'}
        ---------------------
      SUMMARY

      logger.info(log_message.strip)
    end

    # Setup cache directory
    # @param cache_dir [String] Cache directory path
    # @param logger [Logger] Logger instance
    # @return [Boolean] True if successful
    def self.setup_cache_directory(cache_dir, logger)
      FileUtils.mkdir_p(cache_dir) unless Dir.exist?(cache_dir)
      true
    rescue StandardError => e
      logger.error("Error creating cache directory: #{e.message}")
      false
    end

    # --- Private Class Methods ---
    # Setup configuration (internal helper, not part of public API)
    # @return [Hash] Configuration hash
    def self.setup_configuration
      # Set defaults for optional variables
      @config = {
        owner: ENV['GCR_DESTINATION_REPO_OWNER'],
        topics: ENV['GCR_DESTINATION_REPO_TOPICS']&.split(',')&.map(&:strip) || ['chef-cookbook'],
        branch_name: ENV['GCR_BRANCH_NAME'] || 'cookstyle-fixes',
        pr_title: ENV['GCR_PULL_REQUEST_TITLE'] || 'Automated PR: Cookstyle Changes',
        default_branch: ENV['GCR_DEFAULT_GIT_BRANCH'] || 'main',
        manage_changelog: ENV['GCR_MANAGE_CHANGELOG'] == '1',
        changelog_location: ENV['GCR_CHANGELOG_LOCATION'] || 'CHANGELOG.md',
        changelog_marker: ENV['GCR_CHANGELOG_MARKER'] || '## Unreleased',
        git_name: ENV['GCR_GIT_NAME'] || 'Cookstyle Bot',
        git_email: ENV['GCR_GIT_EMAIL'] || 'cookstyle@example.com',
        pr_labels: ENV['GCR_PULL_REQUEST_LABELS']&.split(',')&.map(&:strip) || [],
        cache_dir: ENV['CACHE_DIR'] || '/tmp/cookstyle-runner',
        thread_count: ENV['GCR_THREAD_COUNT']&.to_i || 5,
        use_cache: ENV['GCR_USE_CACHE'] != '0',
        cache_max_age: ENV['GCR_CACHE_MAX_AGE']&.to_i || (7 * 24 * 60 * 60), # 7 days in seconds
        force_refresh: ENV['GCR_FORCE_REFRESH'] == '1',
        force_refresh_repos: ENV['GCR_FORCE_REFRESH_REPOS']&.split(',')&.map(&:strip),
        include_repos: ENV['GCR_INCLUDE_REPOS']&.split(',')&.map(&:strip),
        exclude_repos: ENV['GCR_EXCLUDE_REPOS']&.split(',')&.map(&:strip),
        retry_count: ENV['GCR_RETRY_COUNT']&.to_i || 3,
        filter_repos: ENV['GCR_FILTER_REPOS']&.split(',')&.map(&:strip),
        create_manual_fix_issues: ENV['GCR_CREATE_MANUAL_FIX_ISSUES'] == '1'
      }
    end

    private_class_method :setup_configuration
  end
end