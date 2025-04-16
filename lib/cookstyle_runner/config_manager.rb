#!/usr/bin/env ruby
# frozen_string_literal: true

require 'logger'
require 'fileutils'

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
    # Required environment variables
    github_token = ENV['GITHUB_TOKEN']
    owner = ENV['GCR_DESTINATION_REPO_OWNER']

    # Validate required environment variables
    if github_token.nil? || github_token.empty?
      logger.error('GITHUB_TOKEN environment variable is required')
      exit 1
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
    logger.info('--- Configuration ---')
    logger.info("Destination Repo Owner: #{config[:owner]}")
    logger.info("Destination Repo Topics: #{config[:topics]&.join(', ') || 'None'}")
    logger.info("Branch Name: #{config[:branch_name]}")
    logger.info("PR Title: #{config[:pr_title]}")
    logger.info("PR Labels: #{config[:pr_labels]&.join(', ') || 'None'}")
    logger.info("Git Author: #{config[:git_name]} <#{config[:git_email]}>")
    logger.info("Default Branch: #{config[:default_branch]}")
    logger.info("Cache Dir: #{config[:cache_dir]}")
    logger.info("Cache Enabled: #{config[:use_cache] ? 'Yes' : 'No'}")
    logger.info("Cache Max Age: #{config[:cache_max_age]} days")
    logger.info("Force Refresh: #{config[:force_refresh] ? 'Yes' : 'No'}")
    logger.info("Retry Count: #{config[:retry_count]}")
    logger.info("Manage Changelog: #{config[:manage_changelog] ? 'Yes' : 'No'}")
    logger.info("Changelog Location: #{config[:changelog_location]}")
    logger.info("Changelog Marker: #{config[:changelog_marker]}")
    logger.info('---------------------')

    config
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
end
