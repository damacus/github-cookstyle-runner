# frozen_string_literal: true
# typed: strict

require 'octokit'
require 'sorbet-runtime'

module CookstyleRunner
  # =============================================================================
  # GitHub Cookstyle Runner - GitHub Label Helper
  # =============================================================================
  #
  # This module provides shared functionality for managing GitHub labels on
  # issues and pull requests, reducing code duplication across GitHubAPI and
  # GitHubPRManager.
  #
  module GitHubLabelHelper
    extend T::Sig

    # Add labels to an issue or pull request, avoiding duplicates
    #
    # @param client [Octokit::Client] GitHub API client
    # @param repo_name [String] Repository name in owner/repo format
    # @param issue_or_pr_number [Integer] Issue or PR number
    # @param labels [Array<String>] Labels to add
    # @param logger [SemanticLogger::Logger, nil] Optional logger for reporting
    # @return [Boolean] true if labels were added successfully, false otherwise
    sig do
      params(
        client: T.any(Octokit::Client, Object),
        repo_name: String,
        issue_or_pr_number: Integer,
        labels: T::Array[String],
        logger: T.nilable(T.any(SemanticLogger::Logger, Object))
      ).returns(T::Boolean)
    end
    def self.add_labels_safely(client, repo_name, issue_or_pr_number, labels, logger = nil)
      return true if labels.empty?

      add_new_labels(client, repo_name, issue_or_pr_number, labels, logger)
    rescue StandardError => e
      log_label_error(logger, repo_name, issue_or_pr_number, labels, e)
      false
    end

    # Add only new labels that don't already exist
    #
    # @param client GitHub API client
    # @param repo_name [String] Repository name in owner/repo format
    # @param issue_or_pr_number [Integer] Issue or PR number
    # @param labels [Array<String>] Labels to add
    # @param logger [SemanticLogger::Logger, Object, nil] Optional logger for reporting
    # @return [Boolean] true if labels were added successfully
    # rubocop:disable Naming/PredicateMethod
    private_class_method def self.add_new_labels(client, repo_name, issue_or_pr_number, labels, logger)
      existing_labels = client.labels_for_issue(repo_name, issue_or_pr_number).map(&:name)
      new_labels = labels - existing_labels

      if new_labels.any?
        client.add_labels_to_an_issue(repo_name, issue_or_pr_number, new_labels)
        log_labels_added(logger, repo_name, issue_or_pr_number, new_labels)
      else
        log_no_new_labels(logger, repo_name, issue_or_pr_number)
      end
      true
    end
    # rubocop:enable Naming/PredicateMethod

    # Log successful label addition
    private_class_method def self.log_labels_added(logger, repo_name, issue_or_pr_number, new_labels)
      logger&.info('Added labels', payload: {
                     repo: repo_name,
                     number: issue_or_pr_number,
                     labels: new_labels
                   })
    end

    # Log when no new labels need to be added
    private_class_method def self.log_no_new_labels(logger, repo_name, issue_or_pr_number)
      logger&.debug('No new labels to add', payload: {
                      repo: repo_name,
                      number: issue_or_pr_number
                    })
    end

    # Log label addition error
    private_class_method def self.log_label_error(logger, repo_name, issue_or_pr_number, labels, error)
      logger&.error('Failed to add labels', payload: {
                      repo: repo_name,
                      number: issue_or_pr_number,
                      labels: labels,
                      error: error.message
                    })
    end

    # Update labels for an existing pull request
    #
    # @param client [Octokit::Client] GitHub API client
    # @param repo_name [String] Repository name in owner/repo format
    # @param pr_number [Integer] Pull request number
    # @param labels [Array<String>] Labels to add
    # @param logger [SemanticLogger::Logger, nil] Optional logger for reporting
    # @return [Boolean] true if labels were updated successfully, false otherwise
    sig do
      params(
        client: T.any(Octokit::Client, Object),
        repo_name: String,
        pr_number: Integer,
        labels: T::Array[String],
        logger: T.nilable(T.any(SemanticLogger::Logger, Object))
      ).returns(T::Boolean)
    end
    def self.update_pr_labels(client, repo_name, pr_number, labels, logger = nil)
      add_labels_safely(client, repo_name, pr_number, labels, logger)
    end
  end
end
