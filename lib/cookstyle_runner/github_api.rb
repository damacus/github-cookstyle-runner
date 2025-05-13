# frozen_string_literal: true
# typed: strict

require 'octokit'
require 'logger'
require_relative 'authentication'

module CookstyleRunner
  # Module for GitHub API operations
  module GitHubAPI
    extend T::Sig

    # Fetch repositories from GitHub
    # rubocop:disable Metrics/AbcSize
    sig { params(owner: String, logger: Logger, topics: T.nilable(T::Array[String])).returns(T::Array[String]) }
    def self.fetch_repositories(owner, logger, topics = nil)
      query = "org:#{owner}"
      topics.each { |topic| query += " topic:#{topic}" } if topics && !topics.empty?
      logger.debug("Search query: #{query}")
      results = Authentication.client.search_repositories(query)
      logger.info("Found #{results.total_count} repositories")
      results.items.map(&:clone_url)
    rescue Octokit::Error => e
      logger.error("GitHub API error: #{e.message}")
      logger.debug(T.must(e.backtrace).join("\n"))
      []
    rescue StandardError => e
      logger.error("Error fetching repositories: #{e.message}")
      logger.debug(T.must(e.backtrace).join("\n"))
      []
    end
    # rubocop:enable Metrics/AbcSize

    # Check if a branch exists using GitHub API
    sig { params(repo_full_name: String, branch_name: String, logger: Logger).returns(T::Boolean) }
    def self.branch_exists?(repo_full_name, branch_name, logger)
      clone.ref(repo_full_name, "heads/#{branch_name}")
      true
    rescue Octokit::NotFound
      false
    rescue StandardError => e
      logger.error("Error checking if branch exists: #{e.message}")
      false
    end

    # Create or update a branch using GitHub API
    sig { params(repo_full_name: String, branch_name: String, default_branch: String, logger: Logger).returns(T::Boolean) }
    def self.create_or_update_branch(repo_full_name, branch_name, default_branch, logger)
      default_branch_ref = ::Git.clone.ref(repo_full_name, "heads/#{default_branch}")

      begin
        ::Git.clone.ref(repo_full_name, "heads/#{branch_name}")
        logger.info("Branch #{branch_name} already exists for #{repo_full_name}, updating")
        ::Git.clone.update_ref(
          repo_full_name,
          "heads/#{branch_name}",
          default_branch_ref.object.sha,
          true
        )
      rescue Octokit::NotFound
        logger.info("Creating branch #{branch_name} for #{repo_full_name}")
        ::Git.clone.create_ref(
          repo_full_name,
          "heads/#{branch_name}",
          default_branch_ref.object.sha
        )
      end
      true
    rescue StandardError => e
      logger.error("Error creating/updating branch for #{repo_full_name}: #{e.message}")
      false
    end

    # Find an existing PR for a branch
    sig { params(repo_full_name: String, branch_name: String, logger: Logger).returns(T.nilable(Sawyer::Resource)) }
    def self.find_existing_pr(repo_full_name, branch_name, logger)
      prs = clone.pull_requests(repo_full_name, state: 'open')
      prs.find { |pr| pr.head.ref == branch_name }
    rescue StandardError => e
      logger.error("Error finding existing PR for #{repo_full_name}: #{e.message}")
      nil
    end

    # Create or update a pull request
    # rubocop:disable Metrics/ParameterLists, Metrics/AbcSize, Metrics/MethodLength
    sig do
      params(repo_full_name: String, branch_name: String, default_branch: String, title: String, body: String, labels: T::Array[String],
             logger: Logger).returns(T.nilable(Sawyer::Resource))
    end
    def self.create_or_update_pr(repo_full_name, branch_name, default_branch, title, body, labels, logger)
      existing_pr = find_existing_pr(repo_full_name, branch_name, logger)
      if existing_pr
        logger.info("Pull request already exists for #{repo_full_name}, updating PR ##{existing_pr.number}")
        pr = clone.update_pull_request(
          repo_full_name,
          existing_pr.number,
          title: title,
          body: body
        )
        if labels.any?
          existing_labels = clone.labels_for_issue(repo_full_name, existing_pr.number).map(&:name)
          new_labels = labels - existing_labels
          clone.add_labels_to_an_issue(repo_full_name, existing_pr.number, new_labels) if new_labels.any?
        end
      else
        logger.info("Creating new PR for #{repo_full_name}")
        pr = clone.create_pull_request(
          repo_full_name,
          default_branch,
          branch_name,
          title,
          body
        )

        # Add labels if specified
        clone.add_labels_to_an_issue(repo_full_name, pr.number, labels) if labels.any?
      end
      pr
    rescue StandardError => e
      logger.error("Error creating/updating PR for #{repo_full_name}: #{e.message}")
      logger.debug(T.must(e.backtrace).join("\n"))
      nil
    end
    # rubocop:enable Metrics/ParameterLists, Metrics/AbcSize, Metrics/MethodLength

    # Format PR body for auto-fix PRs
    sig { params(cookstyle_output: String).returns(String) }
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

    # Format issue body for manual fix issues
    sig { params(cookstyle_output: String).returns(String) }
    def self.format_issue_body(cookstyle_output)
      <<~BODY
        ## Manual Cookstyle Fixes Required

        Cookstyle identified issues that require manual intervention. Please review the output below and apply the necessary fixes.

        ### Cookstyle Output

        ```
        #{cookstyle_output}
        ```
      BODY
    end
  end
end
