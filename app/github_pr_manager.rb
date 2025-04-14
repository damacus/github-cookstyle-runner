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

# Manages GitHub pull request operations
class GitHubPRManager
  attr_reader :logger, :config

  # Initialize the PR manager
  # @param config [Hash] Configuration hash
  # @param logger [Logger] Logger instance
  def initialize(config, logger)
    @config = config
    @logger = logger
    @github_client = nil
  end

  # Create a pull request for cookstyle fixes
  # @param repo_name [String] Repository name
  # @param repo_dir [String] Repository directory
  # @param cookstyle_output [String] Output from cookstyle run
  # @param manual_fix [Boolean] Whether this is a PR for manual fixes (no changes committed)
  # @return [Boolean] True if PR was created successfully
  def create_pull_request(repo_name, repo_dir, cookstyle_output, manual_fix = false)
    # Ensure we're in the repository directory
    Dir.chdir(repo_dir) do
      # For regular PRs, check if there are changes to commit
      unless manual_fix || changes_to_commit?
        logger.info("No changes to commit for #{repo_name}")
        return false
      end

      # Create a new branch for the fixes
      create_branch(repo_name)

      # For manual fix PRs, we need to create an empty commit
      if manual_fix
        # Create an empty commit for manual fixes
        create_empty_commit(repo_name)
      else
        # Update changelog if configured (only for auto-fix PRs)
        update_changelog(repo_name) if config[:manage_changelog]

        # Commit and push changes
        unless commit_and_push_changes(repo_name)
          logger.error("Failed to commit and push changes for #{repo_name}")
          return false
        end
      end

      # Create the PR on GitHub
      pr_title = manual_fix ? "Manual Fix Required: Cookstyle Issues" : config[:pr_title]
      pr = create_github_pr(repo_name, cookstyle_output, pr_title, manual_fix)
      if pr
        logger.info("Successfully created PR ##{pr.number} for #{repo_name}: #{pr.html_url}")
        return true
      else
        logger.error("Failed to create PR for #{repo_name}")
        return false
      end
    end
  rescue StandardError => e
    logger.error("Error creating pull request for #{repo_name}: #{e.message}")
    logger.debug(e.backtrace.join("\n"))
    false
  end

  private

  # Check if there are changes to commit
  # @return [Boolean] True if there are changes
  def changes_to_commit?
    stdout, _stderr, status = Open3.capture3('git status --porcelain')
    status.success? && !stdout.strip.empty?
  end

  # Create a new branch for cookstyle fixes
  # @param repo_name [String] Repository name
  # @return [Boolean] True if branch was created successfully
  def create_branch(repo_name)
    branch_name = config[:branch_name]
    default_branch = config[:default_branch]
    
    # Fetch latest changes
    system('git fetch origin')
    
    # Check if branch already exists
    if branch_exists?(branch_name)
      logger.info("Branch #{branch_name} already exists for #{repo_name}, checking out")
      system("git checkout #{branch_name}")
      system("git reset --hard origin/#{default_branch}")
    else
      logger.info("Creating branch #{branch_name} for #{repo_name}")
      system("git checkout -b #{branch_name} origin/#{default_branch}")
    end
    
    # Configure git user
    system("git config user.name \"#{config[:git_name]}\"")
    system("git config user.email \"#{config[:git_email]}\"")
    
    $?.success?
  end

  # Check if a branch exists
  # @param branch_name [String] Branch name
  # @return [Boolean] True if branch exists
  def branch_exists?(branch_name)
    system("git branch --list #{branch_name} | grep -q #{branch_name}")
  end

  # Update the changelog with cookstyle fixes
  # @param repo_name [String] Repository name
  def update_changelog(repo_name)
    changelog_file = config[:changelog_location]
    marker = config[:changelog_marker]

    return unless File.exist?(changelog_file)

    logger.info("Updating changelog at #{changelog_file} for #{repo_name}")

    content = File.read(changelog_file)
    today = Time.now.strftime('%Y-%m-%d')

    if content.include?(marker)
      new_content = content.gsub(marker, "#{marker}\n- Cookstyle auto-corrections applied on #{today}")
      File.write(changelog_file, new_content)
      logger.info("Changelog updated successfully for #{repo_name}")
    else
      logger.warn("Changelog marker '#{marker}' not found in #{changelog_file} for #{repo_name}")
    end
  rescue StandardError => e
    logger.error("Error updating changelog for #{repo_name}: #{e.message}")
  end

  # Commit and push changes
  # @param repo_name [String] Repository name
  # @return [Boolean] True if commit and push were successful
  def commit_and_push_changes(repo_name)
    logger.info("Committing and pushing changes for #{repo_name}")

    # Add all changes
    system('git add .')

    # Commit changes
    commit_message = "#{config[:pr_title]}\n\nSigned-off-by: #{config[:git_name]} <#{config[:git_email]}>"
    system("git commit -m \"#{commit_message}\"")

    # Push to remote
    system("git push -u origin #{config[:branch_name]} -f")

    $?.success?
  rescue StandardError => e
    logger.error("Error committing and pushing changes for #{repo_name}: #{e.message}")
    false
  end
  
  # Create an empty commit for manual fix PRs
  # @param repo_name [String] Repository name
  # @return [Boolean] True if commit and push were successful
  def create_empty_commit(repo_name)
    logger.info("Creating empty commit for manual fixes in #{repo_name}")
    
    # Create an empty commit
    commit_message = "Manual cookstyle fixes required\n\nThis is an empty commit to create a PR for manual cookstyle fixes.\n\nSigned-off-by: #{config[:git_name]} <#{config[:git_email]}>"
    system("git commit --allow-empty -m \"#{commit_message}\"")
    
    # Push to remote
    system("git push -u origin #{config[:branch_name]} -f")
    
    $?.success?
  rescue StandardError => e
    logger.error("Error creating empty commit for #{repo_name}: #{e.message}")
    false
  end

  # Create a pull request on GitHub
  # @param repo_name [String] Repository name
  # @param cookstyle_output [String] Output from cookstyle run
  # @param pr_title [String] Pull request title
  # @param manual_fix [Boolean] Whether this is a PR for manual fixes
  # @return [Sawyer::Resource, nil] PR object or nil if failed
  def create_github_pr(repo_name, cookstyle_output, pr_title = nil, manual_fix = false)
    repo_full_name = "#{config[:owner]}/#{repo_name}"
    logger.info("Creating pull request for #{repo_full_name}")

    # Format PR body with cookstyle output
    pr_body = manual_fix ? format_manual_fix_pr_body(cookstyle_output) : format_pr_body(cookstyle_output)

    # Use provided title or default
    title = pr_title || config[:pr_title]

    # Create the pull request
    pr = github_client.create_pull_request(
      repo_full_name,
      config[:default_branch],
      config[:branch_name],
      title,
      pr_body
    )

    # Add labels if specified
    if config[:pr_labels]&.any?
      github_client.add_labels_to_an_issue(
        repo_full_name,
        pr.number,
        config[:pr_labels]
      )
      logger.info("Added labels #{config[:pr_labels].join(', ')} to PR ##{pr.number}")
    end

    pr
  rescue Octokit::UnprocessableEntity => e
    if e.message.include?('A pull request already exists')
      logger.info("Pull request already exists for #{repo_full_name}")
      # Find the existing PR
      prs = github_client.pull_requests(repo_full_name, head: "#{config[:owner]}:#{config[:branch_name]}")
      prs.first if prs.any?
    else
      logger.error("Error creating pull request for #{repo_full_name}: #{e.message}")
      nil
    end
  rescue StandardError => e
    logger.error("Error creating pull request for #{repo_full_name}: #{e.message}")
    nil
  end

  # Format the PR body with cookstyle output for auto-fixes
  # @param cookstyle_output [String] Output from cookstyle run
  # @return [String] Formatted PR body
  def format_pr_body(cookstyle_output)
    <<~BODY
      ## Cookstyle Auto-corrections

      This PR applies automatic cookstyle fixes using the latest version.

      ### Changes Made

      ```
      #{cookstyle_output.to_s.strip}
      ```

      ### Verification Steps

      - [ ] All tests pass
      - [ ] Cookbook version has been bumped if appropriate
      - [ ] Changelog has been updated if appropriate

      Automated PR created by GitHub Cookstyle Runner
    BODY
  end
  
  # Format the PR body for manual fixes
  # @param cookstyle_output [String] Output from cookstyle run with issues
  # @return [String] Formatted PR body for manual fixes
  def format_manual_fix_pr_body(cookstyle_output)
    <<~BODY
      ## Cookstyle Issues Requiring Manual Fixes

      This PR highlights cookstyle issues that require manual intervention.
      These issues cannot be automatically fixed by cookstyle's auto-correction.

      ### Issues Detected

      ```
      #{cookstyle_output.to_s.strip}
      ```

      ### Required Actions

      1. Review the issues listed above
      2. Make the necessary manual changes to address them
      3. Run cookstyle again to verify the issues are resolved
      4. Update tests if necessary
      5. Update version and changelog if appropriate

      Automated PR created by GitHub Cookstyle Runner
    BODY
  end

  # Get or create GitHub client
  # @return [Octokit::Client] GitHub client
  def github_client
    @github_client ||= Octokit::Client.new(
      access_token: ENV['GITHUB_TOKEN'],
      auto_paginate: true
    )
  end
end
