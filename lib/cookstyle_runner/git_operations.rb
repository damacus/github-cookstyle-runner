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
  # Holds repository information and authentication details
  class RepoContext
    attr_reader :repo_name, :owner, :logger, :repo_url, :repo_dir,
                :github_token, :app_id, :installation_id, :private_key

    # Initialize a repository context with either token or GitHub App authentication
    # @param repo_name [String] Name of the repository
    # @param owner [String] Owner of the repository
    # @param logger [Logger] Logger instance
    # @param base_dir [String] Base directory for repositories
    # @param repo_dir [String, nil] Repository directory
    # @param repo_url [String, nil] Repository URL
    # @param github_token [String, nil] GitHub PAT (if using token auth)
    # @param app_id [String, nil] GitHub App ID (if using app auth)
    # @param installation_id [Integer, nil] GitHub App Installation ID (if using app auth)
    # @param private_key [String, nil] GitHub App Private Key (if using app auth)
    def initialize(repo_name:, owner:, logger:, base_dir: REPO_BASE_DIR, repo_dir: nil, repo_url: nil,
                   github_token: nil, app_id: nil, installation_id: nil, private_key: nil)
      @repo_name = repo_name
      @owner = owner
      @logger = logger
      @repo_url = repo_url || "https://github.com/#{owner}/#{repo_name}.git"
      @repo_dir = repo_dir || File.join(base_dir, owner, repo_name)

      # Store authentication details
      @github_token = github_token
      @app_id = app_id
      @installation_id = installation_id
      @private_key = private_key

      FileUtils.mkdir_p(@repo_dir)
    end
  end

  # Check if a git repository exists in the directory
  # @param context [RepoContext]
  # @return [Boolean]
  def self.repo_exists?(context)
    Dir.exist?(File.join(context.repo_dir)) &&
      # check if folder is a git repository
      begin
        Git.open(context.repo_dir)
        true
      rescue StandardError
        false
      end
  end

  # Create a new branch for cookstyle fixes using GitHub API
  # @param context [RepoContext]
  # @param config [Hash] Configuration hash
  # @param logger [Logger] Logger instance
  # @return [Boolean] True if branch was created successfully
  def self.create_branch(context, config, logger)
    repo = Git.open(context.repo_dir)
    setup_git_config(config[:git_name], config[:git_email], logger)
    repo.branch(config[:branch_name]).checkout
    logger.info("Created and checked out branch '#{config[:branch_name]}' locally for #{context.repo_name}")
    true
  end

  # Get the latest commit SHA for the repository
  # @param context [RepoContext]
  # @return [String, nil]
  def self.get_latest_commit_sha(context)
    repo = Git.open(context.repo_dir)
    repo.object('HEAD').sha
  rescue StandardError => e
    context.logger.error("Failed to get latest commit SHA: #{e.message}")
    nil
  end

  # Ensure the repository exists locally and is up-to-date
  # @param context [RepoContext] Context containing repository and authentication details
  # @param branch [String] Branch to update
  # @return [Git::Base, nil] Opened Git repo object or nil on failure
  def self.clone_or_update_repo(context, branch)
    # Get authenticated URL for cloning/fetching (may raise authentication error)
    authed_url = authenticated_url(context)

    # Clone or update based on whether repo already exists
    repo_exists?(context) ? update_repo(context, branch) : clone_repo(context, authed_url, branch)
  rescue StandardError => e
    context.logger.error("Error when ensuring repository is up to date: #{e.message}")
    context.logger.debug(e.backtrace.join("\n"))
    exit(1)
  end

  # Get authenticated URL for git operations based on auth method in context
  # @param context [RepoContext] Repository context
  # @return [String] Authenticated URL
  def self.authenticated_url(context)
    if CookstyleRunner::Authentication.use_pat?
      context.logger.debug("Using PAT authentication for #{context.repo_name}")
    end

    if CookstyleRunner::Authentication.use_pat?
      "https://#{context.github_token}:x-oauth-basic@github.com/#{context.owner}/#{context.repo_name}.git"
    else
      token = CookstyleRunner::Authentication.get_installation_token(
        app_id: context.app_id,
        installation_id: context.installation_id,
        private_key: context.private_key
      )
      "https://x-access-token:#{token}@github.com/#{context.owner}/#{context.repo_name}.git"
    end
  end

  # Update the repository to the specified branch
  # @param context [RepoContext]
  # @param branch [String] Branch to update
  # @return [Git::Base, nil] Opened Git repo object or nil on failure
  def self.update_repo(context, branch)
    context.logger.debug("Updating repository #{context.repo_name} on branch #{branch}")
    repo = Git.open(context.repo_dir)
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

  def self.clone_repo(context, authed_url, branch)
    context.logger.debug("Cloning repository #{context.repo_name} from #{authed_url} to #{context.repo_dir}")
    repo = Git.clone(authed_url, context.repo_dir)
    begin
      repo.checkout(branch)
    rescue Git::Error
      context.logger.warn("Branch #{branch} does not exist yet in #{context.repo_name}, checked out default.")
    end
    context.logger.debug("Cloned repository #{context.repo_name} to #{context.repo_dir}")
    repo
  end

  # Checkout or create a branch from remote
  # @param context [RepoContext]
  # @param branch [String] Branch to checkout/create
  # @return [Boolean]
  def self.checkout_branch(context, branch)
    repo = Git.open(context.repo_dir)
    begin
      repo.checkout(branch)
    rescue Git::Error
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
    repo.status.changed.any? || repo.status.added.any? || repo.status.deleted.any?
  rescue StandardError => e
    context.logger.error("Failed to check for changes to commit: #{e.message}")
    false
  end

  # Add and commit local changes
  # @param context [RepoContext]
  # @param commit_message [String] Commit message
  # @return [Boolean] True if successful
  def self.add_and_commit_changes(context, commit_message)
    repo = Git.open(context.repo_dir)
    repo.add(all: true)
    repo.commit(commit_message)
    context.logger.debug("Committed changes locally with message: #{commit_message}")
    true
  rescue StandardError => e
    context.logger.error("Failed to add and commit local changes: #{e.message}")
    false
  end

  # Push the current branch to the remote repository
  # @param context [RepoContext]
  # @param branch_name [String] Branch name
  # @return [Boolean] True if successful
  def self.push_branch(context, branch_name)
    repo = Git.open(context.repo_dir)
    # Commit should happen before this
    setup_remote(repo, context)
    push_to_remote(repo, context, branch_name)
  rescue StandardError => e
    context.logger.error("Failed to push branch #{branch_name}: #{e.message}")
    false
  end

  # Configure remote repository URL
  # @param repo [Git::Base] The git repository object
  # @param context [RepoContext]
  # @return [Boolean] True if successful
  def self.setup_remote(repo, context)
    remove_origin_remote_if_exists(repo, 'origin', context)
    repo.add_remote('origin', get_authenticated_url(context))
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
  # @param repo [Git::Base] The git repository object
  # @param context [RepoContext]
  # @param branch_name [String] Branch name
  # @return [Boolean] True if successful
  def self.push_to_remote(repo, context, branch_name)
    repo.push('origin', branch_name, force: true)
    context.logger.info("Pushed changes to origin/#{branch_name} for #{context.repo_name}")
    true
  rescue StandardError => e
    context.logger.error("Error pushing to origin/#{branch_name} for #{context.repo_name}: #{e.message}")
    false
  end

  # Update changelog with cookstyle fixes
  # @param context [RepoContext]
  # @param config [Hash] Configuration hash
  # @param offense_details [String] Formatted string of offenses to add
  # @return [Boolean] True if successful
  def self.update_changelog(context, config, offense_details)
    changelog_path = File.join(context.repo_dir, config[:changelog_location])
    unless File.exist?(changelog_path)
      context.logger.warn("Changelog file not found at #{changelog_path}, skipping update.")
      return false
    end

    content = File.readlines(changelog_path)
    marker_index = content.find_index { |line| line.strip.start_with?(config[:changelog_marker].strip) }

    unless marker_index
      context.logger.warn("Changelog marker '#{config[:changelog_marker]}' not found in #{changelog_path}, skipping update.")
      return false
    end

    # Find the index of the next header (line starting with '## ') after the marker
    next_header_index = content.find_index.with_index do |line, idx|
      idx > marker_index && line.strip.start_with?('## ')
    end

    # Determine insertion point
    # If no next header found, insert at the end. Otherwise, insert before the next header.
    insertion_point = next_header_index || content.length

    # Prepare entry with indentation and ensure newline
    entry = "\n#{offense_details.strip}\n"

    # Insert the offense details
    content.insert(insertion_point, entry)

    File.write(changelog_path, content.join)
    context.logger.info("Updated changelog file: #{changelog_path}")
    true
  rescue StandardError => e
    context.logger.error("Failed to update changelog: #{e.message}")
    false
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
