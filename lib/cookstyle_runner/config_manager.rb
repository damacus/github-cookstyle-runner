# frozen_string_literal: true
# typed: true

require 'semantic_logger'
require 'fileutils'
require 'config'

# Load configuration initializer if not already loaded
require_relative '../../config/initializers/config' unless defined?(Settings)

module CookstyleRunner
  # Simplified config manager that works with Config gem
  module ConfigManager
    # Reads log level from Settings or falls back to INFO
    # Available levels: :trace, :debug, :info, :warn, :error, :fatal
    # @param debug_mode [Boolean] Override to set debug level (deprecated, use Settings.log_level instead)
    # @return [semanticLogger::Logger] Logger instance
    def self.setup_logger(debug_mode: false)
      settings = Object.const_get('Settings')

      # Determine log level
      level = if debug_mode
                :debug
              else
                parse_log_level(settings.log_level)
              end

      SemanticLogger.default_level = level
      logger = SemanticLogger[self]
      logger.info('Logger initialized', level: level)
      logger
    end

    # @param level_str [String, Symbol] Log level
    # @return [Symbol] Parsed log level symbol
    def self.parse_log_level(level_str)
      return :info if level_str.nil? || level_str.to_s.strip.empty?

      level = level_str.to_s.downcase.to_sym

      # Validate against SemanticLogger levels
      valid_levels = %i[trace debug info warn error fatal]
      valid_levels.include?(level) ? level : :info
    end

    # Log configuration summary using structured logging
    # SemanticLogger will format based on the configured appender (color/json)
    def self.log_config_summary
      logger = SemanticLogger[self]
      settings = Object.const_get('Settings')

      # Build and log structured payload
      payload = build_config_payload(settings)
      logger.debug('Configuration loaded', payload: payload)
    end

    # Build structured configuration payload
    # @param settings [Config::Options] Settings object
    # @return [Hash] Structured configuration data
    def self.build_config_payload(settings)
      {
        repo_owner: settings.owner,
        topics: settings.topics || [],
        branch_name: settings.branch_name || 'cookstyle-fixes',
        pr_title: settings.pr_title || 'Automated PR: Cookstyle Changes',
        issue_labels: settings.issue_labels || [],
        git_author: {
          name: settings.git_name || 'GitHub Cookstyle Runner',
          email: settings.git_email || 'cookstylerunner@noreply.com'
        },
        default_branch: settings.default_branch || 'main',
        cache: {
          dir: settings.cache_dir || '/tmp/cookstyle-runner',
          enabled: settings.use_cache || true,
          max_age_days: settings.cache_max_age || 7,
          force_refresh: settings.force_refresh || false
        },
        processing: {
          retry_count: settings.retry_count || 3,
          filter_repos: settings.filter_repos || [],
          create_manual_fix_issues: settings.create_manual_fix_issues || true,
          auto_assign_manual_fixes: settings.auto_assign_manual_fixes || true,
          copilot_assignee: settings.copilot_assignee || 'copilot'
        }
      }
    end

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
