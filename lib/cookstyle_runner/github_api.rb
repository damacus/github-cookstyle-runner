#!/usr/bin/env ruby
# frozen_string_literal: true

require 'octokit'
require 'logger'
require_relative 'authentication'

module CookstyleRunner
  # Module for GitHub API operations
  module GitHubAPI
    # Fetch repositories from GitHub
    # @param client [Octokit::Client] GitHub API client
    # @param owner [String] Repository owner
    # @param topics [Array<String>] Topics to filter by
    # @param logger [Logger] Logger instance
    # @return [Array<String>] List of repository clone URLs
    def self.fetch_repositories(client, owner, topics = nil, logger)
      # Build the search query
      query = "org:#{owner}"

      # Add topic filters if specified
      if topics && !topics.empty?
        topics.each do |topic|
          query += " topic:#{topic}"
        end
      end

      logger.debug("Search query: #{query}")

      # Execute the search
      results = client.search_repositories(query)

      logger.info("Found #{results.total_count} repositories")

      # Extract clone URLs
      results.items.map(&:clone_url)
    rescue Octokit::Error => e
      logger.error("GitHub API error: #{e.message}")
      logger.debug(e.backtrace.join("\n"))
      []
    rescue StandardError => e
      logger.error("Error fetching repositories: #{e.message}")
      logger.debug(e.backtrace.join("\n"))
      []
    end

    # Check if a branch exists using GitHub API
    # @param client [Octokit::Client] GitHub API client
    # @param repo_full_name [String] Full repository name (owner/repo)
    # @param branch_name [String] Branch name
    # @param logger [Logger] Logger instance
    # @return [Boolean] True if branch exists
    def self.branch_exists?(client, repo_full_name, branch_name, logger)
      client.ref(repo_full_name, "heads/#{branch_name}")
      true
    rescue Octokit::NotFound
      false
    rescue StandardError => e
      logger.error("Error checking if branch exists: #{e.message}")
      false
    end

    # Create or update a branch using GitHub API
    # @param client [Octokit::Client] GitHub API client
    # @param repo_full_name [String] Full repository name (owner/repo)
    # @param branch_name [String] Branch name to create or update
    # @param default_branch [String] Default branch name
    # @param logger [Logger] Logger instance
    # @return [Boolean] True if successful
    def self.create_or_update_branch(client, repo_full_name, branch_name, default_branch, logger)
      # Get the SHA of the default branch
      default_branch_ref = client.ref(repo_full_name, "heads/#{default_branch}")
      default_branch_sha = default_branch_ref.object.sha

      # Check if branch exists
      begin
        client.ref(repo_full_name, "heads/#{branch_name}")
        logger.info("Branch #{branch_name} already exists for #{repo_full_name}, updating")
        # Update the branch to point to the same commit as default_branch
        client.update_ref(
          repo_full_name,
          "heads/#{branch_name}",
          default_branch_sha,
          true # Force update
        )
      rescue Octokit::NotFound
        # Branch doesn't exist, create it
        logger.info("Creating branch #{branch_name} for #{repo_full_name}")
        client.create_ref(
          repo_full_name,
          "heads/#{branch_name}",
          default_branch_sha
        )
      end

      true
    rescue StandardError => e
      logger.error("Error creating/updating branch for #{repo_full_name}: #{e.message}")
      false
    end

    # Find an existing PR for a branch
    # @param client [Octokit::Client] GitHub API client
    # @param repo_full_name [String] Full repository name (owner/repo)
    # @param branch_name [String] Branch name
    # @param logger [Logger] Logger instance
    # @return [Sawyer::Resource, nil] Pull request object or nil if not found
    def self.find_existing_pr(client, repo_full_name, branch_name, logger)
      prs = client.pull_requests(repo_full_name, state: 'open')
      prs.find { |pr| pr.head.ref == branch_name }
    rescue StandardError => e
      logger.error("Error finding existing PR for #{repo_full_name}: #{e.message}")
      nil
    end

    # Create or update a pull request
    # @param client [Octokit::Client] GitHub API client
    # @param repo_full_name [String] Full repository name (owner/repo)
    # @param branch_name [String] Branch name
    # @param default_branch [String] Default branch name
    # @param title [String] PR title
    # @param body [String] PR body
    # @param labels [Array<String>] PR labels
    # @param logger [Logger] Logger instance
    # @return [Sawyer::Resource, nil] Pull request object or nil if failed
    def self.create_or_update_pr(client, repo_full_name, branch_name, default_branch, title, body, labels, logger)
      # Check if PR already exists
      existing_pr = find_existing_pr(client, repo_full_name, branch_name, logger)

      if existing_pr
        logger.info("Pull request already exists for #{repo_full_name}, updating PR ##{existing_pr.number}")

        # Update the existing PR with new content
        pr = client.update_pull_request(
          repo_full_name,
          existing_pr.number,
          title: title,
          body: body
        )

        # Add labels if specified and not already present
        if labels && !labels.empty?
          existing_labels = client.labels_for_issue(repo_full_name, existing_pr.number).map(&:name)
          new_labels = labels - existing_labels

          client.add_labels_to_an_issue(repo_full_name, existing_pr.number, new_labels) if new_labels.any?
        end

      else
        # Create a new PR
        logger.info("Creating new PR for #{repo_full_name}")
        pr = client.create_pull_request(
          repo_full_name,
          default_branch,
          branch_name,
          title,
          body
        )

        # Add labels if specified
        client.add_labels_to_an_issue(repo_full_name, pr.number, labels) if labels && !labels.empty?

      end
      pr
    rescue StandardError => e
      logger.error("Error creating/updating PR for #{repo_full_name}: #{e.message}")
      logger.debug(e.backtrace.join("\n"))
      nil
    end

    # Format PR body for auto-fix PRs
    # @param cookstyle_output [String] Output from cookstyle run
    # @return [String] Formatted PR body
    def self.format_pr_body(cookstyle_output)
      <<~BODY
        ## Cookstyle Automated Changes

        This PR applies automatic Cookstyle fixes using the latest version.

        ### Changes Made

        ```
        #{cookstyle_output}
        ```

        Signed-off-by: GitHub Cookstyle Runner <cookstyle-runner@example.com>
      BODY
    end

    # Format PR body for manual fix PRs
    # @param cookstyle_output [String] Output from cookstyle run
    # @return [String] Formatted PR body
    def self.format_manual_fix_pr_body(cookstyle_output)
      <<~BODY
        ## Manual Cookstyle Fixes Required

        Cookstyle identified issues that require manual intervention. Please review the output below and apply the necessary fixes.

        ### Cookstyle Output

        ```
        #{cookstyle_output}
        ```
      BODY
    end

    # Create a GitHub Issue
    # @param client [Octokit::Client] GitHub API client
    # @param repo_full_name [String] Full repository name (owner/repo)
    # @param title [String] Issue title
    # @param body [String] Issue body
    # @param labels [Array<String>] Issue labels
    # @param logger [Logger] Logger instance
    # @return [Sawyer::Resource, nil] Issue object or nil if failed
    def self.create_issue(client, repo_full_name, title, body, labels, logger)
      logger.info("Creating issue '#{title}' for #{repo_full_name}")
      issue = client.create_issue(
        repo_full_name,
        title,
        body,
        labels: labels
      )
      logger.info("Successfully created issue ##{issue.number} for #{repo_full_name}: #{issue.html_url}")
      issue
    rescue StandardError => e
      logger.error("Error creating issue for #{repo_full_name}: #{e.message}")
      logger.debug(e.backtrace.join("\n"))
      nil
    end
  end
end
