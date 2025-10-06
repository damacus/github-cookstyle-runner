# frozen_string_literal: true
# typed: strict

require 'sorbet-runtime'

module CookstyleRunner
  # GitHub PR Manager for creating pull requests and issues
  class GitHubPRManager
    extend T::Sig

    # Instance variable declarations for Sorbet
    T::Sig::WithoutRuntime.sig { returns(::Config::Options) }
    attr_reader :settings

    T::Sig::WithoutRuntime.sig { returns(Logger) }
    attr_reader :logger

    T::Sig::WithoutRuntime.sig { returns(Octokit::Client) }
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

    T::Sig::WithoutRuntime.sig { params(settings: ::Config::Options, logger: Logger, github_client: Octokit::Client).void }
    def initialize(settings, logger, github_client)
      @settings = T.let(settings, ::Config::Options)
      @logger = T.let(logger, Logger)
      @github_client = github_client

      # Set default values for settings that might be missing
      @owner = T.let(settings.owner || 'sous-chefs', String)
      @branch_name = T.let(settings.branch_name || 'cookstyle-fixes', String)
      @pr_title = T.let(settings.pr_title || 'Automated PR: Cookstyle Changes', String)
      @issue_labels = T.let(settings.issue_labels || [], T::Array[String])
      @create_manual_fix_issues = T.let(settings.create_manual_fix_issues || true, T::Boolean)
    end

    sig { params(repository: String, base_branch: String, head_branch: String, title: String, body: String).returns(T::Boolean) }
    def create_pull_request(repository, base_branch, head_branch, title, body)
      repo_name = extract_repo_name(repository)

      @logger.info("Creating PR for #{repo_name}: #{head_branch} -> #{base_branch}")

      begin
        # Check for existing PR first
        existing_pr = find_existing_pr(repo_name, head_branch)
        pr = T.let(nil, T.nilable(Sawyer::Resource))

        if existing_pr
          @logger.info("Pull request already exists for #{repo_name}, updating PR ##{existing_pr.number}")
          pr = @github_client.update_pull_request(
            repo_name,
            existing_pr.number,
            title: title,
            body: body
          )

          # Update labels for existing PR (only add new ones)
          if @issue_labels && !@issue_labels.empty?
            existing_labels = @github_client.labels_for_issue(repo_name, existing_pr.number).map(&:name)
            new_labels = @issue_labels - existing_labels
            if new_labels.any?
              @github_client.add_labels_to_an_issue(repo_name, pr.number, new_labels)
              @logger.info("Added labels #{new_labels.join(', ')} to PR ##{pr.number}")
            end
          end
        else
          # Use the GitHub client to create a PR
          # Octokit signature: create_pull_request(repo, base, head, title, body)
          pr = @github_client.create_pull_request(
            repo_name,
            base_branch,
            head_branch,
            title,
            body
          )

          # Apply labels to new PR
          if @issue_labels && !@issue_labels.empty?
            @github_client.add_labels_to_an_issue(repo_name, pr.number, @issue_labels)
            @logger.info("Added labels #{@issue_labels.join(', ')} to PR ##{pr.number}")
          end
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

    # Find an existing PR for a branch
    sig { params(repo_name: String, branch_name: String).returns(T.nilable(Sawyer::Resource)) }
    def find_existing_pr(repo_name, branch_name)
      prs = @github_client.pull_requests(repo_name, state: 'open')
      prs.find { |pr| pr.head.ref == branch_name }
    rescue StandardError => e
      @logger.error("Error finding existing PR: #{e.message}")
      nil
    end

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
