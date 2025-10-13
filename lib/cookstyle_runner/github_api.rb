# frozen_string_literal: true
# typed: strict

require 'octokit'
require 'semantic_logger'
require_relative 'authentication'

module CookstyleRunner
  # Module for GitHub API operations
  module GitHubAPI
    extend T::Sig

    # Module-level logger
    @log = T.let(SemanticLogger[self], SemanticLogger::Logger)

    sig { returns(SemanticLogger::Logger) }
    def self.log
      @log
    end

    # Fetch repositories from GitHub
    sig { params(owner: String, topics: T.nilable(T::Array[String])).returns(T::Array[String]) }
    def self.fetch_repositories(owner, topics = nil)
      query = "org:#{owner}"
      topics.each { |topic| query += " topic:#{topic}" } if topics && !topics.empty?
      log.debug('Searching repositories', payload: { owner: owner, topics: topics, query: query })
      results = Authentication.client.search_repositories(query)
      log.info('Found repositories', payload: { count: results.total_count, owner: owner })
      results.items.map(&:clone_url)
    rescue Octokit::Error => e
      log.error('GitHub API error', payload: { operation: 'search_repositories', error: e.message, owner: owner })
      log.debug(T.must(e.backtrace).join("\n"))
      []
    rescue StandardError => e
      log.error('Error fetching repositories', payload: { operation: 'search_repositories', error: e.message, owner: owner })
      log.debug(T.must(e.backtrace).join("\n"))
      []
    end

    # Find an existing PR for a branch
    sig { params(repo_full_name: String, branch_name: String).returns(T.nilable(Sawyer::Resource)) }
    def self.find_existing_pr(repo_full_name, branch_name)
      prs = Authentication.client.pull_requests(repo_full_name, state: 'open')
      prs.find { |pr| pr.head.ref == branch_name }
    rescue StandardError => e
      log.error('Error finding existing PR', payload: { repo: repo_full_name, branch: branch_name, error: e.message, operation: 'find_pr' })
      nil
    end

    # Create or update a pull request
    # rubocop:disable Metrics/MethodLength
    sig do
      params(repo_full_name: String, branch_name: String, default_branch: String, title: String, body: String,
             labels: T::Array[String]).returns(T.nilable(Sawyer::Resource))
    end
    def self.create_or_update_pr(repo_full_name, branch_name, default_branch, title, body, labels)
      existing_pr = find_existing_pr(repo_full_name, branch_name)
      if existing_pr
        log.info('Pull request already exists, updating', payload: { repo: repo_full_name, pr_number: existing_pr.number, operation: 'update_pr' })
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
        log.info('Creating new PR', payload: { repo: repo_full_name, branch: branch_name, operation: 'create_pr' })
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
      log.error('Error creating/updating PR', payload: {
                  repo: repo_full_name,
                  branch: branch_name,
                  error: e.message,
                  operation: 'create_or_update_pr'
                })
      log.debug(T.must(e.backtrace).join("\n"))
      nil
    end
    # rubocop:enable Metrics/MethodLength
  end
end
