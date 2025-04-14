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

require_relative './git_operations'
require_relative './github_api'
require_relative './cookstyle_operations'

# Manages GitHub pull request operations
module CookstyleRunner
  class GitHubPRManager
    attr_reader :logger, :config, :github_client

    # Initialize the PR manager
    # @param config [Hash] Configuration hash
    # @param logger [Logger] Logger instance
    def initialize(config, logger)
      @config = config
      @logger = logger
      # Initialize GitHub client using our GitHub API module
      @github_client = CookstyleRunner::GitHubAPI.create_client
    end

    # Process repository with cookstyle fixes
    # @param repo_name [String] Repository name
    # @param repo_dir [String] Repository directory
    # @param cookstyle_output [String] Output from cookstyle run
    # @param manual_fix [Boolean] Whether manual fixes are required (can't be auto-fixed)
    # @return [Array<Boolean, Hash>] Success status and PR/Issue details
    def create_pull_request(repo_name, repo_dir, cookstyle_output, manual_fix: false)
      # Ensure the repository directory exists
      return [false, nil] unless Dir.exist?(repo_dir)

      # Create an issue if manual fixes are required
      return create_issue_for_manual_fixes(repo_name, cookstyle_output) if manual_fix

      # Process auto-fixable changes
      Dir.chdir(repo_dir) do
        # Check if there are changes to commit
        unless GitOperations.changes_to_commit?(logger)
          logger.info("No changes to commit for #{repo_name}")
          return [false, nil]
        end

        # Create a new branch for the fixes
        GitOperations.create_branch(
          repo_context,
          config[:branch_name],
          config[:default_branch],
          config[:git_name],
          config[:git_email],
          logger
        )

        # Update changelog if configured
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

        # Create the PR on GitHub
        repo_full_name = "#{config[:owner]}/#{repo_name}"
        pr_body = CookstyleRunner::GitHubAPI.format_pr_body(cookstyle_output)

        pr = CookstyleRunner::GitHubAPI.create_or_update_pr(
          github_client,
          repo_full_name,
          config[:branch_name],
          config[:default_branch],
          config[:pr_title],
          pr_body,
          config[:pr_labels],
          logger
        )

        if pr
          logger.info("Successfully created PR ##{pr.number} for #{repo_name}: #{pr.html_url}")
          return [true, {
            number: pr.number,
            html_url: pr.html_url,
            title: config[:pr_title],
            type: 'pull_request'
          }]
        else
          logger.error("Failed to create PR for #{repo_name}")
          return [false, nil]
        end
      end
    rescue StandardError => e
      logger.error("Error processing repository #{repo_name}: #{e.message}")
      logger.debug(e.backtrace.join("\n"))
      [false, nil]
    end

    # Create an issue for manual cookstyle fixes
    # @param repo_name [String] Repository name
    # @param cookstyle_output [String] Output from cookstyle run
    # @return [Array<Boolean, Hash>] Success status and issue details
    def create_issue_for_manual_fixes(repo_name, cookstyle_output)
      repo_full_name = "#{config[:owner]}/#{repo_name}"
      issue_title = 'Manual Fix Required: Cookstyle Issues'
      issue_body = CookstyleRunner::GitHubAPI.format_manual_fix_pr_body(cookstyle_output)
      labels = config[:pr_labels] || []

      # Add a manual-fix label if not already included
      labels = (labels + ['manual-fix']).uniq

      issue = CookstyleRunner::GitHubAPI.create_issue(
        github_client,
        repo_full_name,
        issue_title,
        issue_body,
        labels,
        logger
      )

      if issue
        logger.info("Successfully created issue ##{issue.number} for #{repo_name}: #{issue.html_url}")
        [true, {
          number: issue.number,
          html_url: issue.html_url,
          title: issue_title,
          type: 'issue'
        }]
      else
        logger.error("Failed to create issue for #{repo_name}")
        [false, nil]
      end
    rescue StandardError => e
      logger.error("Error creating issue for #{repo_name}: #{e.message}")
      logger.debug(e.backtrace.join("\n"))
      [false, nil]
    end
  end
end
