# frozen_string_literal: true
# typed: true

require 'logger'
require 'fileutils'
require 'config'

# Load configuration initializer if not already loaded
require_relative '../../config/initializers/config' unless defined?(Settings)

module CookstyleRunner
  # Simplified config manager that works with Config gem
  module ConfigManager
    # Setup logger with appropriate configuration
    def self.setup_logger(debug_mode: false)
      logger = Logger.new($stdout)
      logger.level = debug_mode ? Logger::DEBUG : Logger::INFO
      logger.formatter = proc do |severity, datetime, _progname, msg|
        "[#{datetime.utc.strftime('%Y-%m-%dT%H:%M:%SZ')}] #{severity}: #{msg}\n"
      end
      logger
    end

    # Log configuration summary
    # @param logger [Logger] Logger instance
    # @param format [String] Output format (text, table, json)
    def self.log_config_summary(logger, format: 'text')
      # Access settings via Object.const_get to avoid lint errors
      settings = Object.const_get('Settings')

      # Get values with nil checks
      cache_age_days = settings.cache_max_age || 7
      topics = settings.topics ? settings.topics.join(', ') : 'None'
      filter_repos = settings.filter_repos && !settings.filter_repos.empty? ? settings.filter_repos.join(', ') : 'None'
      issue_labels = settings.issue_labels ? settings.issue_labels.join(', ') : 'None'

      # Get the rest of the settings with default values as fallbacks
      owner = settings.owner
      branch_name = settings.branch_name || 'cookstyle-fixes'
      pr_title = settings.pr_title || 'Automated PR: Cookstyle Changes'
      git_name = settings.git_name || 'GitHub Cookstyle Runner'
      git_email = settings.git_email || 'cookstylerunner@noreply.com'
      default_branch = settings.default_branch || 'main'
      cache_dir = settings.cache_dir || '/tmp/cookstyle-runner'
      use_cache = settings.use_cache || true
      force_refresh = settings.force_refresh || false
      retry_count = settings.retry_count || 3
      create_manual_fix_issues = settings.create_manual_fix_issues || true

      case format
      when 'table'
        log_config_summary_table(logger, owner, topics, branch_name, pr_title, issue_labels,
                                 git_name, git_email, default_branch, cache_dir, use_cache,
                                 cache_age_days, force_refresh, retry_count, filter_repos,
                                 create_manual_fix_issues)
      when 'json'
        log_config_summary_json(logger, owner, topics, branch_name, pr_title, issue_labels,
                                git_name, git_email, default_branch, cache_dir, use_cache,
                                cache_age_days, force_refresh, retry_count, filter_repos,
                                create_manual_fix_issues)
      else
        log_config_summary_text(logger, owner, topics, branch_name, pr_title, issue_labels,
                                git_name, git_email, default_branch, cache_dir, use_cache,
                                cache_age_days, force_refresh, retry_count, filter_repos,
                                create_manual_fix_issues)
      end
    end

    # rubocop:disable Metrics/ParameterLists
    def self.log_config_summary_text(logger, owner, topics, branch_name, pr_title, issue_labels,
                                     git_name, git_email, default_branch, cache_dir, use_cache,
                                     cache_age_days, force_refresh, retry_count, filter_repos,
                                     create_manual_fix_issues)
      log_message = <<~SUMMARY

        --- Configuration ---
        Destination Repo Owner: #{owner}
        Destination Repo Topics: #{topics}
        Branch Name: #{branch_name}
        PR Title: #{pr_title}
        PR Labels: #{issue_labels}
        Git Author: #{git_name} <#{git_email}>
        Default Branch: #{default_branch}
        Cache Dir: #{cache_dir}
        Cache Enabled: #{use_cache ? 'Yes' : 'No'}
        Cache Max Age: #{cache_age_days} days
        Force Refresh: #{force_refresh ? 'Yes' : 'No'}
        Retry Count: #{retry_count}
        Filter Repos: #{filter_repos}
        Create Manual Fix Issues: #{create_manual_fix_issues ? 'Yes' : 'No'}
        ---------------------
      SUMMARY

      logger.info(log_message.strip)
    end

    def self.log_config_summary_table(logger, owner, topics, branch_name, pr_title, issue_labels,
                                      git_name, git_email, default_branch, cache_dir, use_cache,
                                      cache_age_days, force_refresh, retry_count, filter_repos,
                                      create_manual_fix_issues)
      require_relative 'table_renderer'
      config_data = {
        'Repo Owner' => owner,
        'Topics' => topics,
        'Branch Name' => branch_name,
        'PR Title' => pr_title,
        'PR Labels' => issue_labels,
        'Git Author' => "#{git_name} <#{git_email}>",
        'Default Branch' => default_branch,
        'Cache Dir' => cache_dir,
        'Cache Enabled' => use_cache ? 'Yes' : 'No',
        'Cache Max Age' => "#{cache_age_days} days",
        'Force Refresh' => force_refresh ? 'Yes' : 'No',
        'Retry Count' => retry_count.to_s,
        'Filter Repos' => filter_repos,
        'Manual Fix Issues' => create_manual_fix_issues ? 'Yes' : 'No'
      }
      logger.info("\n#{TableRenderer.render_summary(config_data)}")
    end

    def self.log_config_summary_json(logger, owner, topics, branch_name, pr_title, issue_labels,
                                     git_name, git_email, default_branch, cache_dir, use_cache,
                                     cache_age_days, force_refresh, retry_count, filter_repos,
                                     create_manual_fix_issues)
      require 'json'
      config_data = {
        configuration: {
          repo_owner: owner,
          topics: topics,
          branch_name: branch_name,
          pr_title: pr_title,
          pr_labels: issue_labels,
          git_author: {
            name: git_name,
            email: git_email
          },
          default_branch: default_branch,
          cache_dir: cache_dir,
          cache_enabled: use_cache,
          cache_max_age_days: cache_age_days,
          force_refresh: force_refresh,
          retry_count: retry_count,
          filter_repos: filter_repos,
          create_manual_fix_issues: create_manual_fix_issues
        }
      }
      logger.info("\n#{JSON.pretty_generate(config_data)}")
    end
    # rubocop:enable Metrics/ParameterLists

    # Setup cache directory
    def self.setup_cache_directory(cache_dir, logger)
      FileUtils.mkdir_p(cache_dir)
      true
    rescue StandardError => e
      logger.error("Error creating cache directory: #{e.message}")
      false
    end
  end
end
