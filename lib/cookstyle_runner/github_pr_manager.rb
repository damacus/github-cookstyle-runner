# frozen_string_literal: true
# typed: strict

require 'sorbet-runtime'

module CookstyleRunner
  # GitHub PR Manager for creating pull requests and issues
  class GitHubPRManager
    extend T::Sig

    # Instance variable declarations for Sorbet
    T::Sig::WithoutRuntime.sig { returns(T.untyped) }
    attr_reader :settings

    T::Sig::WithoutRuntime.sig { returns(T.untyped) }
    attr_reader :logger

    T::Sig::WithoutRuntime.sig { returns(T.untyped) }
    attr_reader :github_client

    T::Sig::WithoutRuntime.sig { returns(String) }
    attr_reader :owner

    T::Sig::WithoutRuntime.sig { returns(String) }
    attr_reader :branch_name

    T::Sig::WithoutRuntime.sig { returns(String) }
    attr_reader :pr_title

    T::Sig::WithoutRuntime.sig { returns(T::Array[String]) }
    attr_reader :issue_labels

    T::Sig::WithoutRuntime.sig { returns(T::Boolean) }
    attr_reader :create_manual_fix_issues

    sig { params(settings: T.untyped, logger: T.untyped, github_client: T.untyped).void }
    def initialize(settings, logger, github_client)
      @settings = T.let(settings, T.untyped)
      @logger = T.let(logger, T.untyped)
      @github_client = T.let(github_client, T.untyped)

      # Set default values for settings that might be missing
      @owner = T.let(settings.respond_to?(:owner) ? settings.owner : 'sous-chefs', String)
      @branch_name = T.let(settings.respond_to?(:branch_name) ? settings.branch_name : 'cookstyle-fixes', String)
      @pr_title = T.let(settings.respond_to?(:pr_title) ? settings.pr_title : 'Automated PR: Cookstyle Changes', String)
      @issue_labels = T.let(settings.respond_to?(:issue_labels) ? settings.issue_labels : [], T::Array[String])
      @create_manual_fix_issues = T.let(settings.respond_to?(:create_manual_fix_issues) ? settings.create_manual_fix_issues : true, T::Boolean)
    end

    sig { params(repository: String, branch: String, title: String, body: String).returns(T::Boolean) }
    def create_pull_request(repository, branch, title, body)
      repo_name = extract_repo_name(repository)

      @logger.info("Creating PR for #{repo_name} with title: #{title}")

      begin
        # Use the GitHub client to create a PR
        pr = @github_client.create_pull_request(
          repo_name,
          @branch_name,
          branch,
          title,
          body
        )

        # Apply labels if they exist
        if @issue_labels && !@issue_labels.empty?
          @github_client.add_labels_to_an_issue(repo_name, pr.number, @issue_labels)
          @logger.info("Added labels #{@issue_labels.join(', ')} to PR ##{pr.number}")
        end

        @logger.info("Successfully created PR ##{pr.number} for #{repo_name}")
        true
      rescue StandardError => e
        @logger.error("Failed to create PR for #{repo_name}: #{e.message}")
        false
      end
    end

    sig { params(repository: String, title: String, body: String).returns(T::Boolean) }
    def create_issue(repository, title, body)
      # Skip issue creation if the feature is disabled
      return false unless @create_manual_fix_issues

      repo_name = extract_repo_name(repository)

      @logger.info("Creating issue for #{repo_name} with title: #{title}")

      begin
        # Use the GitHub client to create an issue
        issue = @github_client.create_issue(
          repo_name,
          title,
          body
        )

        # Apply labels if they exist
        if @issue_labels && !@issue_labels.empty?
          @github_client.add_labels_to_an_issue(repo_name, issue.number, @issue_labels)
          @logger.info("Added labels #{@issue_labels.join(', ')} to Issue ##{issue.number}")
        end

        @logger.info("Successfully created Issue ##{issue.number} for #{repo_name}")
        true
      rescue StandardError => e
        @logger.error("Failed to create issue for #{repo_name}: #{e.message}")
        false
      end
    end

    private

    # Extract the repository name from a full repository URL or path
    sig { params(repository: String).returns(String) }
    def extract_repo_name(repository)
      # Handle URLs like https://github.com/sous-chefs/repo-name
      if repository.include?('github.com')
        parts = repository.split('/')
        "#{parts[-2]}/#{parts[-1]}"
      else
        # Handle direct repo names or owner/repo format
        repository.include?('/') ? repository : "#{@owner}/#{repository}"
      end
    end
  end
end
