# frozen_string_literal: true
# typed: strict

require 'octokit'
require 'sorbet-runtime'

module CookstyleRunner
  # =============================================================================
  # GitHub Cookstyle Runner - GitHub PR Helper
  # =============================================================================
  #
  # This module provides shared functionality for managing GitHub pull requests,
  # reducing code duplication across GitHubAPI and GitHubPRManager.
  #
  module GitHubPRHelper
    extend T::Sig

    # Find an existing pull request for a specific branch
    #
    # @param client [Octokit::Client] GitHub API client
    # @param repo_name [String] Repository name in owner/repo format
    # @param branch_name [String] Branch name to search for
    # @param logger [SemanticLogger::Logger, nil] Optional logger for error reporting
    # @return [Sawyer::Resource, nil] The pull request resource or nil if not found/error
    sig do
      params(
        client: T.any(Octokit::Client, Object),
        repo_name: String,
        branch_name: String,
        logger: T.nilable(T.any(SemanticLogger::Logger, Object))
      ).returns(T.nilable(T.any(Sawyer::Resource, Object)))
    end
    def self.find_existing_pr(client, repo_name, branch_name, logger = nil)
      prs = client.pull_requests(repo_name, state: 'open')
      prs.find { |pr| pr.head.ref == branch_name }
    rescue StandardError => e
      logger&.error('Error finding existing pull request', payload: {
                      repo: repo_name,
                      branch: branch_name,
                      error: e.message
                    })
      nil
    end
  end
end
