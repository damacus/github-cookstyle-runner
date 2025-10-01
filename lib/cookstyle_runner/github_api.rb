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

    # Find an existing PR for a branch
    sig { params(repo_full_name: String, branch_name: String, logger: Logger).returns(T.nilable(Sawyer::Resource)) }
    def self.find_existing_pr(repo_full_name, branch_name, logger)
      prs = Authentication.client.pull_requests(repo_full_name, state: 'open')
      prs.find { |pr| pr.head.ref == branch_name }
    rescue StandardError => e
      logger.error("Error finding existing PR for #{repo_full_name}: #{e.message}")
      nil
    end

    # Create or update a pull request
    # rubocop:disable Metrics/MethodLength
    sig do
      params(repo_full_name: String, branch_name: String, default_branch: String, title: String, body: String, labels: T::Array[String],
             logger: Logger).returns(T.nilable(Sawyer::Resource))
    end
    def self.create_or_update_pr(repo_full_name, branch_name, default_branch, title, body, labels, logger)
      existing_pr = find_existing_pr(repo_full_name, branch_name, logger)
      if existing_pr
        logger.info("Pull request already exists for #{repo_full_name}, updating PR ##{existing_pr.number}")
        pr = Authentication.client.update_pull_request(
          repo_full_name,
          existing_pr.number,
          title: title,
          body: body
        )
        if labels.any?
          existing_labels = Authentication.client.labels_for_issue(repo_full_name, existing_pr.number).map(&:name)
          new_labels = labels - existing_labels
          Authentication.client.add_labels_to_an_issue(repo_full_name, existing_pr.number, new_labels) if new_labels.any?
        end
      else
        logger.info("Creating new PR for #{repo_full_name}")
        pr = Authentication.client.create_pull_request(
          repo_full_name,
          default_branch,
          branch_name,
          title,
          body
        )

        # Add labels if specified
        Authentication.client.add_labels_to_an_issue(repo_full_name, pr.number, labels) if labels.any?
      end
      pr
    rescue StandardError => e
      logger.error("Error creating/updating PR for #{repo_full_name}: #{e.message}")
      logger.debug(T.must(e.backtrace).join("\n"))
      nil
    end
    # rubocop:enable Metrics/MethodLength
  end
end
