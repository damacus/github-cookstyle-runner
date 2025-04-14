#!/usr/bin/env ruby
# frozen_string_literal: true

require 'logger'
require 'open3'
require 'fileutils'

# Module for handling Git operations
module GitOperations
  # Check if there are changes to commit in the current directory
  # @param logger [Logger] Logger instance
  # @return [Boolean] True if there are changes
  def self.changes_to_commit?(logger)
    stdout, _stderr, status = Open3.capture3('git status --porcelain')
    status.success? && !stdout.strip.empty?
  rescue StandardError => e
    logger.error("Error checking for changes: #{e.message}")
    false
  end

  # Create a new branch for cookstyle fixes
  # @param repo_name [String] Repository name
  # @param branch_name [String] Branch name to create
  # @param default_branch [String] Default branch to base off of
  # @param git_name [String] Git user name
  # @param git_email [String] Git user email
  # @param logger [Logger] Logger instance
  # @return [Boolean] True if branch was created successfully
  def self.create_local_branch(repo_name, branch_name, default_branch, git_name, git_email, logger)
    # Set up the local branch in the thread-specific directory
    # These commands need to be run in the repository directory, which is handled by the caller
    # Each thread has its own working directory, so these operations are thread-safe
    system('git fetch origin')
    system("git checkout -B #{branch_name} origin/#{branch_name} || git checkout -b #{branch_name} origin/#{default_branch}")

    # Configure git user
    system("git config user.name \"#{git_name}\"")
    system("git config user.email \"#{git_email}\"")

    true
  rescue StandardError => e
    logger.error("Error creating local branch for #{repo_name}: #{e.message}")
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
  def self.commit_and_push_changes(repo_name, branch_name, commit_message, github_token, owner, logger)
    # Add all changes
    system('git add .')

    # Commit changes
    system("git commit -m \"#{commit_message}\"")

    # Set up remote with token for authentication
    # Use thread-safe remote name to avoid conflicts
    thread_id = Thread.current.object_id
    remote_name = "origin_#{thread_id}"
    repo_url = "https://#{github_token}@github.com/#{owner}/#{repo_name}.git"

    # Add a new remote with the token for authentication
    system("git remote remove #{remote_name} 2>/dev/null || true")
    system("git remote add #{remote_name} #{repo_url}")
    system("git push -u #{remote_name} #{branch_name} -f")

    $?.success?
  rescue StandardError => e
    logger.error("Error committing and pushing changes for #{repo_name}: #{e.message}")
    false
  end

  # Create an empty commit for manual fix PRs
  # @param repo_name [String] Repository name
  # @param branch_name [String] Branch name
  # @param commit_message [String] Commit message
  # @param github_token [String] GitHub token
  # @param owner [String] Repository owner
  # @param logger [Logger] Logger instance
  # @return [Boolean] True if successful
  def self.create_empty_commit(repo_name, branch_name, commit_message, github_token, owner, logger)
    # Create an empty commit
    system("git commit --allow-empty -m \"#{commit_message}\"")

    # Set up remote with token for authentication
    # Use thread-safe remote name to avoid conflicts
    thread_id = Thread.current.object_id
    remote_name = "origin_#{thread_id}"
    repo_url = "https://#{github_token}@github.com/#{owner}/#{repo_name}.git"

    # Add a new remote with the token for authentication
    system("git remote remove #{remote_name} 2>/dev/null || true")
    system("git remote add #{remote_name} #{repo_url}")
    system("git push -u #{remote_name} #{branch_name} -f")

    $?.success?
  rescue StandardError => e
    logger.error("Error creating empty commit for #{repo_name}: #{e.message}")
    false
  end

  # Update changelog with cookstyle fixes
  # @param repo_name [String] Repository name
  # @param changelog_file [String] Path to changelog file
  # @param marker [String] Marker in changelog for adding entries
  # @param logger [Logger] Logger instance
  # @return [Boolean] True if successful
  def self.update_changelog(repo_name, changelog_file, marker, logger)
    return false unless File.exist?(changelog_file)

    content = File.read(changelog_file)
    today = Time.now.utc.strftime('%Y-%m-%d')

    if content.include?(marker)
      new_content = content.gsub(marker, "#{marker}\n- Cookstyle auto-corrections applied on #{today}")
      File.write(changelog_file, new_content)
      logger.info("Changelog updated successfully for #{repo_name}")
      true
    else
      logger.warn("Changelog marker '#{marker}' not found in #{changelog_file} for #{repo_name}")
      false
    end
  rescue StandardError => e
    logger.error("Error updating changelog for #{repo_name}: #{e.message}")
    false
  end
end
