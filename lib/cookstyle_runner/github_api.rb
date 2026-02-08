# frozen_string_literal: true
# typed: strict

require 'octokit'
require 'semantic_logger'
require_relative 'authentication'
require_relative 'github_label_helper'
require_relative 'github_pr_helper'

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
      retries = T.let(0, Integer)
      max_retries = T.let(3, Integer)

      begin
        query = "org:#{owner}"
        topics.each { |topic| query += " topic:#{topic}" } if topics && !topics.empty?
        log.debug('Searching repositories', payload: { owner: owner, topics: topics, query: query })
        results = Authentication.client.search_repositories(query)
        log.info('Found repositories', payload: { count: results.total_count, owner: owner })
        results.items.map(&:clone_url)
      rescue Octokit::TooManyRequests => e
        retries += 1
        if retries <= max_retries
          retry_after = T.let(e.response_headers&.dig('retry-after')&.to_i || (2**retries), Integer)
          log.warn('Rate limited, retrying', payload: { attempt: retries, retry_after: retry_after, owner: owner })
          sleep(retry_after)
          retry
        end
        log.error('Rate limit exceeded after retries', payload: { operation: 'search_repositories', error: e.message, owner: owner })
        []
      rescue Octokit::ServerError => e
        retries += 1
        if retries <= max_retries
          delay = T.let(2**retries, Integer)
          log.warn('Server error, retrying', payload: { attempt: retries, delay: delay, owner: owner })
          sleep(delay)
          retry
        end
        log.error('GitHub API server error after retries', payload: { operation: 'search_repositories', error: e.message, owner: owner })
        []
      rescue Octokit::Error => e
        log.error('GitHub API error', payload: { operation: 'search_repositories', error: e.message, owner: owner })
        log.debug(T.must(e.backtrace).join("\n"))
        []
      rescue StandardError => e
        log.error('Error fetching repositories', payload: { operation: 'search_repositories', error: e.message, owner: owner })
        log.debug(T.must(e.backtrace).join("\n"))
        []
      end
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
