# frozen_string_literal: true

require 'singleton'
require_relative 'git_operations'

module CookstyleRunner
  # Manages repository contexts across the application
  # Provides thread-safe access to repository context objects
  class ContextManager
    include Singleton

    def initialize
      @context_mutex = Mutex.new
      @repo_contexts = {}
      @global_config = {}
    end

    # Set global configuration that will be used for all contexts
    # @param config [Hash] Global configuration hash
    # @param logger [Logger] Logger instance
    def set_global_config(config, logger)
      @context_mutex.synchronize do
        @global_config = config
        @global_logger = logger
      end
    end

    # Get or create a repository context for a specific repository
    # @param repo_url [String] Repository URL
    # @param repo_dir [String] Repository directory
    # @return [GitOperations::RepoContext] Repository context
    def get_repo_context(repo_url, repo_dir)
      repo_name = File.basename(repo_url, '.git')

      @context_mutex.synchronize do
        # Return existing context if available
        return @repo_contexts[repo_name] if @repo_contexts.key?(repo_name)

        # Otherwise create a new context
        context = create_context(repo_name, repo_url, repo_dir)
        @repo_contexts[repo_name] = context
        context
      end
    end

    # Clear all cached contexts
    def clear_contexts
      @context_mutex.synchronize do
        @repo_contexts.clear
      end
    end

    private

    # Create a repository context with appropriate authentication
    # rubocop:disable Metrics/MethodLength
    def create_context(repo_name, repo_url, repo_dir)
      auth_params = if CookstyleRunner::Authentication.use_pat?
                      { github_token: ENV.fetch('GITHUB_TOKEN', nil) }
                    else
                      {
                        app_id: ENV.fetch('GITHUB_APP_ID', nil),
                        installation_id: ENV.fetch('GITHUB_APP_INSTALLATION_ID', nil),
                        private_key: ENV.fetch('GITHUB_APP_PRIVATE_KEY', nil)
                      }
                    end

      GitOperations::RepoContext.new(
        repo_name: repo_name,
        owner: @global_config[:owner],
        logger: @global_logger,
        repo_dir: repo_dir,
        repo_url: repo_url,
        **auth_params
      )
    end
    # rubocop:enable Metrics/MethodLength
  end
end
