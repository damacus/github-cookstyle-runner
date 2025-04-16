#!/usr/bin/env ruby
# frozen_string_literal: true

require 'logger'
require 'fileutils'
require 'open3'

# Module for repository management operations
module RepositoryManager
  # Clone a repository if it doesn't exist or update it if it does
  # @param repo_url [String] Repository URL
  # @param repo_dir [String] Repository directory
  # @param default_branch [String] Default branch name
  # @param logger [Logger] Logger instance
  # @param owner [String] Repository owner
  # @param app_id [String] GitHub App ID
  # @param installation_id [String] GitHub App installation ID
  # @param private_key [String] PEM-encoded private key
  # @return [Boolean] True if successful
  def self.clone_or_update_repo(repo_url, repo_dir, default_branch, logger, owner:, app_id:, installation_id:, private_key:)
    context = GitOperations::RepoContext.new(repo_name: File.basename(repo_url, '.git'), owner: owner, logger: logger)
    GitOperations.clone_or_update_repo(context, default_branch, app_id: app_id, installation_id: installation_id, private_key: private_key)
  end

  # Extract repository name from URL
  # @param repo_url [String] Repository URL
  # @return [String] Repository name
  def self.extract_repo_name(repo_url)
    File.basename(repo_url, '.git')
  end

  # Create a thread-safe working directory for a repository
  # @param cache_dir [String] Base cache directory
  # @param repo_name [String] Repository name
  # @return [String] Thread-safe repository directory path
  def self.thread_safe_repo_dir(cache_dir, repo_name)
    thread_id = Thread.current.object_id
    thread_dir = File.join(cache_dir, "thread_#{thread_id}")
    repo_dir = File.join(thread_dir, repo_name)

    # Ensure thread directory exists
    FileUtils.mkdir_p(thread_dir) unless Dir.exist?(thread_dir)

    repo_dir
  end

  # Clean up repository directory after processing
  # @param repo_dir [String] Repository directory
  # @return [Boolean] True if successful
  def self.cleanup_repo_dir(repo_dir)
    FileUtils.rm_rf(repo_dir) if Dir.exist?(repo_dir)
    true
  rescue StandardError => e
    # Just log the error but don't fail the operation
    puts "Warning: Failed to clean up repository directory: #{e.message}"
    false
  end

  # Filter repositories based on specified criteria
  # @param repositories [Array<String>] List of repository URLs
  # @param filter_repos [Array<String>] List of repository names to filter by
  # @param logger [Logger] Logger instance
  # @return [Array<String>] Filtered list of repository URLs
  def self.filter_repositories(repositories, filter_repos, logger)
    return repositories if filter_repos.nil? || filter_repos.empty?

    logger.info("Filtering repositories to include only: #{filter_repos.join(', ')}")

    # Convert filter_repos to lowercase for case-insensitive matching
    filter_repos_lowercase = filter_repos.map(&:downcase)

    # Filter repositories by name
    filtered = repositories.select do |repo_url|
      repo_name = extract_repo_name(repo_url).downcase
      filter_repos_lowercase.any? { |filter| repo_name.include?(filter) }
    end

    logger.info("Found #{filtered.length} repositories matching filter criteria")
    filtered
  end

  # Check if a repository should be skipped based on inclusion/exclusion lists
  # @param repo_name [String] Repository name
  # @param include_repos [Array<String>] List of repositories to include
  # @param exclude_repos [Array<String>] List of repositories to exclude
  # @return [Boolean] True if the repository should be skipped
  def self.should_skip_repository?(repo_name, include_repos, exclude_repos)
    # If include list is specified, only process repositories in that list
    return !include_repos.include?(repo_name) if include_repos && !include_repos.empty?

    # If exclude list is specified, skip repositories in that list
    return exclude_repos.include?(repo_name) if exclude_repos && !exclude_repos.empty?

    false
  end
end
