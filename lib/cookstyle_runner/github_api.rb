# frozen_string_literal: true
# typed: strict

require 'octokit'
require 'semantic_logger'
require_relative 'authentication'
require_relative 'github_label_helper'
require_relative 'github_pr_helper'
require_relative 'retry_with_backoff'
require_relative 'metrics'

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
    # rubocop:disable Metrics/MethodLength
    sig { params(owner: String, topics: T.nilable(T::Array[String])).returns(T::Array[String]) }
    def self.fetch_repositories(owner, topics = nil)
      max_retries = T.let(Settings.retry_count || 3, Integer)

      RetryWithBackoff.with_exponential_backoff(
        max_retries: max_retries,
        operation_name: 'search_repositories',
        context: { owner: owner, topics: topics }
      ) do
        query = "org:#{owner}"
        topics.each { |topic| query += " topic:#{topic}" } if topics && !topics.empty?
        log.debug('Searching repositories', payload: { owner: owner, topics: topics, query: query })

        results = Authentication.client.search_repositories(query)
        log.info('Found repositories', payload: { count: results.total_count, owner: owner })

        # Record successful API request metrics
        Metrics.increment_api_requests(endpoint: 'search_repositories', status: '200')

        results.items.map(&:clone_url)
      end
    rescue Octokit::TooManyRequests => e
      log.error('Rate limit exceeded after retries', payload: { operation: 'search_repositories', error: e.message, owner: owner })
      Metrics.increment_api_requests(endpoint: 'search_repositories', status: '429')
      Metrics.increment_errors(error_type: 'RateLimit', component: 'GitHubAPI')
      []
    rescue Octokit::ServerError => e
      log.error('GitHub API server error after retries', payload: { operation: 'search_repositories', error: e.message, owner: owner })
      Metrics.increment_api_requests(endpoint: 'search_repositories', status: '500')
      Metrics.increment_errors(error_type: 'ServerError', component: 'GitHubAPI')
      []
    rescue Octokit::Error => e
      log.error('GitHub API error', payload: { operation: 'search_repositories', error: e.message, owner: owner })
      log.debug(T.must(e.backtrace).join("\n"))
      Metrics.increment_api_requests(endpoint: 'search_repositories', status: 'error')
      Metrics.increment_errors(error_type: 'OctokitError', component: 'GitHubAPI')
      []
    rescue StandardError => e
      log.error('Error fetching repositories', payload: { operation: 'search_repositories', error: e.message, owner: owner })
      log.debug(T.must(e.backtrace).join("\n"))
      Metrics.increment_api_requests(endpoint: 'search_repositories', status: 'error')
      Metrics.increment_errors(error_type: e.class.name, component: 'GitHubAPI')
      []
    end
    # rubocop:enable Metrics/MethodLength

    # Find an existing PR for a branch
    sig { params(repo_full_name: String, branch_name: String).returns(T.nilable(Sawyer::Resource)) }
    def self.find_existing_pr(repo_full_name, branch_name)
      GitHubPRHelper.find_existing_pr(Authentication.client, repo_full_name, branch_name, log)
    end

    # Create or update a pull request
    # rubocop:disable Metrics/MethodLength
    sig do
      params(repo_full_name: String, branch_name: String, default_branch: String, title: String, body: String,
             labels: T::Array[String]).returns(T.nilable(Sawyer::Resource))
    end
    def self.create_or_update_pr(repo_full_name, branch_name, default_branch, title, body, labels)
      max_retries = T.let(Settings.retry_count || 3, Integer)

      RetryWithBackoff.with_exponential_backoff(
        max_retries: max_retries,
        operation_name: 'create_or_update_pr',
        context: { repo: repo_full_name, branch: branch_name }
      ) do
        existing_pr = find_existing_pr(repo_full_name, branch_name)
        if existing_pr
          log.info('Pull request already exists, updating', payload: { repo: repo_full_name, pr_number: existing_pr.number, operation: 'update_pr' })
          pr = Authentication.client.update_pull_request(
            repo_full_name,
            existing_pr.number,
            title: title,
            body: body
          )
          GitHubLabelHelper.update_pr_labels(Authentication.client, repo_full_name, existing_pr.number, labels, log)
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
          GitHubLabelHelper.add_labels_safely(Authentication.client, repo_full_name, pr.number, labels, log)
        end
        pr
      end
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
