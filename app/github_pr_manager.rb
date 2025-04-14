#!/usr/bin/env ruby
# frozen_string_literal: true

# =============================================================================
# GitHub Cookstyle Runner - Pull Request Manager
# =============================================================================
#
# This class handles all GitHub Pull Request related operations including:
# - Creating branches for cookstyle fixes
# - Committing and pushing changes
# - Creating pull requests with appropriate labels
# - Updating PR descriptions with cookstyle fix details
#

require 'octokit'
require 'logger'
require 'fileutils'
require 'open3'

# Load our library modules
require_relative '../lib/git_operations'
require_relative '../lib/github_api'
require_relative '../lib/cookstyle_operations'

# Manages GitHub pull request operations
class GitHubPRManager
  attr_reader :logger, :config, :github_client

  # Initialize the PR manager
  # @param config [Hash] Configuration hash
  # @param logger [Logger] Logger instance
  def initialize(config, logger)
    @config = config
    @logger = logger
    @github_token = ENV['GITHUB_TOKEN']

    # Initialize GitHub client using our GitHub API module
    @github_client = GitHubAPI.create_client(@github_token)
  end

  # Create a pull request for cookstyle fixes
  # @param repo_name [String] Repository name
  # @param repo_dir [String] Repository directory
  # @param cookstyle_output [String] Output from cookstyle run
  # @param manual_fix [Boolean] Whether this is a PR for manual fixes (no changes committed)
  # @return [Array<Boolean, Hash>] Array containing [success_boolean, pr_details_hash]
  def create_pull_request(repo_name, repo_dir, cookstyle_output, manual_fix = false)
    # Ensure the repository directory exists
    unless Dir.exist?(repo_dir)
      logger.error("Repository directory does not exist: #{repo_dir}")
      return [false, nil]
    end

    # Ensure we're in the repository directory
    Dir.chdir(repo_dir) do
      # For regular PRs, check if there are changes to commit
      unless manual_fix || GitOperations.changes_to_commit?(logger)
        logger.info("No changes to commit for #{repo_name}")
        return [false, nil]
      end

      # Create a new branch for the fixes
      create_branch(repo_name)

      # For manual fix PRs, we need to create an empty commit
      if manual_fix
        # Create an empty commit for manual fixes
        commit_message = "Manual cookstyle fixes required\n\nThis is an empty commit to create a PR for manual cookstyle fixes.\n\nSigned-off-by: #{config[:git_name]} <#{config[:git_email]}>"
        GitOperations.create_empty_commit(repo_name, config[:branch_name], commit_message, @github_token,
                                          config[:owner], logger)
      else
        # Update changelog if configured (only for auto-fix PRs)
        if config[:manage_changelog]
          GitOperations.update_changelog(repo_name, config[:changelog_location], config[:changelog_marker], logger)
        end

        # Commit and push changes
        commit_message = "#{config[:pr_title]}\n\nSigned-off-by: #{config[:git_name]} <#{config[:git_email]}>"
        unless GitOperations.commit_and_push_changes(repo_name, config[:branch_name], commit_message, @github_token,
                                                     config[:owner], logger)
          logger.error("Failed to commit and push changes for #{repo_name}")
          return [false, nil]
        end
      end

      # Create the PR on GitHub
      pr_title = manual_fix ? 'Manual Fix Required: Cookstyle Issues' : config[:pr_title]
      pr = create_github_pr(repo_name, cookstyle_output, pr_title, manual_fix)
      if pr
        logger.info("Successfully created PR ##{pr.number} for #{repo_name}: #{pr.html_url}")
        # Return success boolean and PR details hash
        return [true, {
          number: pr.number,
          html_url: pr.html_url,
          title: pr_title
        }]
      else
        logger.error("Failed to create PR for #{repo_name}")
        return [false, nil]
      end
    end
  rescue StandardError => e
    logger.error("Error creating pull request for #{repo_name}: #{e.message}")
    logger.debug(e.backtrace.join("\n"))
    [false, nil]
  end

  private

  # Create a new branch for cookstyle fixes using GitHub API
  # @param repo_name [String] Repository name
  # @return [Boolean] True if branch was created successfully
  def create_branch(repo_name)
    repo_full_name = "#{config[:owner]}/#{repo_name}"

    # Use the GitHub API module to create or update the branch
    branch_created = GitHubAPI.create_or_update_branch(
      github_client,
      repo_full_name,
      config[:branch_name],
      config[:default_branch],
      logger
    )

    if branch_created
      # Use the Git Operations module to set up the local branch
      GitOperations.create_local_branch(
        repo_name,
        config[:branch_name],
        config[:default_branch],
        config[:git_name],
        config[:git_email],
        logger
      )
    else
      false
    end
  end

  # Check if a branch exists using GitHub API
  # @param repo_name [String] Repository name
  # @param branch_name [String] Branch name
  # @return [Boolean] True if branch exists
  def branch_exists?(repo_name, branch_name)
    repo_full_name = "#{config[:owner]}/#{repo_name}"
    GitHubAPI.branch_exists?(github_client, repo_full_name, branch_name, logger)
  end

  # Find an existing PR for the branch
  # @param repo_name [String] Repository name
  # @return [Sawyer::Resource, nil] Pull request object or nil if not found
  def find_existing_pr(repo_name)
    repo_full_name = "#{config[:owner]}/#{repo_name}"
    GitHubAPI.find_existing_pr(github_client, repo_full_name, config[:branch_name], logger)
  end

  # This method is now handled by GitOperations.update_changelog

  # This method is now handled by GitOperations.commit_and_push_changes

  # This method is now handled by GitOperations.create_empty_commit

  # Create a pull request on GitHub
  # @param repo_name [String] Repository name
  # @param cookstyle_output [String] Output from cookstyle run
  # @param pr_title [String] Pull request title
  # @param manual_fix [Boolean] Whether this is a PR for manual fixes
  # @return [Sawyer::Resource, nil] PR object or nil if failed
  def create_github_pr(repo_name, cookstyle_output, pr_title = nil, manual_fix = false)
    repo_full_name = "#{config[:owner]}/#{repo_name}"

    # Format PR body with cookstyle output using our GitHubAPI module
    pr_body = if manual_fix
                GitHubAPI.format_manual_fix_pr_body(cookstyle_output)
              else
                GitHubAPI.format_pr_body(cookstyle_output)
              end

    # Use provided title or default
    title = pr_title || config[:pr_title]

    # Use the GitHub API module to create or update the PR
    GitHubAPI.create_or_update_pr(
      github_client,
      repo_full_name,
      config[:branch_name],
      config[:default_branch],
      title,
      pr_body,
      config[:pr_labels],
      logger
    )
  rescue Octokit::UnprocessableEntity => e
    if e.message.include?('A pull request already exists')
      logger.info('Pull request creation failed but one might exist, trying to find it')
      # Fallback to find the existing PR if our find_existing_pr method failed
      prs = github_client.pull_requests(repo_full_name, head: "#{config[:owner]}:#{config[:branch_name]}")
      if prs.any?
        logger.info("Found existing PR ##{prs.first.number} for #{repo_name}")
        return prs.first
      end
    end
    logger.error("Error creating pull request for #{repo_full_name}: #{e.message}")
    nil
  rescue StandardError => e
    logger.error("Error creating pull request for #{repo_full_name}: #{e.message}")
    nil
  end

  # These methods have been moved to the GitHubAPI module

  # Get or create GitHub client
  # @return [Octokit::Client] GitHub client
  # Accessor for the GitHub client
  # @return [Octokit::Client] GitHub client
  attr_reader :github_client
end
