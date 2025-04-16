# frozen_string_literal: true

require 'logger'
require 'fileutils'
require 'git'
require_relative 'authentication'

# Module for handling Git operations
module GitOperations
  # Default base directory for cloning repos
  REPO_BASE_DIR = File.join(Dir.pwd, 'tmp', 'repositories')

  # Context object for git operations
  # Holds repo_name, owner, logger, repo_url, repo_dir
  class RepoContext
    attr_reader :repo_name, :owner, :logger, :repo_url, :repo_dir, :github_token

    def initialize(repo_name:, owner:, logger:, github_token:, base_dir: REPO_BASE_DIR)
      @repo_name = repo_name
      @owner = owner
      @repo_url = "https://github.com/#{owner}/#{repo_name}.git"
      @logger = logger
      @repo_dir = File.join(base_dir, owner, repo_name)
      @github_token = github_token
      FileUtils.mkdir_p(@repo_dir) unless Dir.exist?(@repo_dir)
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
  def self.clone_or_update_repo(context, branch, app_id:, installation_id:, private_key:)
    token = Authentication.get_installation_token(app_id: app_id,
                                                 installation_id: installation_id,
                                                 private_key: private_key)
    authed_url = "https://x-access-token:#{token}@github.com/#{context.owner}/#{context.repo_name}.git"
    repo_exists?(context) ? update_repo(context, branch) : clone_repo(context, authed_url, branch)
  rescue StandardError => e
    context.logger.error("Error ensuring repo latest state: #{e.message}")
    nil
  end

  # Update the repository to the specified branch
  # @param context [RepoContext]
  # @param branch [String] Branch to update
  # @return [Git::Base, nil] Opened Git repo object or nil on failure
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

  def self.clone_repo(context, authed_url, branch)
    repo = Git.clone(authed_url, context.repo_dir)
    begin
      repo.checkout(branch)
    rescue Git::Error
      context.logger.warn("Branch #{branch} does not exist yet in #{context.repo_name}, checked out default.")
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
      # Attempt to checkout existing local or remote-tracking branch
      repo.checkout(branch)
    rescue Git::Error
      # If checkout fails (branch doesn't exist locally/remotely), create it
      context.logger.info("Branch #{branch} not found, creating new branch.")
      repo.branch(branch).checkout
    end
    true
  rescue StandardError => e
    context.logger.error("Git checkout failed for branch #{branch}: #{e.message}")
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
    repo.status.changed.any? || !repo.status.added.empty? || !repo.status.deleted.empty?
  rescue StandardError => e
    context.logger.error("Failed to check for changes to commit: #{e.message}")
    false
  end

  # Commit and push changes to GitHub
  # @param context [RepoContext]
  # @param branch_name [String] Branch name
  # @param commit_message [String] Commit message
  # @return [Boolean] True if successful
  def self.commit_and_push_changes(context, branch_name, commit_message)
    repo = Git.open(context.repo_dir)
    add_and_commit_changes(repo, context, commit_message) || (return false)
    setup_remote(repo, context)
    push_to_remote(repo, context, branch_name)
  rescue StandardError => e
    context.logger.error("Failed to commit and push changes: #{e.message}")
    false
  end

  # Add and commit all changes
  # @param repo [Git::Base] The git repository object
  # @param context [RepoContext]
  # @param commit_message [String]
  # @return [Boolean]
  def self.add_and_commit_changes(repo, context, commit_message)
    repo.add(all: true)
    repo.commit(commit_message)
    context.logger.debug("Committed changes in #{context.repo_dir} with message: #{commit_message}")
    true
  rescue StandardError => e
    context.logger.error("Error committing changes in #{context.repo_dir}: #{e.message}")
    false
  end

  # Configure remote repository URL
  # @param repo [Git::Base] The git repository object
  # @param context [RepoContext]
  # @return [Boolean] True if successful
  def self.setup_remote(repo, context)
    remote_name = 'origin'
    remote_url = "https://x-access-token:#{context.github_token}@github.com/#{context.repo_name}.git"
    existing_remote = repo.remotes.find { |r| r.name == remote_name }

    if existing_remote
      repo.remote(remote_name).remove
      context.logger.debug("Removed existing remote '#{remote_name}'")
    end

    repo.add_remote(remote_name, remote_url)
    context.logger.debug("Added remote '#{remote_name}' with URL ending in .../#{context.repo_name}.git")
    repo.fetch(remote_name) # Fetch updates from the remote
    context.logger.debug("Fetched from remote '#{remote_name}'")
    true
  rescue StandardError => e
    context.logger.error("Error setting up remote for #{context.repo_name}: #{e.message}")
    false
  end

  # Push changes to the remote repository
  # @param repo [Git::Base] The git repository object
  # @param context [RepoContext]
  # @param branch_name [String] Branch name
  # @return [Boolean] True if successful
  def self.push_to_remote(repo, context, branch_name)
    remote_name = 'origin'
    repo.push(remote_name, branch_name, force: true)
    context.logger.info("Pushed changes to #{remote_name}/#{branch_name} for #{context.repo_name}")
    true
  rescue StandardError => e
    context.logger.error("Error pushing to #{remote_name}/#{branch_name} for #{context.repo_name}: #{e.message}")
    false
  end

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
