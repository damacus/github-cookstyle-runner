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

require_relative 'git_operations'
require_relative 'github_api'
require_relative 'cookstyle_operations'
require_relative 'authentication'

module CookstyleRunner
  # Manages GitHub pull request operations
  class GitHubPRManager
    attr_reader :logger, :config, :github_client

    # Initialize the PR manager
    # @param config [Hash] Configuration hash
    # @param logger [Logger] Logger instance
    def initialize(config, logger)
      @config = config
      @logger = logger
      @github_client = CookstyleRunner::Authentication.client
    end

    # Process repository with cookstyle fixes
    # @param repo_name [String] Repository name
    # @param repo_dir [String] Repository directory
    # @param cookstyle_output [String] Output from cookstyle run
    # @param context [RepoContext] The context object for the repository
    # @param manual_fix [Boolean] Whether manual fixes are required (can't be auto-fixed)
    # @return [Array<Boolean, Hash>] Success status and PR/Issue details
    # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
    def create_pull_request(repo_name, repo_dir, cookstyle_output, context, manual_fix: false)
      # Create an issue if manual fixes are required
      return create_issue_for_manual_fixes(repo_name, cookstyle_output) if manual_fix

      # rubocop:disable Metrics/BlockLength
      Dir.chdir(repo_dir) do
        # Check if there are changes to commit - Pass context
        unless GitOperations.changes_to_commit?(context)
          @logger.info("No changes to commit for #{repo_name}")
          return [false, nil]
        end

        # Create a new branch for the fixes - Pass context and config
        # Assuming config is accessible via @config instance variable
        unless GitOperations.create_branch(context, @config, @logger)
          @logger.error("Failed to create branch for #{repo_name}, cannot proceed with PR.")
          return [false, { error: 'Failed to create branch', type: 'pull_request' }]
        end

        # Update changelog if enabled - Pass context and config
        if @config[:manage_changelog]
          # Format offense details for changelog (this might need context/config access too)
          # Placeholder: Assuming cookstyle_output contains details needed
          offense_details_for_cl = '* Automated Cookstyle fixes applied.'
          GitOperations.update_changelog(context, @config, offense_details_for_cl)
        end

        # Add and commit changes - Pass context
        commit_message = "#{@config[:pr_title]}\n\nSigned-off-by: #{@config[:git_name]} <#{@config[:git_email]}>"
        unless GitOperations.add_and_commit_changes(context, commit_message)
          @logger.error("Failed to commit changes for #{repo_name}, cannot proceed with PR.")
          return [false, { error: 'Failed to commit changes', type: 'pull_request' }]
        end

        # Push the branch - Pass context
        unless GitOperations.push_branch(context, @config[:branch_name])
          @logger.error("Failed to push branch for #{repo_name}, cannot proceed with PR.")
          return [false, { error: 'Failed to push branch', type: 'pull_request' }]
        end

        # Create the PR on GitHub
        repo_full_name = "#{@config[:owner]}/#{repo_name}"
        # Format PR body (Assuming cookstyle_output is sufficient)
        pr_body = CookstyleRunner::GitHubAPI.format_pr_body(cookstyle_output)

        pr = CookstyleRunner::GitHubAPI.create_or_update_pr(
          @github_client,
          repo_full_name,
          @config[:branch_name],
          @config[:default_branch],
          @config[:pr_title],
          pr_body,
          @config[:pr_labels],
          @logger
        )

        if pr
          @logger.info("Successfully created PR ##{pr.number} for #{repo_name}: #{pr.html_url}")
          return [true, {
            number: pr.number,
            html_url: pr.html_url,
            title: @config[:pr_title],
            type: 'pull_request'
          }]
        else
          @logger.error("Failed to create PR for #{repo_name} via GitHub API")
          return [false, { error: 'GitHub API PR creation failed', type: 'pull_request' }]
        end
      end
      # rubocop:enable Metrics/BlockLength
    rescue StandardError => e
      @logger.error("Error during PR creation process for #{repo_name}: #{e.message}")
      @logger.debug(e.backtrace.join("\n"))
      [false, { error: e.message, type: 'pull_request' }]
    end
    # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity

    # Create an issue for manual cookstyle fixes
    # @param repo_name [String] Repository name
    # @param cookstyle_output [String] Output from cookstyle run
    # @return [Array<Boolean, Hash>] Success status and issue details
    # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
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
    # rubocop:enable Metrics/AbcSize, Metrics/MethodLength
  end
end
