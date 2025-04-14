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
    @github_token = ENV['GITHUB_TOKEN']
    
    # Initialize GitHub client with token
    @github_client = Octokit::Client.new(
      access_token: @github_token,
      auto_paginate: true
    )
    
    # Configure Octokit to use the right API version
    @github_client.api_endpoint = 'https://api.github.com'
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
      unless manual_fix || changes_to_commit?
        logger.info("No changes to commit for #{repo_name}")
        return [false, nil]
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
          return [false, nil]
        end
      end

      # Create the PR on GitHub
      pr_title = manual_fix ? "Manual Fix Required: Cookstyle Issues" : config[:pr_title]
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

  # Check if there are changes to commit
  # @return [Boolean] True if there are changes
  def changes_to_commit?
    stdout, _stderr, status = Open3.capture3('git status --porcelain')
    status.success? && !stdout.strip.empty?
  end

  # Create a new branch for cookstyle fixes using GitHub API
  # @param repo_name [String] Repository name
  # @return [Boolean] True if branch was created successfully
  def create_branch(repo_name)
    branch_name = config[:branch_name]
    default_branch = config[:default_branch]
    repo_full_name = "#{config[:owner]}/#{repo_name}"
    
    begin
      # Get the SHA of the default branch
      default_branch_ref = github_client.ref(repo_full_name, "heads/#{default_branch}")
      default_branch_sha = default_branch_ref.object.sha
      
      # Check if branch exists
      begin
        github_client.ref(repo_full_name, "heads/#{branch_name}")
        logger.info("Branch #{branch_name} already exists for #{repo_name}, updating")
        # Update the branch to point to the same commit as default_branch
        github_client.update_ref(
          repo_full_name,
          "heads/#{branch_name}",
          default_branch_sha,
          true # Force update
        )
      rescue Octokit::NotFound
        # Branch doesn't exist, create it
        logger.info("Creating branch #{branch_name} for #{repo_name}")
        github_client.create_ref(
          repo_full_name,
          "heads/#{branch_name}",
          default_branch_sha
        )
      end
      
      # Set up the local branch in the thread-specific directory
      # These commands need to be run in the repository directory, which is handled by the caller
      # Each thread has its own working directory, so these operations are thread-safe
      system('git fetch origin')
      system("git checkout -B #{branch_name} origin/#{branch_name} || git checkout -b #{branch_name} origin/#{default_branch}")
      
      # Configure git user
      system("git config user.name \"#{config[:git_name]}\"")
      system("git config user.email \"#{config[:git_email]}\"")
      
      true
    rescue => e
      logger.error("Error creating branch for #{repo_name}: #{e.message}")
      false
    end
  end

  # Check if a branch exists using GitHub API
  # @param repo_name [String] Repository name
  # @param branch_name [String] Branch name
  # @return [Boolean] True if branch exists
  def branch_exists?(repo_name, branch_name)
    begin
      github_client.ref("#{config[:owner]}/#{repo_name}", "heads/#{branch_name}")
      true
    rescue Octokit::NotFound
      false
    end
  end
  
  # Find an existing PR for the branch
  # @param repo_name [String] Repository name
  # @return [Sawyer::Resource, nil] Pull request object or nil if not found
  def find_existing_pr(repo_name)
    repo_full_name = "#{config[:owner]}/#{repo_name}"
    prs = github_client.pull_requests(repo_full_name, state: 'open')
    prs.find { |pr| pr.head.ref == config[:branch_name] }
  rescue StandardError => e
    logger.error("Error finding existing PR for #{repo_name}: #{e.message}")
    nil
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

    # Push to remote using token authentication
    # Use a thread-specific remote name to avoid conflicts between threads
    thread_id = Thread.current.object_id
    remote_name = "origin_#{thread_id}"
    repo_url = "https://#{@github_token}@github.com/#{config[:owner]}/#{repo_name}.git"
    
    # Remove the remote if it exists, then add it with the token
    system("git remote remove #{remote_name} 2>/dev/null || true")
    system("git remote add #{remote_name} #{repo_url}")
    system("git push -u #{remote_name} #{config[:branch_name]} -f")

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
    
    # Push to remote using token authentication
    # Use a thread-specific remote name to avoid conflicts between threads
    thread_id = Thread.current.object_id
    remote_name = "origin_#{thread_id}"
    repo_url = "https://#{@github_token}@github.com/#{config[:owner]}/#{repo_name}.git"
    
    # Remove the remote if it exists, then add it with the token
    system("git remote remove #{remote_name} 2>/dev/null || true")
    system("git remote add #{remote_name} #{repo_url}")
    system("git push -u #{remote_name} #{config[:branch_name]} -f")
    
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
    
    # Format PR body with cookstyle output
    pr_body = manual_fix ? format_manual_fix_pr_body(cookstyle_output) : format_pr_body(cookstyle_output)

    # Use provided title or default
    title = pr_title || config[:pr_title]
    
    # Check if PR already exists using our dedicated method
    existing_pr = find_existing_pr(repo_name)
    
    if existing_pr
      logger.info("Pull request already exists for #{repo_full_name}, updating PR ##{existing_pr.number}")
      
      # Update the existing PR with new content
      pr = github_client.update_pull_request(
        repo_full_name,
        existing_pr.number,
        title: title,
        body: pr_body
      )
      
      # Add labels if specified and not already present
      if config[:pr_labels]&.any?
        existing_labels = github_client.labels_for_issue(repo_full_name, existing_pr.number).map(&:name)
        missing_labels = config[:pr_labels] - existing_labels
        
        if missing_labels.any?
          github_client.add_labels_to_an_issue(
            repo_full_name,
            existing_pr.number,
            missing_labels
          )
          logger.info("Added labels #{missing_labels.join(', ')} to PR ##{existing_pr.number}")
        end
      end
      
      pr
    else
      logger.info("Creating new pull request for #{repo_full_name}")
      
      # Create a new pull request
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
    end
  rescue Octokit::UnprocessableEntity => e
    if e.message.include?('A pull request already exists')
      logger.info("Pull request creation failed but one might exist, trying to find it")
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
  # Accessor for the GitHub client
  # @return [Octokit::Client] GitHub client
  def github_client
    @github_client
  end
end
