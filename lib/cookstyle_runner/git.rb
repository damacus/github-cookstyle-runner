# frozen_string_literal: true
# typed: strict

require 'logger'
require 'fileutils'
require 'git'
require_relative 'authentication'
require_relative '../../config/initializers/config' unless defined?(Settings)
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
      attr_reader :repo_name, :owner, :logger, :repo_url, :repo_dir, :github_token, :app_id, :installation_id, :private_key

      def initialize(repo_name:, owner:, logger:, base_dir: Dir.pwd, repo_dir: nil, repo_url: nil, github_token: nil, app_id: nil,
                     installation_id: nil, private_key: nil)
        repo_dir_val = repo_dir || File.join(base_dir, owner, repo_name)
        repo_url_val = repo_url || "https://github.com/#{owner}/#{repo_name}.git"
        @repo_name = T.let(repo_name, String)
        @owner = T.let(owner, String)
        @logger = T.let(logger, Logger)
        @repo_url = T.let(repo_url_val, String)
        @repo_dir = T.let(repo_dir_val, String)
        @github_token = T.let(github_token, T.nilable(String))
        @app_id = T.let(app_id, T.nilable(String))
        @installation_id = T.let(installation_id, T.nilable(Integer))
        @private_key = T.let(private_key, T.nilable(String))
        FileUtils.mkdir_p(@repo_dir)
      end
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
    def self.latest_commit_sha(repo_dir, logger)
      repo = ::Git.open(repo_dir)
      repo.object('HEAD').sha
    rescue StandardError => e
      logger.error("Failed to get latest commit SHA: #{e.message}")
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
      context.logger.error("Error ensuring repo latest state: #{e.message}")
      nil
    end

    # Get authenticated URL for git operations based on auth method in context
    # Exits if authentication fails
    def self.authenticated_url(context)
      CookstyleRunner::Authentication.authenticated_url(context.owner, context.repo_name, context.logger)
    rescue StandardError => e
      context.logger.error("Authentication failed: #{e.message}")
      exit(1)
    end

    # Update the repository to the specified branch
    # Returns the repo object, or nil if an error occurs
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
      context.logger.error("Error updating repo #{context.repo_name}: #{e.message}")
      nil
    end

    # Clone the repository and checkout the branch
    # Returns the repo object, or nil if an error occurs
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
    rescue StandardError => e
      context.logger.error("Error ensuring repo latest state: #{e.message}")
      nil
    end

    # Checkout or create a branch from remote
    def self.checkout_branch(context, branch)
      repo = ::Git.open(context.repo_dir)
      repo.checkout(branch)
      true
    rescue ::Git::Error
      context.logger.info("Branch #{branch} not found, creating new branch.")
      repo.branch(branch).checkout
      true
    rescue StandardError => e
      context.logger.error("Git checkout failed for branch #{branch}: #{e.message}")
      false
    end

    # Get the current commit SHA
    def self.current_commit_sha(context)
      repo = ::Git.open(context.repo_dir)
      repo.object('HEAD').sha
    rescue StandardError => e
      context.logger.error("Failed to get current commit SHA: #{e.message}")
      nil
    end

    # Check if there are changes to commit
    def self.changes_to_commit?(context)
      repo = ::Git.open(context.repo_dir)
      changes = changes?(repo)
      context.logger.info("Changes to commit found for #{context.repo_name}: #{changes}")
      changes
    rescue ::Git::Error => e
      context.logger.error("Failed to check for changes to commit: #{e.message}")
      false
    end

    # Accept T.untyped for testability with RSpec doubles (Sorbet does not accept instance doubles as ::Git::Base)
    def self.changes?(repo)
      repo.status.changed.any? || repo.status.added.any? || repo.status.deleted.any?
    end

    # Add and commit local changes
    def self.add_and_commit_changes(context, commit_message, git_config: {})
      return false unless changes_to_commit?(context)

      setup_git_config_from_hash(git_config, context.logger)

      repo = ::Git.open(context.repo_dir)
      repo.add(all: true)
      commit_result = repo.commit(commit_message)
      context.logger.debug("Committed changes locally with message: #{commit_message}")
      commit_result
    rescue StandardError => e
      context.logger.error("Failed to add and commit local changes: #{e.message}")
      false
    end

    # Push the current branch to the remote repository
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
    def self.remove_origin_remote_if_exists(repo, remote_name, context)
      existing_remote = repo.remotes.find { |r| r.name == remote_name }
      return unless existing_remote

      repo.remote(remote_name).remove
      context.logger.debug("Removed existing remote '#{remote_name}'")
    end

    # Push changes to the remote repository
    def self.push_to_remote(repo, context, branch_name)
      repo.push('origin', branch_name, force: true)
      context.logger.info("Pushed changes to origin/#{branch_name} for #{context.repo_name}")
      true
    rescue StandardError => e
      context.logger.error("Error pushing to origin/#{branch_name} for #{context.repo_name}: #{e.message}")
      false
    end

    # Configure git user.name and user.email globally
    def self.setup_git_config(user_name:, user_email:, logger:)
      ::Git.global_config('user.name', user_name)
      ::Git.global_config('user.email', user_email)
      logger.debug("Configured git user.name='#{user_name}', user.email='#{user_email}'")
      true
    rescue StandardError => e
      logger.error("Failed to configure git user: #{e.message}")
      false
    end

    # Setup git config from hash if credentials are provided
    sig { params(git_config: T::Hash[Symbol, T.untyped], logger: Logger).void }
    private_class_method def self.setup_git_config_from_hash(git_config, logger)
      return unless git_config[:git_user_name] && git_config[:git_user_email]

      setup_git_config(
        user_name: git_config[:git_user_name],
        user_email: git_config[:git_user_email],
        logger: logger
      )
    end

    # Helper method to delete, create, and checkout a branch
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

    def self.commit_and_push_changes(context, commit_message)
      repo = ::Git.open(context.repo_dir)
      branch_name = ::Settings.branch_name

      repo.remote(branch_name).remove if repo.remotes.any? { |r| r.name == branch_name }
      repo.add_remote(branch_name, authenticated_url(context))
      commit_changes(context, commit_message)
      repo.push(branch_name, branch_name, force: true)

      true
    rescue StandardError => e
      context.logger.error("Failed to commit and push changes: #{e.message}")
      false
    end

    def self.commit_changes(context, commit_message)
      begin
        repo = ::Git.open(context.repo_dir)
      rescue StandardError => e
        context.logger.error("Failed to commit and push changes: #{e.message}")
        return false
      end

      begin
        repo.add(all: true)
        repo.commit(commit_message)
      rescue StandardError => e
        context.logger.error("Error committing changes in #{context.repo_dir}: #{e.message}")
        false
      end
    end
  end
end
