# frozen_string_literal: true
# typed: true

require 'sorbet-runtime'

module CookstyleRunner
  # GitHub PR Manager for creating pull requests and issues
  class GitHubPRManager
    extend T::Sig

    # Instance variable declarations for Sorbet
    T::Sig::WithoutRuntime.sig { returns(::Config::Options) }
    attr_reader :settings

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

    T::Sig::WithoutRuntime.sig { returns(T::Boolean) }
    attr_reader :auto_assign_manual_fixes

    T::Sig::WithoutRuntime.sig { returns(String) }
    attr_reader :copilot_assignee

    T::Sig::WithoutRuntime.sig { params(settings: ::Config::Options, github_client: Octokit::Client).void }
    def initialize(settings, github_client)
      @settings = T.let(settings, ::Config::Options)
      @logger = T.let(SemanticLogger[self.class], SemanticLogger::Logger)
      @github_client = github_client
      @owner = T.let(settings.owner || 'sous-chefs', String)
      @branch_name = T.let(settings.branch_name || 'cookstyle-fixes', String)
      @pr_title = T.let(settings.pr_title || 'Automated PR: Cookstyle Changes', String)
      @issue_labels = T.let(settings.issue_labels || [], T::Array[String])
      @create_manual_fix_issues = T.let(boolean_config(settings, :create_manual_fix_issues, true), T::Boolean)
      @auto_assign_manual_fixes = T.let(boolean_config(settings, :auto_assign_manual_fixes, true), T::Boolean)
      @copilot_assignee = T.let(settings.copilot_assignee || 'copilot', String)
    end

    sig { params(repository: String, base_branch: String, head_branch: String, title: String, body: String).returns(T::Boolean) }
    def create_pull_request(repository, base_branch, head_branch, title, body)
      repo_name = extract_repo_name(repository)

      @logger.info('Creating pull request', payload: {
                     repo: repo_name, head_branch: head_branch, base_branch: base_branch, action: 'create_pr'
                   })

      begin
        # Check for existing PR first
        existing_pr = find_existing_pr(repo_name, head_branch)
        pr = T.let(nil, T.nilable(Sawyer::Resource))

        if existing_pr
          @logger.info('Updating existing pull request', payload: {
                         repo: repo_name, pr_number: existing_pr.number, action: 'update_pr'
                       })
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
              @logger.info('Added labels to pull request', payload: {
                             repo: repo_name, pr_number: pr.number, labels: new_labels
                           })
            end
          end
        else
          # Use the GitHub client to create a PR
          # Octokit signature: create_pull_request(repo, base, head, title, body)
          pr = @github_client.create_pull_request(repo_name, base_branch, head_branch, title, body)

          # Apply labels to new PR
          if @issue_labels && !@issue_labels.empty?
            @github_client.add_labels_to_an_issue(repo_name, pr.number, @issue_labels)
            @logger.info('Added labels to pull request', payload: {
                           repo: repo_name, pr_number: pr.number, labels: @issue_labels
                         })
          end
        end

        @logger.info('Pull request created successfully', payload: {
                       repo: repo_name, pr_number: pr.number, action: 'create_pr'
                     })
        true
      rescue StandardError => e
        @logger.error('Failed to create pull request', exception: e, payload: { repo: repo_name, action: 'create_pr' })
        false
      end
    end

    sig { params(repository: String, title: String, body: String).returns(T::Boolean) }
    def create_issue(repository, title, body)
      # Skip issue creation if the feature is disabled
      return false unless @create_manual_fix_issues

      repo_name = extract_repo_name(repository)

      @logger.info('Creating issue', payload: { repo: repo_name, title: title, action: 'create_issue' })

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
          @logger.info('Added labels to issue', payload: {
                         repo: repo_name, issue_number: issue.number, labels: @issue_labels
                       })
        end

        # Assign the issue to the Copilot agent if auto-assign is enabled
        if @auto_assign_manual_fixes && @copilot_assignee && !@copilot_assignee.empty?
          begin
            @github_client.update_issue(repo_name, issue.number, assignees: [@copilot_assignee])
            @logger.info('Assigned issue to Copilot agent', payload: {
                           repo: repo_name, issue_number: issue.number, assignee: @copilot_assignee
                         })
          rescue StandardError => e
            @logger.warn('Failed to assign issue to Copilot agent', exception: e, payload: {
                           repo: repo_name, issue_number: issue.number, assignee: @copilot_assignee
                         })
          end
        end

        @logger.info('Issue created successfully', payload: {
                       repo: repo_name, issue_number: issue.number, action: 'create_issue'
                     })
        true
      rescue StandardError => e
        @logger.error('Failed to create issue', exception: e, payload: { repo: repo_name, action: 'create_issue' })
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
      @logger.error('Error finding existing pull request', exception: e, payload: { repo: repo_name })
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

    # Helper method to safely get boolean configuration values
    # @param settings [Config::Options] Settings object
    # @param field [Symbol] Field name
    # @param default [Boolean] Default value if field is not set
    # @return [Boolean] The boolean value
    sig { params(settings: ::Config::Options, field: Symbol, default: T::Boolean).returns(T::Boolean) }
    def boolean_config(settings, field, default)
      settings.respond_to?(field) && !settings.send(field).nil? ? settings.send(field) : default
    end
  end
end
