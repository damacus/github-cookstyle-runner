# frozen_string_literal: true
# typed: true

require 'semantic_logger'
require 'fileutils'
require 'git'
require_relative 'authentication'
require_relative '../../config/initializers/config' unless defined?(Settings)
require 'sorbet-runtime'

module CookstyleRunner
  # Handle Git operations
  module Git
    extend T::Sig

    # Module-level logger
    @log = T.let(SemanticLogger[self], SemanticLogger::Logger)

    sig { returns(SemanticLogger::Logger) }
    def self.log
      @log
    end

    # Constants
    # Type the constant using T.let
    REPO_BASE_DIR = T.let(File.join(Dir.pwd, 'tmp', 'repositories'), String)

    # Context object for git operations
    # Holds repository information and authentication details
    class RepoContext
      extend T::Sig

      attr_reader :repo_name, :owner, :repo_url, :repo_dir, :github_token, :app_id, :installation_id, :private_key

      sig do
        params(
          repo_name: String,
          owner: String,
          base_dir: String,
          repo_dir: T.nilable(String),
          repo_url: T.nilable(String),
          github_token: T.nilable(String),
          app_id: T.nilable(String),
          installation_id: T.nilable(Integer),
          private_key: T.nilable(String)
        ).void
      end
      def initialize(repo_name:, owner:, base_dir: Dir.pwd, repo_dir: nil, repo_url: nil, github_token: nil, app_id: nil,
                     installation_id: nil, private_key: nil)
        repo_dir_val = repo_dir || File.join(base_dir, owner, repo_name)
        repo_url_val = repo_url || "https://github.com/#{owner}/#{repo_name}.git"
        @repo_name = T.let(repo_name, String)
        @owner = T.let(owner, String)
        @logger = T.let(SemanticLogger[self.class], SemanticLogger::Logger)
        @repo_url = T.let(repo_url_val, String)
        @repo_dir = T.let(repo_dir_val, String)
        @github_token = T.let(github_token, T.nilable(String))
        @app_id = T.let(app_id, T.nilable(String))
        @installation_id = T.let(installation_id, T.nilable(Integer))
        @private_key = T.let(private_key, T.nilable(String))
        FileUtils.mkdir_p(@repo_dir)
      end

      sig { returns(SemanticLogger::Logger) }
      attr_reader :logger
    end

    # Check if a git repository exists in the directory
    def self.repo_exists?(context)
      ::Git.open(context.repo_dir)
      true
    rescue StandardError
      false
    end

    # Create a new branch for cookstyle fixes using GitHub API
    # Deletes the existing branch if there is one
    def self.create_branch(context, config)
      setup_git_config(user_name: config[:git_user_name], user_email: config[:git_user_email])
      repo = ::Git.open(context.repo_dir)
      _manage_branch_lifecycle(repo, config[:branch_name])
      true
    rescue ::Git::Error => e
      log.error('Failed to create branch', payload: { repo: context.repo_name, branch: config[:branch_name], error: e.message })
      false
    end

    # Get the latest commit SHA for the repository
    def self.latest_commit_sha(context)
      repo = ::Git.open(context.repo_dir)
      repo.object('HEAD').sha
    rescue StandardError => e
      log.error('Failed to get commit SHA', payload: { repo: context.repo_name, error: e.message })
      nil
    end

    # Ensure the repository exists locally and is up-to-date
    # Returns the repo object, or nil if an error occurs (except for auth failures, which exit)
    def self.clone_or_update_repo(context, config)
      repo_exists?(context) ? update_repo(context, config[:branch_name]) : clone_repo(context, authenticated_url(context), config[:branch_name])
    rescue SystemExit
      # Reraise exit for authentication failures
      raise
    rescue StandardError => e
      log.error("Error ensuring repo latest state: #{e.message}")
      nil
    end

    # Get authenticated URL for git operations based on auth method in context
    # Exits if authentication fails
    def self.authenticated_url(context)
      CookstyleRunner::Authentication.authenticated_url(context.owner, context.repo_name, log)
    rescue StandardError => e
      log.error('Git authentication failed', payload: { repo: context.repo_name, error: e.message })
      exit(1)
    end

    # Update the repository to the specified branch
    # Returns the repo object, or nil if an error occurs
    def self.update_repo(context, branch)
      log.debug('Updating repository', payload: { repo: context.repo_name, branch: branch, action: 'update' })
      repo = ::Git.open(context.repo_dir)
      repo.fetch('origin')
      repo.checkout(branch)
      repo.pull('origin', branch)
      repo.clean(force: true, d: true, f: true)
      log.debug('Repository updated successfully', payload: { repo: context.repo_name, branch: branch })
      repo
    rescue StandardError => e
      log.error('Repository update failed', payload: { repo: context.repo_name, error: e.message, action: 'update' })
      nil
    end

    # Clone the repository and checkout the branch
    # Returns the repo object, or nil if an error occurs
    def self.clone_repo(context, authed_url, branch)
      log.debug('Cloning repository', payload: { repo: context.repo_name, branch: branch, action: 'clone' })
      repo = ::Git.clone(authed_url, context.repo_dir)
      begin
        repo.checkout(branch)
      rescue ::Git::Error
        log.warn('Branch does not exist, using default', payload: { repo: context.repo_name, branch: branch })
      end
      log.debug('Repository cloned successfully', payload: { repo: context.repo_name })
      repo
    rescue StandardError => e
      log.error("Error ensuring repo latest state: #{e.message}")
      nil
    end

    # Checkout or create a branch from remote
    def self.checkout_branch(context, branch)
      repo = ::Git.open(context.repo_dir)
      repo.checkout(branch)
      true
    rescue ::Git::Error
      log.info('Creating new branch', payload: { repo: context.repo_name, branch: branch, action: 'create_branch' })
      repo.branch(branch).checkout
      true
    rescue StandardError => e
      log.error('Git checkout failed', payload: { repo: context.repo_name, branch: branch, error: e.message })
      false
    end

    # Get the current commit SHA
    def self.current_commit_sha(context)
      repo = ::Git.open(context.repo_dir)
      repo.object('HEAD').sha
    rescue StandardError => e
      log.error("Failed to get current commit SHA: #{e.message}")
      nil
    end

    # Check if there are changes to commit
    def self.changes_to_commit?(context)
      repo = ::Git.open(context.repo_dir)
      changes = changes?(repo)
      log.debug("Changes to commit found for #{context.repo_name}: #{changes}")
      changes
    rescue ::Git::Error => e
      log.error("Failed to check for changes to commit: #{e.message}")
      false
    end

    def self.changes?(repo)
      repo.status.changed.any? || repo.status.added.any? || repo.status.deleted.any?
    end

    def self.add_and_commit_changes(context, commit_message)
      return false unless changes_to_commit?(context)

      repo = ::Git.open(context.repo_dir)
      repo.add(all: true)
      repo.commit(commit_message)
    rescue StandardError => e
      log.error("Failed to add and commit local changes: #{e.message}")
      false
    end

    def self.push_branch(context, branch_name)
      repo = ::Git.open(context.repo_dir)
      setup_remote(repo, context)
      push_to_remote(repo, context, branch_name)
    rescue StandardError => e
      log.error("Failed to push branch #{branch_name}: #{e.message}")
      false
    end

    def self.setup_remote(repo, context)
      remove_existing_remote(repo, 'origin')
      repo.add_remote('origin', authenticated_url(context))
      repo.fetch('origin')
      true
    rescue StandardError => e
      log.error("Error setting up remote for #{context.repo_name}: #{e.message}")
      false
    end

    def self.remove_existing_remote(repo, remote_name)
      existing_remote = repo.remotes.find { |r| r.name == remote_name }
      return unless existing_remote

      repo.remote(remote_name).remove
    end

    def self.push_to_remote(repo, context, branch_name)
      repo.push('origin', branch_name, force: true)
      log.debug("Pushed changes to origin/#{branch_name} for #{context.repo_name}")
      true
    rescue StandardError => e
      log.error("Error pushing to origin/#{branch_name} for #{context.repo_name}: #{e.message}")
      false
    end

    # Configure git user.name and user.email globally
    sig { params(user_name: String, user_email: String).returns(T::Boolean) }
    def self.setup_git_config(user_name:, user_email:)
      ::Git.global_config('user.name', user_name)
      ::Git.global_config('user.email', user_email)
      true
    rescue StandardError => e
      log.error("Failed to configure git user: #{e.message}")
      false
    end

    # Setup git config from hash if credentials are provided
    sig { params(git_config: T::Hash[Symbol, T.untyped]).void }
    private_class_method def self.setup_git_config_from_hash(git_config)
      return unless git_config[:git_user_name] && git_config[:git_user_email]

      setup_git_config(
        user_name: git_config[:git_user_name],
        user_email: git_config[:git_user_email]
      )
    end

    sig { params(repo: T.untyped, branch_name: String).void }
    def self._manage_branch_lifecycle(repo, branch_name)
      # Check if branch exists locally and delete it
      if repo.branches.local.map(&:name).include?(branch_name)
        log.debug("Deleting existing local branch '#{branch_name}'")
        repo.branch(branch_name).delete
      end

      repo.branch(branch_name).create
      repo.branch(branch_name).checkout
      log.debug("Created and checked out branch '#{branch_name}' locally.")
    rescue ::Git::Error => e
      log.error("Failed to manage branch lifecycle for '#{branch_name}': #{e.message}")
      raise
    end

    def self.commit_and_push_changes(context, commit_message)
      repo = ::Git.open(context.repo_dir)
      branch_name = ::Settings.branch_name

      repo.remote(branch_name).remove if repo.remotes.any? { |r| r.name == branch_name }
      repo.add_remote(branch_name, authenticated_url(context))
      commit_changes(context, commit_message)
      repo.push(branch_name, branch_name, force: true)

      true
    rescue StandardError => e
      log.error("Failed to commit and push changes: #{e.message}")
      false
    end

    def self.commit_changes(context, commit_message)
      begin
        repo = ::Git.open(context.repo_dir)
      rescue StandardError => e
        log.error("Failed to commit and push changes: #{e.message}")
        return false
      end

      begin
        repo.add(all: true)
        repo.commit(commit_message)
      rescue StandardError => e
        log.error("Error committing changes in #{context.repo_dir}: #{e.message}")
        false
      end
    end
  end
end
