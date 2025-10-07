# frozen_string_literal: true
# typed: false

# This file is an RBI (Ruby Interface) file for Sorbet static type checking.
# It provides type signatures for the CookstyleRunner::RepositoryProcessor class.
# DO NOT put implementation code here. For more information, see:
# https://sorbet.org/docs/rbi

module CookstyleRunner
  # Repository Processor class that orchestrates the processing of repositories
  # - Cloning/updating the repository
  # - Running Cookstyle checks
  # - Processing the results
  # - Creating pull requests or issues as needed
  class RepositoryProcessor
    extend T::Sig

    # Configuration hash
    sig { returns(T::Hash[String, T.untyped]) }
    def config; end

    # Logger instance
    sig { returns(T.untyped) }
    def logger; end

    # Cache manager instance
    sig { returns(T.nilable(Cache)) }
    def cache_manager; end

    # GitHub API client
    sig { returns(T.untyped) }
    def github_client; end

    # Pull request manager
    sig { returns(T.untyped) }
    def pr_manager; end

    # Initialize a new repository processor
    # @param config [Hash] Configuration hash
    # @param logger [Logger] Logger instance
    # @param cache_manager [Cache, nil] Cache manager instance (optional)
    # @param github_client [Object, nil] GitHub API client (optional)
    # @param pr_manager [Object, nil] Pull request manager (optional)
    sig do
      params(
        config: T::Hash[String, T.untyped],
        logger: T.untyped,
        cache_manager: T.nilable(Cache),
        github_client: T.untyped,
        pr_manager: T.untyped
      ).void
    end
    def initialize(config:, logger:, cache_manager: nil, github_client: nil, pr_manager: nil); end

    # Process a single repository
    # @param repo_name [String] Repository name
    # @param repo_url [String] Repository URL
    # @return [Hash] Processing result hash
    sig do
      params(
        repo_name: String,
        repo_url: String
      ).returns(T::Hash[String, T.untyped])
    end
    def process_repository(repo_name, repo_url); end

    # Prepare the repository directory
    # @param repo_name [String] Repository name
    # @return [String] Repository directory path
    sig { params(repo_name: String).returns(String) }
    def prepare_repo_directory(repo_name); end

    # Clone or update the repository
    # @param repo_url [String] Repository URL
    # @param repo_dir [String] Repository directory path
    # @return [String, nil] The current commit SHA or nil if failed
    sig { params(repo_url: String, repo_dir: String).returns(T.nilable(String)) }
    def clone_or_update_repository(repo_url, repo_dir); end

    # Check if the repository is up to date in the cache
    # @param repo_name [String] Repository name
    # @param commit_sha [String] Current commit SHA
    # @return [Boolean] True if up to date in cache
    sig { params(repo_name: String, commit_sha: String).returns(T::Boolean) }
    def cache_up_to_date?(repo_name, commit_sha); end

    # Run Cookstyle checks on the repository
    sig { params(repo_dir: String).returns(T::Hash[Symbol, T.untyped]) }
    def run_cookstyle_checks(repo_dir); end

    # Handle issues found in the repository by creating PR or issue
    sig do
      params(
        result: T::Hash[String, T.untyped],
        repo_dir: String,
        repo_name: String,
        commit_sha: String
      ).returns(T::Hash[String, T.untyped])
    end
    def handle_issues(result, repo_dir, repo_name, commit_sha); end

    # Handle auto-correctable issues by creating a pull request
    sig do
      params(
        result: T::Hash[String, T.untyped],
        repo_dir: String,
        repo_full_name: String,
        branch_name: String,
        _base_commit: String
      ).returns(T::Hash[String, T.untyped])
    end
    def handle_auto_correctable_issues(result, repo_dir, repo_full_name, branch_name, _base_commit); end

    # Handle manual fixes by creating an issue
    sig do
      params(
        result: T::Hash[String, T.untyped],
        repo_full_name: String
      ).returns(T::Hash[String, T.untyped])
    end
    def handle_manual_fixes(result, repo_full_name); end

    # Format PR description based on offense details
    sig { params(offense_details: T::Hash[String, T.untyped]).returns(String) }
    def format_pr_description(offense_details); end

    # Format issue description based on offense details
    sig { params(offense_details: T::Hash[String, T.untyped]).returns(String) }
    def format_issue_description(offense_details); end

    # Update cache with processing results
    sig do
      params(
        repo_name: String,
        commit_sha: String,
        had_issues: T::Boolean,
        result: String,
        processing_time: Float
      ).void
    end
    def update_cache(repo_name, commit_sha, had_issues, result, processing_time); end
  end
end
