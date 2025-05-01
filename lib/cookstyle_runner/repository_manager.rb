#!/usr/bin/env ruby
# frozen_string_literal: true

require 'logger'
require 'fileutils'
require 'open3'

# Module for repository management operations
module RepositoryManager
  # Extract repository name from URL
  # @param repo_url [String] Repository URL
  # @return [String] Repository name
  def self.extract_repo_name(repo_url)
    File.basename(repo_url, '.git')
  end

  # Clean up repository directory after processing
  # @param repo_dir [String] Repository directory
  # @return [Boolean] True if successful
  def self.cleanup_repo_dir(repo_dir)
    FileUtils.rm_rf(repo_dir)
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
      # Use exact match instead of include?
      filter_repos_lowercase.any? { |filter| repo_name == filter }
    end

    logger.info("Found #{filtered.length} repositories matching filter criteria")
    filtered
  end
end
