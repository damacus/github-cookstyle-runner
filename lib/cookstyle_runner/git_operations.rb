# frozen_string_literal: true

require 'logger'
require 'fileutils'
require 'git'

# Module for handling Git operations
module GitOperations
  # Context object for git operations
  # Holds repo_name, github_token, owner, logger
  class RepoContext
    attr_reader :repo_name, :github_token, :owner, :logger

    def initialize(repo_name:, github_token:, owner:, logger:)
      @repo_name = repo_name
      @github_token = github_token
      @owner = owner
      @logger = logger
    end
  end

  # Check if a git repository exists in the directory
  # @param context [RepoContext]
  # @return [Boolean]
  def self.repo_exists?(context)
    Dir.exist?(File.join(context.repo_dir, '.git'))
  end

  # Ensure the repository exists locally and is up-to-date
  # @param context [RepoContext]
  # @param branch [String] Branch to update (default: 'main')
  # @return [Git::Base, nil] Opened Git repo object or nil on failure
  def self.clone_or_update_repo(context, branch = 'main')
    repo_url = "https://#{context.github_token}@github.com/#{context.owner}/#{context.repo_name}.git"
    repo_exists?(context.repo_dir) ? update_repo(context, branch) : clone_repo(context, repo_url, branch)
  rescue StandardError => e
    context.logger.error("Error ensuring repo latest state: #{e.message}")
    nil
  end

  def self.update_repo(context, branch)
    repo = Git.open(context.repo_dir)
    repo.fetch('origin')
    repo.checkout(branch)
    repo.pull('origin', branch)
    repo.clean(force: true, d: true, f: true)
    context.logger.debug("Fetched and updated repo #{context.repo_name} on branch #{branch}")
    repo
  rescue StandardError => e
    context.logger.error("Error updating repo #{context.repo_name}: #{e.message}")
    nil
  end

  def self.clone_repo(context, repo_url, branch)
    repo = Git.clone(repo_url, context.repo_dir)
    begin
      repo.checkout(branch)
    rescue Git::GitExecuteError
      context.logger.warn("Branch #{branch} does not exist yet in #{context.repo_name}")
    end
    context.logger.debug("Cloned repo #{context.repo_name} to #{context.repo_dir}")
    repo
  end

  # Checkout or create a branch from remote
  # @param context [RepoContext]
  # @param branch [String] Branch to checkout/create
  # @return [Boolean]
  def self.checkout_branch(context, branch)
    repo = Git.open(context.repo_dir)
    begin
      repo.branch(branch).checkout
    rescue Git::GitExecuteError
      repo.branch(branch).checkout
    end
    true
  rescue StandardError => e
    context.logger.error("Git checkout failed: #{e.message}")
    false
  end

  # Get the current commit SHA
  # @param context [RepoContext]
  # @return [String, nil]
  def self.current_commit_sha(context)
    repo = Git.open(context.repo_dir)
    repo.object('HEAD').sha
  rescue StandardError => e
    context.logger.error("Failed to get current commit SHA: #{e.message}")
    nil
  end

  # Check if there are changes to commit
  # @param context [RepoContext]
  # @return [Boolean]
  def self.changes_to_commit?(context)
    repo = Git.open(context.repo_dir)
    !repo.status.changed.empty? || !repo.status.added.empty? || !repo.status.deleted.empty?
  rescue StandardError => e
    context.logger.error("Failed to check for changes to commit: #{e.message}")
    false
  end

  # Commit and push changes to GitHub
  # @param repo_name [String] Repository name
  # @param branch_name [String] Branch name
  # @param commit_message [String] Commit message
  # @param github_token [String] GitHub token
  # @param owner [String] Repository owner
  # @param logger [Logger] Logger instance
  # @return [Boolean] True if successful
  def self.commit_and_push_changes(context, branch_name, commit_message)
    add_and_commit_changes(commit_message, context.logger) || (return false)
    setup_remote(context)
    push_to_remote(context, branch_name)
  end

  # Add and commit all changes
  # @param context [RepoContext]
  # @param commit_message [String]
  # @return [Boolean]
  def self.add_and_commit_changes(context, commit_message)
    repo = Git.open(context.repo_dir)
    repo.add(all: true)
    repo.commit(commit_message)
    context.logger.debug("Committed changes in #{repo_dir} with message: #{commit_message}")
    true
  rescue StandardError => e
    logger.error("Error committing changes in #{repo_dir}: #{e.message}")
    false
  end

  # Set up a remote with token authentication
  # @param context [RepoContext]
  # @return [String, nil] remote name or nil on failure
  def self.setup_remote(context)
    thread_id = Thread.current.object_id
    remote_name = "origin_#{thread_id}"
    repo_url = "https://#{context.github_token}@github.com/#{context.owner}/#{context.repo_name}.git"
    repo = Git.open(context.repo_dir)
    repo.remove_remote(remote_name) if repo.remotes.map(&:name).include?(remote_name)
    repo.add_remote(remote_name, repo_url)
    context.logger.debug("Set up remote '#{remote_name}' with URL '#{repo_url}' in #{context.repo_dir}")
    remote_name
  rescue StandardError => e
    context.logger.error("Error setting up remote: #{e.message}")
    nil
  end

  # Push to the specified remote and branch
  # @param context [RepoContext]
  # @param branch_name [String]
  # @return [Boolean]
  def self.push_to_remote(context, branch_name)
    repo = Git.open(context.repo_dir)
    repo.push(context.remote_name, branch_name, force: true)
    context.logger.debug("Pushed branch '#{branch_name}' to remote '#{context.remote_name}' in #{context.repo_dir}")
    true
  rescue StandardError => e
    context.logger.error("Error pushing to remote: #{e.message}")
    false
  end

  # Create an empty commit for manual fix PRs (main orchestration)
  # @param context [RepoContext]
  # @param branch_name [String]
  # @param commit_message [String]
  # @return [Boolean]
  def self.create_empty_commit(context, branch_name, commit_message)
    repo = Git.open(context.repo_dir)
    repo.commit(commit_message, allow_empty: true)
    setup_remote(context)
    push_to_remote(context, branch_name)
  rescue StandardError => e
    context.logger.error("Error creating empty commit for #{context.repo_name}: #{e.message}")
    false
  end

  # Update changelog with cookstyle fixes
  # @param context [RepoContext]
  # @param changelog_file [String] Path to changelog file
  # @param marker [String] Marker in changelog for adding entries
  # @return [Boolean] True if successful
  # Update changelog with cookstyle fixes
  # @param context [RepoContext]
  # @param changelog_file [String] Path to changelog file
  # @param marker [String] Marker in changelog for adding entries
  # @return [Boolean] True if successful
  def self.update_changelog(context, changelog_file, marker)
    return false unless File.exist?(changelog_file)

    unless File.read(changelog_file).include?(marker)
      context.logger.warn("Changelog marker '#{marker}' not found in #{changelog_file} for #{context.repo_name}")
      return false
    end

    today = Time.now.utc.strftime('%Y-%m-%d')

    write_changelog_entry(context, changelog_file, File.read(changelog_file), marker, today)
  rescue StandardError => e
    context.logger.error("Error updating changelog for #{context.repo_name}: #{e.message}")
    false
  end

  # Helper: Write changelog entry
  def self.write_changelog_entry(context, changelog_file, content, marker, today)
    new_content = content.gsub(marker, "#{marker}\n- Cookstyle auto-corrections applied on #{today}")
    File.write(changelog_file, new_content)
    context.logger.info("Changelog updated successfully for #{context.repo_name}")
    true
  end

  # Configure git user.name and user.email globally
  # @param user_name [String] Git user name
  # @param user_email [String] Git user email
  # @param logger [Logger] Logger instance
  # @return [Boolean] True if successful
  def self.setup_git_config(user_name, user_email, logger)
    Git.global_config('user.name', user_name)
    Git.global_config('user.email', user_email)
    logger.debug("Configured git user.name='#{user_name}', user.email='#{user_email}'")
    true
  rescue StandardError => e
    logger.error("Failed to configure git user: #{e.message}")
    false
  end
end
