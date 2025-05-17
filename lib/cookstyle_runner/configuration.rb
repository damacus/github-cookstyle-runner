# frozen_string_literal: true
# typed: strict

require 'sorbet-runtime'
require 'logger'
require 'yaml'
require_relative 'configuration_validator'

module CookstyleRunner
  # Configuration class that encapsulates all application configuration
  # with proper type validation and sensible defaults.
  # This class loads configuration from YAML files and environment variables,
  # with environment variables taking precedence.
  class Configuration
    extend T::Sig

    # Deep merge two hashes
    sig { params(first_hash: T::Hash[Symbol, T.untyped], second_hash: T::Hash[Symbol, T.untyped]).returns(T::Hash[Symbol, T.untyped]) }
    def self.deep_merge(first_hash, second_hash)
      first_hash.merge(second_hash) do |_, old_val, new_val|
        if old_val.is_a?(Hash) && new_val.is_a?(Hash)
          deep_merge(old_val, new_val)
        else
          new_val
        end
      end
    end

    # Find the default config file in the app root or config/
    sig { returns(T.nilable(String)) }
    def self.default_config_path
      # Look in the following locations in order:
      # 1. config/ at project root (production/default)
      # 2. spec/fixtures for tests
      possible_paths = [
        File.expand_path('../../../config/_default_configuration.yml', __dir__),
        File.expand_path('../../../spec/fixtures/_default_configuration.yml', __dir__)
      ]

      found_path = possible_paths.find { |path| File.exist?(path) }
      Logger.new($stdout).debug("Found default configuration at: #{found_path}") if found_path && ENV['DEBUG']
      found_path
    end

    # GitHub authentication configuration
    sig { returns(T.nilable(String)) }
    attr_reader :github_token

    sig { returns(T.nilable(String)) }
    attr_reader :github_app_id

    sig { returns(T.nilable(String)) }
    attr_reader :github_app_installation_id

    sig { returns(T.nilable(String)) }
    attr_reader :github_app_private_key

    sig { returns(T.nilable(String)) }
    attr_reader :github_api_endpoint

    # Repository configuration
    sig { returns(String) }
    attr_reader :owner

    sig { returns(T::Array[String]) }
    attr_reader :topics

    sig { returns(T::Array[String]) }
    attr_reader :filter_repos

    # Branch/PR configuration
    sig { returns(T.nilable(String)) }
    attr_reader :branch_name

    sig { returns(T.nilable(String)) }
    attr_reader :pr_title

    sig { returns(T.nilable(T::Array[String])) }
    attr_reader :issue_labels

    sig { returns(T.nilable(String)) }
    attr_reader :default_branch

    # Git author configuration
    sig { returns(String) }
    attr_reader :git_name

    sig { returns(String) }
    attr_reader :git_email

    # Cache configuration
    sig { returns(T.nilable(String)) }
    attr_reader :cache_dir

    sig { returns(T.nilable(T::Boolean)) }
    attr_reader :use_cache

    sig { returns(T.nilable(Integer)) }
    attr_reader :cache_max_age

    sig { returns(T.nilable(T::Boolean)) }
    attr_reader :force_refresh

    # Changelog configuration
    sig { returns(T::Boolean) }
    attr_reader :manage_changelog

    sig { returns(String) }
    attr_reader :changelog_location

    sig { returns(String) }
    attr_reader :changelog_marker

    # Processing configuration
    sig { returns(T.nilable(Integer)) }
    attr_reader :retry_count

    sig { returns(T.nilable(Integer)) }
    attr_reader :thread_count

    sig { returns(T.nilable(T::Boolean)) }
    attr_reader :create_manual_fix_issues

    sig { params(logger: T.untyped, validator: T.nilable(T.untyped), config_files: T.nilable(T::Array[String])).void }
    def initialize(logger, validator = nil, config_files: nil)
      @logger = T.let(logger, T.any(Logger, T.untyped))
      @validator = T.let(validator || ConfigurationValidator.new(logger), T.untyped)

      # GitHub authentication
      @github_token = T.let(nil, T.nilable(String))
      @github_app_id = T.let(nil, T.nilable(String))
      @github_app_installation_id = T.let(nil, T.nilable(String))
      @github_app_private_key = T.let(nil, T.nilable(String))
      @github_api_endpoint = T.let('https://api.github.com', String)

      # Repository configuration
      @owner = T.let('', String)
      @topics = T.let([], T::Array[String])
      @filter_repos = T.let([], T::Array[String])

      # Branch/PR configuration
      @branch_name = T.let('cookstyle-fixes', String)
      @pr_title = T.let('Automated PR: Cookstyle Changes', String)
      @issue_labels = T.let([], T::Array[String])
      @default_branch = T.let('main', String)

      # Git author configuration
      @git_name = T.let('GitHub Cookstyle Runner', String)
      @git_email = T.let('cookstylerunner@noreply.com', String)

      # Cache configuration
      @cache_dir = T.let('/tmp/cookstyle-runner', String)
      @use_cache = T.let(true, T::Boolean)
      @cache_max_age = T.let(7, Integer) # Default to 7 days
      @force_refresh = T.let(false, T::Boolean)

      # Changelog configuration
      @manage_changelog = T.let(true, T::Boolean)
      @changelog_location = T.let('CHANGELOG.md', String)
      @changelog_marker = T.let('## Unreleased', String)

      # Processing configuration
      @retry_count = T.let(3, Integer)
      @thread_count = T.let(4, Integer)
      @create_manual_fix_issues = T.let(true, T::Boolean) # Default to true to ensure issues are created for manual fixes

      # Load configuration from YAML files
      config_files ||= [self.class.default_config_path].compact
      if config_files.any?
        merged_config = load_and_merge_yaml_configs(config_files)
        apply_config(merged_config)
      end

      # Apply environment variables (highest priority)
      apply_environment_variables

      # Validate configuration
      @validator.validate_required_env_vars if @validator.respond_to?(:validate_required_env_vars)
    end

    # Initialize all instance variables
    # This method is no longer needed as defaults are set in initialize
    sig { void }
    def initialize_defaults
      # Defaults are now set directly in initialize
    end
    private :initialize_defaults

    # Load and merge YAML configuration files
    sig { params(config_files: T::Array[String]).returns(T::Hash[Symbol, T.untyped]) }
    def load_and_merge_yaml_configs(config_files)
      merged = {}
      config_files.each do |path|
        next unless path && File.exist?(path)

        begin
          yaml_content = YAML.safe_load_file(path) || {}
          # Use a safer approach to transform keys to symbols
          yaml_hash = {}
          yaml_content.each_pair do |key, value|
            yaml_hash[key.to_sym] = value
          end
          merged = self.class.deep_merge(merged, yaml_hash)
          @logger.debug("Loaded configuration from #{path}")
        rescue StandardError => e
          @logger.error("Error loading configuration from #{path}: #{e.message}")
        end
      end
      merged
    end
    private :load_and_merge_yaml_configs

    # Apply configuration from YAML
    sig { params(config: T::Hash[Symbol, T.untyped]).void }
    def apply_config(config)
      # GitHub authentication
      @github_token = config[:github_token] if config[:github_token]
      @github_app_id = config[:github_app_id] if config[:github_app_id]
      @github_app_installation_id = config[:github_app_installation_id] if config[:github_app_installation_id]
      @github_app_private_key = config[:github_app_private_key] if config[:github_app_private_key]
      @github_api_endpoint = config[:github_api_endpoint] if config[:github_api_endpoint]

      # Repository configuration
      @owner = config[:owner] if config[:owner]
      @topics = Array(config[:topics]) if config[:topics]
      @filter_repos = Array(config[:filter_repos]) if config.key?(:filter_repos)

      # Branch/PR configuration
      @branch_name = config[:branch_name] if config[:branch_name]
      @pr_title = config[:pr_title] if config[:pr_title]
      @issue_labels = Array(config[:issue_labels]) if config[:issue_labels]
      @default_branch = config[:default_branch] if config[:default_branch]

      # Git author configuration
      @git_name = config[:git_name] if config[:git_name]
      @git_email = config[:git_email] if config[:git_email]

      # Cache configuration
      @cache_dir = config[:cache_dir] if config[:cache_dir]
      @use_cache = config[:use_cache] unless config[:use_cache].nil?
      # Ensure cache_max_age is at least 1 day, default to 7
      @cache_max_age = [1, config[:cache_max_age].to_i].max if config.key?(:cache_max_age)
      @force_refresh = config[:force_refresh] unless config[:force_refresh].nil?

      # Changelog configuration
      @manage_changelog = config[:manage_changelog] unless config[:manage_changelog].nil?
      @changelog_location = config[:changelog_location] if config[:changelog_location]
      @changelog_marker = config[:changelog_marker] if config[:changelog_marker]

      # Processing configuration
      @retry_count = config[:retry_count] if config[:retry_count]
      @thread_count = config[:thread_count] if config[:thread_count]
      # Ensure create_manual_fix_issues is set correctly to create issues for manual fixes
      return unless config.key?(:create_manual_fix_issues)

      @create_manual_fix_issues = config[:create_manual_fix_issues]
    end
    private :apply_config

    # Apply environment variables
    sig { void }
    def apply_environment_variables
      # GitHub authentication - prioritize environment variables
      @github_token = ENV['GITHUB_TOKEN'] if ENV['GITHUB_TOKEN']
      @github_app_id = ENV['GITHUB_APP_ID'] if ENV['GITHUB_APP_ID']
      @github_app_installation_id = ENV['GITHUB_APP_INSTALLATION_ID'] if ENV['GITHUB_APP_INSTALLATION_ID']
      @github_app_private_key = ENV['GITHUB_APP_PRIVATE_KEY'] if ENV['GITHUB_APP_PRIVATE_KEY']
      @github_api_endpoint = ENV['GITHUB_API_ENDPOINT'] if ENV['GITHUB_API_ENDPOINT']

      # Cache configuration from environment
      if ENV.key?('GCR_CACHE_MAX_AGE')
        env_cache_max_age_str = ENV['GCR_CACHE_MAX_AGE']
        if env_cache_max_age_str && !env_cache_max_age_str.empty?
          env_cache_max_age_int = env_cache_max_age_str.to_i
          if env_cache_max_age_int.positive?
            @cache_max_age = env_cache_max_age_int
          else
            @logger.warn("Invalid GCR_CACHE_MAX_AGE value '#{env_cache_max_age_str}'. Using default of #{@cache_max_age} days.")
          end
        else
          # This handles cases where GCR_CACHE_MAX_AGE is set but empty, or if it's nil (though ENV.key? checks for presence)
          # If ENV.key? is true, env_cache_max_age_str won't be nil, so this mostly covers the empty string case.
          @logger.warn("GCR_CACHE_MAX_AGE is present but effectively empty or invalid. Using default of #{@cache_max_age} days.") unless env_cache_max_age_str.nil? # Log only if it was actually an empty string
        end
      end

      # Processing configuration from environment
      @create_manual_fix_issues = ENV['CREATE_MANUAL_FIX_ISSUES'] == 'true' if ENV.key?('CREATE_MANUAL_FIX_ISSUES')
    end
    private :apply_environment_variables

    # This method used to log a summary of the configuration
    # It has been replaced by ConfigManager.log_config_summary
    sig { params(logger: T.untyped).void }
    def log_summary(logger = @logger)
      logger.info('Configuration log_summary is deprecated - use ConfigManager.log_config_summary instead')
    end

    # Get a hash representation of the configuration
    sig { returns(T::Hash[Symbol, T.untyped]) }
    def to_h
      {
        github_token: @github_token,
        github_app_id: @github_app_id,
        github_app_installation_id: @github_app_installation_id,
        github_app_private_key: @github_app_private_key,
        github_api_endpoint: @github_api_endpoint,
        owner: @owner,
        topics: @topics,
        filter_repos: @filter_repos,
        branch_name: @branch_name,
        pr_title: @pr_title,
        issue_labels: @issue_labels,
        default_branch: @default_branch,
        git_name: @git_name,
        git_email: @git_email,
        cache_dir: @cache_dir,
        use_cache: @use_cache,
        cache_max_age: @cache_max_age,
        force_refresh: @force_refresh,
        manage_changelog: @manage_changelog,
        changelog_location: @changelog_location,
        changelog_marker: @changelog_marker,
        retry_count: @retry_count,
        thread_count: @thread_count,
        create_manual_fix_issues: @create_manual_fix_issues
      }
    end

    # For backward compatibility with existing code
    alias to_hash to_h

    # Authentication configuration hash
    sig { returns(T::Hash[Symbol, T.untyped]) }
    def auth_config
      {
        github_token: @github_token,
        github_app_id: @github_app_id,
        github_app_installation_id: @github_app_installation_id,
        github_app_private_key: @github_app_private_key,
        github_api_endpoint: @github_api_endpoint
      }
    end

    # Repository configuration hash
    sig { returns(T::Hash[Symbol, T.untyped]) }
    def repository_config
      {
        owner: @owner,
        topics: @topics,
        filter_repos: @filter_repos
      }
    end

    # Branch and PR configuration hash
    sig { returns(T::Hash[Symbol, T.untyped]) }
    def branch_pr_config
      {
        branch_name: @branch_name,
        pr_title: @pr_title,
        issue_labels: @issue_labels,
        default_branch: @default_branch
      }
    end

    # Git author configuration hash
    sig { returns(T::Hash[Symbol, T.untyped]) }
    def git_config
      {
        git_name: @git_name,
        git_email: @git_email
      }
    end

    # Cache configuration hash
    sig { returns(T::Hash[Symbol, T.untyped]) }
    def cache_config
      {
        cache_dir: @cache_dir,
        use_cache: @use_cache,
        cache_max_age: @cache_max_age,
        force_refresh: @force_refresh
      }
    end

    # Changelog configuration hash
    sig { returns(T::Hash[Symbol, T.untyped]) }
    def changelog_config
      {
        manage_changelog: @manage_changelog,
        changelog_location: @changelog_location,
        changelog_marker: @changelog_marker
      }
    end

    # Processing configuration hash
    sig { returns(T::Hash[Symbol, T.untyped]) }
    def processing_config
      {
        retry_count: @retry_count,
        thread_count: @thread_count,
        create_manual_fix_issues: @create_manual_fix_issues
      }
    end
  end
end
