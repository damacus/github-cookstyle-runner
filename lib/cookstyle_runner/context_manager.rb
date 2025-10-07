# frozen_string_literal: true
# typed: true

require 'singleton'
require_relative 'git'
require 'logger'
require 'sorbet-runtime'

module CookstyleRunner
  # =============================================================================
  # Context Manager
  # =============================================================================
  #
  # Manages repository context including authentication and configuration.
  # Ensures that each repository has a dedicated context object.
  #
  class ContextManager
    extend T::Sig
    include Singleton

    sig { void }
    def initialize
      @context_mutex = T.let(Mutex.new, Mutex)
      @repo_contexts = T.let({}, T::Hash[String, CookstyleRunner::Git::RepoContext])
      @global_config = T.let({},
                             T::Hash[Symbol, T.any(String, Integer, T::Boolean, T::Array[String], T.nilable(String), T.nilable(T::Array[String]))])
      @logger = T.let(SemanticLogger[self.class], SemanticLogger::Logger)
    end

    # Set global configuration that will be used for all contexts
    # @param config [Hash, Object] Global configuration hash or Settings object
    # @return [void]
    sig do
      params(
        config: T.any(T::Hash[Symbol, T.any(String, Integer, T::Boolean, T::Array[String], T.nilable(String), T.nilable(T::Array[String]))],
                      ::Config::Options)
      ).void
    end
    def global_config=(config)
      @context_mutex.synchronize do
        # Convert Settings object to hash if needed
        @global_config = config.respond_to?(:to_h) ? config.to_h : config
      end
    end

    # Get or create a repository context for a specific repository
    # @param repo_url [String] Repository URL (e.g., 'https://github.com/owner/repo.git')
    # @param _repo_dir [String] Repository directory (unused, marked with _)
    # @return [RepoContext] Repository context
    sig { params(repo_url: String, _repo_dir: String).returns(CookstyleRunner::Git::RepoContext) }
    def get_repo_context(repo_url, _repo_dir)
      repo_name = File.basename(repo_url, '.git')

      T.must(@context_mutex.synchronize do
        # Check if context already exists
        if @repo_contexts.key?(repo_name)
          @repo_contexts[repo_name]
        else
          # Otherwise create a new context
          # Ensure owner is retrieved correctly from global config
          owner = T.let(@global_config[:owner], T.nilable(String))
          raise 'Owner not found in global config' unless owner

          context = create_context(repo_name, owner, repo_url)
          @repo_contexts[repo_name] = context
          context
        end
      end)
    end

    # Clear all cached contexts
    # @return [T.self_type] Return self for chaining
    sig { returns(T.self_type) }
    def clear_contexts
      @context_mutex.synchronize do
        @repo_contexts.clear
      end
      self
    end

    # Add a new context for a repository
    # @param repo_name [String] Repository name
    # @param owner [String] Repository owner
    # @param repo_url [String, nil] Optional repository URL
    # @return [T.self_type] Return self for chaining
    sig { params(repo_name: String, owner: String, repo_url: T.nilable(String)).returns(T.self_type) }
    def add_context(repo_name, owner, repo_url = nil)
      # Use RepoContext directly
      context = CookstyleRunner::Git::RepoContext.new(
        repo_name: repo_name,
        owner: owner,
        repo_url: repo_url
        # repo_dir, github_token, app_id, installation_id, private_key will use defaults (nil)
      )
      @repo_contexts[repo_name] = context
      self
    end

    private

    # Create a repository context with appropriate authentication
    # Disable length check for this method
    # rubocop:disable Metrics/MethodLength
    sig { params(repo_name: String, owner: String, repo_url: T.nilable(String)).returns(CookstyleRunner::Git::RepoContext) }
    def create_context(repo_name, owner, repo_url = nil)
      # Get credentials from Authentication module
      credentials = CookstyleRunner::Authentication.github_credentials

      # Prepare parameters based on credential type
      auth_params = case credentials.auth_type
                    when :pat
                      { github_token: credentials.token }
                    when :app
                      {
                        app_id: credentials.app_id,
                        installation_id: credentials.installation_id,
                        private_key: credentials.private_key
                      }
                    else
                      {} # No auth available
                    end

      # Use RepoContext directly
      CookstyleRunner::Git::RepoContext.new(
        repo_name: repo_name,
        owner: owner,
        repo_dir: nil, # Pass nil explicitly for default base_dir calculation
        repo_url: repo_url,
        github_token: auth_params[:github_token],
        app_id: auth_params[:app_id],
        installation_id: auth_params[:installation_id],
        private_key: auth_params[:private_key]
      )
    end
    # rubocop:enable Metrics/MethodLength
  end
end
