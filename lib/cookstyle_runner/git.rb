# frozen_string_literal: true
# typed: strict

require 'logger'
require 'fileutils'
require 'git'
require_relative 'authentication'
require 'sorbet-runtime'

module CookstyleRunner
  # Handle Git operations
  module Git
    extend T::Sig
    # Constants
    # Type the constant using T.let
    REPO_BASE_DIR = T.let(File.join(Dir.pwd, 'tmp', 'repositories'), String)

    # Context object for git operations
    # Holds repository information and authentication details
    class RepoContext
      extend T::Sig # Added extend T::Sig

      sig { returns(String) }
      attr_reader :repo_name

      sig { returns(String) }
      attr_reader :owner

      sig { returns(Logger) }
      attr_reader :logger

      sig { returns(String) }
      attr_reader :repo_url

      sig { returns(String) }
      attr_reader :repo_dir

      sig { returns(T.nilable(String)) }
      attr_reader :github_token

      sig { returns(T.nilable(String)) }
      attr_reader :app_id

      sig { returns(T.nilable(Integer)) }
      attr_reader :installation_id

      sig { returns(T.nilable(String)) }
      attr_reader :private_key

      # Initialize a repository context with either token or GitHub App authentication
      # rubocop:disable Metrics/ParameterLists, Metrics/AbcSize
      sig do
        params(repo_name: String, owner: String, logger: Logger, base_dir: String, repo_dir: T.nilable(String), repo_url: T.nilable(String),
               github_token: T.nilable(String), app_id: T.nilable(String), installation_id: T.nilable(Integer), private_key: T.nilable(String)).void
      end
      def initialize(repo_name:, owner:, logger:, base_dir: REPO_BASE_DIR, repo_dir: nil, repo_url: nil,
                     github_token: nil, app_id: nil, installation_id: nil, private_key: nil)
        # Declare all instance variables with T.let first
        @repo_name = T.let(repo_name, String)
        @owner = T.let(owner, String)
        @logger = T.let(logger, Logger)
        # Handle potentially nil repo_url and repo_dir before assignment
        repo_url_val = T.let(repo_url || "https://github.com/#{owner}/#{repo_name}.git", String)
        repo_dir_val = T.let(repo_dir || File.join(base_dir, owner, repo_name), String)
        @repo_url = T.let(repo_url_val, String)
        @repo_dir = T.let(repo_dir_val, String)
        @github_token = T.let(github_token, T.nilable(String))
        @app_id = T.let(app_id, T.nilable(String))
        @installation_id = T.let(installation_id, T.nilable(Integer))
        @private_key = T.let(private_key, T.nilable(String))

        # Now use the typed instance variables
        # Assignments are implicitly handled by T.let above

        FileUtils.mkdir_p(@repo_dir)
      end
      # rubocop:enable Metrics/ParameterLists, Metrics/AbcSize
    end

    # Check if a git repository exists in the directory
    sig { params(context: RepoContext).returns(T::Boolean) }
    def self.repo_exists?(context)
      Dir.exist?(File.join(context.repo_dir)) &&
        # check if folder is a git repository
        begin
          ::Git.open(context.repo_dir)
          true
        rescue StandardError
          false
        end
    end

    # Create a new branch for cookstyle fixes using GitHub API
    # Deletes the existing branch if there is one
    sig { params(context: RepoContext, config: T::Hash[Symbol, T.untyped], logger: Logger).returns(T::Boolean) }
    def self.create_branch(context, config, logger)
      setup_git_config(user_name: config[:git_user_name], user_email: config[:git_user_email], logger: logger)
      repo = ::Git.open(context.repo_dir)
      _manage_branch_lifecycle(repo, config[:branch_name], logger)
      true
    rescue ::Git::Error => e
      logger.error("Failed to create branch #{config[:branch_name]}: #{e.message}")
      false
    end

    # Get the latest commit SHA for the repository
    sig { params(repo_dir: String, logger: Logger).returns(T.nilable(String)) }
    def self.get_latest_commit_sha(repo_dir, logger)
      repo = ::Git.open(repo_dir)
      repo.object('HEAD').sha
    rescue StandardError => e
      logger.error("Failed to get latest commit SHA: #{e.message}")
      nil
    end

    # Ensure the repository exists locally and is up-to-date
    sig { params(context: RepoContext, config: T::Hash[Symbol, T.untyped]).returns(T.nilable(::Git::Base)) }
    def self.clone_or_update_repo(context, config)
      # Get authenticated URL for cloning/fetching (may raise authentication error)
      authed_url = authenticated_url(context)

      # Clone or update based on whether repo already exists
      repo_exists?(context) ? update_repo(context, config[:branch_name]) : clone_repo(context, authed_url, config[:branch_name])
    rescue StandardError => e
      context.logger.error("Error when ensuring repository is up to date: #{e.message}")
      context.logger.debug(T.must(e.backtrace).join("\n"))
      exit(1)
    end

    # Get authenticated URL for git operations based on auth method in context
    sig { params(context: RepoContext).returns(String) }
    def self.authenticated_url(context)
      credentials = CookstyleRunner::Authentication.github_credentials
      return unless credentials.valid?

      if credentials.auth_type == :pat
        "https://#{credentials.token}:x-oauth-basic@github.com/#{context.owner}/#{context.repo_name}.git"
      elsif credentials.auth_type == :app
        token = CookstyleRunner::Authentication.get_installation_token(
          app_id: T.must(credentials.app_id),
          installation_id: T.must(credentials.installation_id),
          private_key: T.must(credentials.private_key)
        )
        "https://x-access-token:#{token}@github.com/#{context.owner}/#{context.repo_name}.git"
      else
        context.logger.error("No valid authentication found for #{context.repo_name}")
        "https://github.com/#{context.owner}/#{context.repo_name}.git"
      end
    end

    # Update the repository to the specified branch
    sig { params(context: RepoContext, branch: String).returns(T.nilable(::Git::Base)) }
    def self.update_repo(context, branch)
      context.logger.debug("Updating repository #{context.repo_name} on branch #{branch}")
      repo = ::Git.open(context.repo_dir)
      repo.fetch('origin')
      repo.checkout(branch)
      repo.pull('origin', branch)
      repo.clean(force: true, d: true, f: true)
      context.logger.debug("Fetched and updated repository #{context.repo_name} on branch #{branch}")
      repo
    rescue StandardError => e
      context.logger.error("Error when updating repository #{context.repo_name}: #{e.message}")
      nil
    end

    # Add basic sig for clone_repo
    sig { params(context: RepoContext, authed_url: String, branch: String).returns(T.nilable(::Git::Base)) }
    def self.clone_repo(context, authed_url, branch)
      context.logger.debug("Cloning repository #{context.repo_name} from #{authed_url} to #{context.repo_dir}")
      repo = ::Git.clone(authed_url, context.repo_dir)
      begin
        repo.checkout(branch)
      rescue ::Git::Error
        context.logger.warn("Branch #{branch} does not exist yet in #{context.repo_name}, checked out default.")
      end
      context.logger.debug("Cloned repository #{context.repo_name} to #{context.repo_dir}")
      repo
    end

    # Checkout or create a branch from remote
    sig { params(context: RepoContext, branch: String).returns(T::Boolean) }
    def self.checkout_branch(context, branch)
      repo = ::Git.open(context.repo_dir)
      begin
        repo.checkout(branch)
      rescue ::Git::Error
        context.logger.info("Branch #{branch} not found, creating new branch.")
        repo.branch(branch).checkout
      end
      true
    rescue StandardError => e
      context.logger.error("Git checkout failed for branch #{branch}: #{e.message}")
      false
    end

    # Get the current commit SHA
    sig { params(context: RepoContext).returns(T.nilable(String)) }
    def self.current_commit_sha(context)
      repo = ::Git.open(context.repo_dir)
      repo.object('HEAD').sha
    rescue StandardError => e
      context.logger.error("Failed to get current commit SHA: #{e.message}")
      nil
    end

    # Check if there are changes to commit
    sig { params(context: RepoContext).returns(T::Boolean) }
    def self.changes_to_commit?(context)
      repo = ::Git.open(context.repo_dir)
      changes = changes?(repo)
      context.logger.info("Changes to commit found for #{context.repo_name}: #{changes}")
      changes
    rescue ::Git::Error => e
      context.logger.error("Failed to check for changes to commit: #{e.message}")
      false
    end

    # Add basic sig for changes?
    sig { params(repo: ::Git::Base).returns(T::Boolean) }
    def self.changes?(repo)
      repo.status.changed.any? || repo.status.added.any? || repo.status.deleted.any?
    end

    # Add and commit local changes
    sig { params(context: RepoContext, commit_message: String).returns(T::Boolean) }
    def self.add_and_commit_changes(context, commit_message)
      repo = ::Git.open(context.repo_dir)
      repo.add(all: true)
      repo.commit(commit_message)
      context.logger.debug("Committed changes locally with message: #{commit_message}")
      true
    rescue StandardError => e
      context.logger.error("Failed to add and commit local changes: #{e.message}")
      false
    end

    # Push the current branch to the remote repository
    sig { params(context: RepoContext, branch_name: String).returns(T::Boolean) }
    def self.push_branch(context, branch_name)
      repo = ::Git.open(context.repo_dir)
      # Commit should happen before this
      setup_remote(repo, context)
      push_to_remote(repo, context, branch_name)
    rescue StandardError => e
      context.logger.error("Failed to push branch #{branch_name}: #{e.message}")
      false
    end

    # Configure remote repository URL
    sig { params(repo: ::Git::Base, context: RepoContext).returns(T::Boolean) }
    def self.setup_remote(repo, context)
      remove_origin_remote_if_exists(repo, 'origin', context)
      repo.add_remote('origin', authenticated_url(context))
      repo.fetch('origin')
      true
    rescue StandardError => e
      context.logger.error("Error setting up remote for #{context.repo_name}: #{e.message}")
      false
    end

    # Remove the 'origin' remote if it exists, with logging
    sig { params(repo: ::Git::Base, remote_name: String, context: RepoContext).void }
    def self.remove_origin_remote_if_exists(repo, remote_name, context)
      existing_remote = repo.remotes.find { |r| r.name == remote_name }
      return unless existing_remote

      repo.remote(remote_name).remove
      context.logger.debug("Removed existing remote '#{remote_name}'")
    end

    # Push changes to the remote repository
    sig { params(repo: ::Git::Base, context: RepoContext, branch_name: String).returns(T::Boolean) }
    def self.push_to_remote(repo, context, branch_name)
      repo.push('origin', branch_name, force: true)
      context.logger.info("Pushed changes to origin/#{branch_name} for #{context.repo_name}")
      true
    rescue StandardError => e
      context.logger.error("Error pushing to origin/#{branch_name} for #{context.repo_name}: #{e.message}")
      false
    end

    # Configure git user.name and user.email globally
    sig { params(user_name: String, user_email: String, logger: Logger).returns(T::Boolean) }
    def self.setup_git_config(user_name:, user_email:, logger:)
      ::Git.global_config('user.name', user_name)
      ::Git.global_config('user.email', user_email)
      logger.debug("Configured git user.name='#{user_name}', user.email='#{user_email}'")
      true
    rescue StandardError => e
      logger.error("Failed to configure git user: #{e.message}")
      false
    end

    # Helper method to delete, create, and checkout a branch
    sig { params(repo: ::Git::Base, branch_name: String, logger: Logger).void }
    def self._manage_branch_lifecycle(repo, branch_name, logger)
      logger.debug("Managing lifecycle for branch '#{branch_name}'")
      repo.branch(branch_name).delete if repo.branches.map(&:name).include?(branch_name)
      repo.branch(branch_name).create
      repo.branch(branch_name).checkout
      logger.info("Created and checked out branch '#{branch_name}' locally.")
    rescue ::Git::Error => e
      logger.error("Failed to manage branch lifecycle for '#{branch_name}': #{e.message}")
      raise
    end
  end
end
