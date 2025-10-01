# frozen_string_literal: true
# typed: strict

require 'sorbet-runtime'
require 'logger'
require 'config' # For ::Config::Options type
require_relative '../../config/initializers/config' # Ensure ConfigGem setup and ::Settings name is known
require_relative '../../config/validators/settings_validator' # Updated path

module CookstyleRunner
  # Configuration class that encapsulates all application configuration
  # This class now acts as a typed wrapper around the global `Settings` object
  # provided by the 'config' gem, using SettingsValidator for validation.
  class Configuration
    extend T::Sig

    # List of all configuration attributes for dynamic to_h method
    CONFIG_ATTRIBUTES = T.let(%i[
      github_token github_app_id github_app_installation_id
      github_app_private_key github_api_endpoint owner topics
      filter_repos branch_name pr_title issue_labels
      default_branch git_name git_email cache_dir
      use_cache cache_max_age force_refresh manage_changelog
      changelog_location changelog_marker retry_count
      thread_count create_manual_fix_issues
    ].freeze, T::Array[Symbol])

    # GitHub authentication configuration
    sig { returns(T.nilable(String)) }
    attr_reader :github_token

    sig { returns(T.nilable(String)) }
    attr_reader :github_app_id

    sig { returns(T.nilable(String)) }
    attr_reader :github_app_installation_id

    sig { returns(T.nilable(String)) }
    attr_reader :github_app_private_key

    sig { returns(String) } # Assuming default is always set in yml
    attr_reader :github_api_endpoint

    # Repository configuration
    sig { returns(String) }
    attr_reader :owner

    sig { returns(T.nilable(T::Array[String])) } # Optional in schema
    attr_reader :topics

    sig { returns(T.nilable(T::Array[String])) } # Optional in schema
    attr_reader :filter_repos

    # Branch/PR configuration
    sig { returns(String) }
    attr_reader :branch_name

    sig { returns(String) }
    attr_reader :pr_title

    sig { returns(T.nilable(T::Array[String])) } # Optional in schema
    attr_reader :issue_labels

    sig { returns(String) }
    attr_reader :default_branch

    # Git author configuration
    sig { returns(String) }
    attr_reader :git_name

    sig { returns(String) }
    attr_reader :git_email

    # Cache configuration
    sig { returns(String) }
    attr_reader :cache_dir

    sig { returns(T::Boolean) }
    attr_reader :use_cache

    sig { returns(Integer) }
    attr_reader :cache_max_age

    sig { returns(T::Boolean) }
    attr_reader :force_refresh

    # Changelog configuration
    sig { returns(T::Boolean) }
    attr_reader :manage_changelog

    sig { returns(String) }
    attr_reader :changelog_location

    sig { returns(String) }
    attr_reader :changelog_marker

    # Processing configuration
    sig { returns(Integer) }
    attr_reader :retry_count

    sig { returns(Integer) }
    attr_reader :thread_count

    sig { returns(T::Boolean) }
    attr_reader :create_manual_fix_issues

    # Raw settings object from ConfigGem, primarily for debugging or direct access if needed
    sig { returns(::Config::Options) }
    attr_reader :settings

    sig { params(logger: Logger).void }
    def initialize(logger)
      @logger = T.let(logger, Logger)
      # Attempt to get Settings, provide a more helpful error if it's not defined
      begin
        @settings = T.let(Object.const_get('Settings'), ::Config::Options)
      rescue NameError
        @logger.fatal('The global `Settings` constant is not defined. Ensure `config/initializers/config.rb` has run and `Config.setup` is correct.')
        raise 'Global `Settings` constant not defined. Check application initialization.'
      end

      # Validate settings using the class method on SettingsValidator
      # The SettingsValidator.validate method expects the settings object directly
      validation_errors = CookstyleRunner::SettingsValidator.validate(@settings)

      unless validation_errors.empty?
        # SettingsValidator.validate now returns an array of formatted strings
        error_messages = validation_errors.join('; ')
        @logger.error("Configuration validation failed: #{error_messages}")
        raise ArgumentError, "Configuration validation failed: #{error_messages}"
      end

      # Populate instance variables from Settings
      # GitHub authentication
      @github_token = T.let(@settings.github_token, T.nilable(String))
      @github_app_id = T.let(@settings.github_app_id, T.nilable(String))
      @github_app_installation_id = T.let(@settings.github_app_installation_id, T.nilable(String))
      @github_app_private_key = T.let(@settings.github_app_private_key, T.nilable(String))
      @github_api_endpoint = T.let(@settings.github_api_endpoint, String)

      # Repository configuration
      @owner = T.let(@settings.owner, String)
      @topics = T.let(@settings.topics, T.nilable(T::Array[String]))
      @filter_repos = T.let(@settings.filter_repos, T.nilable(T::Array[String]))

      # Branch/PR configuration
      @branch_name = T.let(@settings.branch_name, String)
      @pr_title = T.let(@settings.pr_title, String)
      @issue_labels = T.let(@settings.issue_labels, T.nilable(T::Array[String]))
      @default_branch = T.let(@settings.default_branch, String)

      # Git author configuration
      @git_name = T.let(@settings.git_name, String)
      @git_email = T.let(@settings.git_email, String)

      # Cache configuration
      @cache_dir = T.let(@settings.cache_dir, String)
      @use_cache = T.let(@settings.use_cache, T::Boolean)
      @cache_max_age = T.let(@settings.cache_max_age, Integer)
      @force_refresh = T.let(@settings.force_refresh, T::Boolean)

      # Changelog configuration
      @manage_changelog = T.let(@settings.manage_changelog, T::Boolean)
      @changelog_location = T.let(@settings.changelog_location, String)
      @changelog_marker = T.let(@settings.changelog_marker, String)

      # Processing configuration
      @retry_count = T.let(@settings.retry_count, Integer)
      @thread_count = T.let(@settings.thread_count, Integer)
      @create_manual_fix_issues = T.let(@settings.create_manual_fix_issues, T::Boolean)

      @logger.info('Configuration loaded and validated successfully.')
    end

    # Return a hash representation of all configuration attributes
    # This is useful for debugging and for passing to other components
    sig { returns(T::Hash[Symbol, T.any(String, Integer, T::Boolean, T::Array[String], T.nilable(String), T.nilable(T::Array[String]))]) }
    def to_h
      CONFIG_ATTRIBUTES.each_with_object({}) do |attr, hash|
        hash[attr] = send(attr)
      end
    end
  end
end
