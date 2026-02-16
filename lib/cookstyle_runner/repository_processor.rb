# frozen_string_literal: true
# typed: true

require 'sorbet-runtime'
require 'fileutils'
require 'json'
require 'pp'
require_relative 'git'
require_relative 'cookstyle_operations'
require_relative 'github_api'
require_relative 'cache'

module CookstyleRunner
  # =============================================================================
  # GitHub Cookstyle Runner - Repository Processor
  # =============================================================================
  #
  # This class orchestrates the processing of a single repository:
  # - Cloning/updating the repository
  # - Running Cookstyle checks
  # - Processing the results
  # - Creating pull requests or issues as needed
  #
  class RepositoryProcessor
    extend T::Sig

    sig { returns(Configuration) }
    attr_reader :configuration

    sig { returns(T.nilable(Cache)) }
    attr_reader :cache_manager

    sig { returns(T.nilable(T.any(Octokit::Client, Object))) }
    attr_reader :github_client

    sig { returns(T.nilable(GitHubPRManager)) }
    attr_reader :pr_manager

    sig do
      params(
        configuration: Configuration,
        cache_manager: T.nilable(Cache),
        github_client: T.nilable(T.any(Octokit::Client, Object)),
        pr_manager: T.nilable(GitHubPRManager),
        context_manager: T.nilable(ContextManager)
      ).void
    end
    def initialize(configuration:, cache_manager: nil, github_client: nil, pr_manager: nil, context_manager: nil)
      @configuration = T.let(configuration, Configuration)
      @logger = T.let(SemanticLogger[self.class], SemanticLogger::Logger)
      @cache_manager = T.let(cache_manager, T.nilable(Cache))
      @github_client = T.let(github_client, T.nilable(T.any(Octokit::Client, Object)))
      @pr_manager = T.let(pr_manager, T.nilable(GitHubPRManager))
      @context_manager = T.let(context_manager, T.nilable(ContextManager))
    end

    # Process a single repository
    sig { params(repo_name: String, repo_url: String).returns(T::Hash[Symbol, Object]) }
    def process_repository(repo_name, repo_url)
      start_time = Time.now
      logger.debug('Processing repository', payload: { repo: repo_name, operation: 'process_repository' })

      result = build_default_result(repo_name, repo_url)
      repo_dir = prepare_repo_directory(repo_name)
      commit_state = resolve_commit_state(repo_name, repo_url, repo_dir, result)
      return T.cast(commit_state[:final_result], T::Hash[Symbol, Object]) if commit_state[:final_result]

      commit_sha = T.must(T.cast(commit_state[:commit_sha], T.nilable(String)))
      cookstyle_state = resolve_cookstyle_state(repo_name, repo_dir, result)
      return T.cast(cookstyle_state[:final_result], T::Hash[Symbol, Object]) if cookstyle_state[:final_result]

      finalize_processing(repo_name, repo_dir, commit_sha, start_time, T.cast(cookstyle_state, T::Hash[Symbol, Object]))
    end

    private

    sig { returns(SemanticLogger::Logger) }
    attr_reader :logger

    sig { params(repo_name: String, repo_url: String).returns(T::Hash[String, Object]) }
    def build_default_result(repo_name, repo_url)
      {
        'name' => repo_name,
        'url' => repo_url,
        'state' => 'skipped',
        'issues_found' => false,
        'time_taken' => 0,
        'error' => nil,
        'message' => ''
      }
    end

    sig do
      params(
        repo_name: String,
        repo_url: String,
        repo_dir: String,
        result: T::Hash[String, Object]
      ).returns(T::Hash[Symbol, Object])
    end
    def resolve_commit_state(repo_name, repo_url, repo_dir, result)
      commit_sha = current_sha(repo_url, repo_dir)
      unless commit_sha
        logger.error('Failed to get commit SHA', payload: { repo: repo_name, operation: 'get_commit_sha' })
        return commit_sha_failure_state(result, repo_name)
      end

      if cache_up_to_date?(repo_name, commit_sha)
        logger.info('Skipping repository - no changes detected since last run', payload: { repo: repo_name, status: 'skipped' })
        return cache_skip_state(result, repo_name)
      end

      { commit_sha: commit_sha, final_result: nil }
    rescue StandardError => e
      logger.error('Error processing repository', payload: { repo: repo_name, error: e.message, operation: 'process_repository' })
      git_error_state(result, repo_name, e)
    end

    sig do
      params(
        repo_name: String,
        repo_dir: String,
        result: T::Hash[String, Object]
      ).returns(T::Hash[Symbol, Object])
    end
    def resolve_cookstyle_state(repo_name, repo_dir, result)
      cookstyle_result = run_cookstyle_checks(repo_dir)
      issues_found = cookstyle_result[:issue_count].positive?
      updated_result = processed_result(result, issues_found, cookstyle_result)

      {
        result: updated_result,
        issues_found: issues_found,
        cookstyle_result: cookstyle_result,
        final_result: nil
      }
    rescue StandardError => e
      logger.error('Error running Cookstyle', payload: { repo: repo_name, error: e.message, operation: 'run_cookstyle' })
      cookstyle_error_state(result, repo_name, e)
    end

    sig { params(result: T::Hash[String, Object], repo_name: String).returns(T::Hash[Symbol, Object]) }
    def commit_sha_failure_state(result, repo_name)
      error_result = result.merge('state' => 'error', 'error' => 'Failed to get commit SHA')
      { final_result: convert_result_to_symbols(error_result, repo_name) }
    end

    sig { params(result: T::Hash[String, Object], repo_name: String).returns(T::Hash[Symbol, Object]) }
    def cache_skip_state(result, repo_name)
      skip_result = result.merge('state' => 'skipped', 'message' => 'No changes detected since last run')
      { final_result: convert_result_to_symbols(skip_result, repo_name) }
    end

    sig { params(result: T::Hash[String, Object], repo_name: String, error: StandardError).returns(T::Hash[Symbol, Object]) }
    def git_error_state(result, repo_name, error)
      error_result = result.merge('state' => 'error', 'error' => "Git error: #{error.message}")
      { final_result: convert_result_to_symbols(error_result, repo_name) }
    end

    sig do
      params(
        result: T::Hash[String, Object],
        issues_found: T::Boolean,
        cookstyle_result: T::Hash[Symbol, Object]
      ).returns(T::Hash[String, Object])
    end
    def processed_result(result, issues_found, cookstyle_result)
      result.merge(
        'state' => 'processed',
        'issues_found' => issues_found,
        'auto_correctable' => cookstyle_result[:auto_correctable_count],
        'manual_fixes' => cookstyle_result[:manual_fixes_count],
        'offense_details' => cookstyle_result[:offense_details]
      )
    end

    sig { params(result: T::Hash[String, Object], repo_name: String, error: StandardError).returns(T::Hash[Symbol, Object]) }
    def cookstyle_error_state(result, repo_name, error)
      error_result = result.merge('state' => 'error', 'error' => "Cookstyle error: #{error.message}")
      { final_result: convert_result_to_symbols(error_result, repo_name) }
    end

    sig do
      params(
        repo_name: String,
        repo_dir: String,
        commit_sha: String,
        start_time: Time,
        cookstyle_state: T::Hash[Symbol, Object]
      ).returns(T::Hash[Symbol, Object])
    end
    def finalize_processing(repo_name, repo_dir, commit_sha, start_time, cookstyle_state)
      result = T.cast(cookstyle_state[:result], T::Hash[String, Object])
      issues_found = T.cast(cookstyle_state[:issues_found], T::Boolean)
      cookstyle_result = T.cast(cookstyle_state[:cookstyle_result], T::Hash[Symbol, Object])

      result = handle_issues(result, repo_dir, repo_name, commit_sha) if issues_found
      elapsed_time = Time.now - start_time
      update_cache(repo_name, commit_sha, issues_found, JSON.generate(cookstyle_result), elapsed_time) if @cache_manager

      result['time_taken'] = elapsed_time
      logger.info('Finished processing repository', payload: { repo: repo_name, time_taken: elapsed_time.round(2), status: result['state'] })
      convert_result_to_symbols(result, repo_name)
    end

    # Prepare the repository directory
    def prepare_repo_directory(repo_name)
      workspace_dir = ENV.fetch('GCR_WORKSPACE_DIR', File.join(Dir.pwd, 'tmp', 'repositories'))
      repo_dir = File.join(workspace_dir, repo_name)
      FileUtils.mkdir_p(repo_dir)
      repo_dir
    end

    # Create a RepoContext for the given repository directory
    # @param repo_dir [String] The repository directory path
    # @param repo_url [T.nilable(String)] Optional repository URL
    # @return [Git::RepoContext] The created RepoContext
    sig { params(repo_dir: String, repo_url: T.nilable(String)).returns(Git::RepoContext) }
    def create_repo_context(repo_dir, repo_url = nil)
      repo_name = T.must(repo_dir.split('/').last)
      Git::RepoContext.new(
        repo_name: repo_name,
        owner: @configuration.owner,
        repo_dir: repo_dir,
        repo_url: repo_url
      )
    end

    # Clone or update the repository
    sig { params(repo_url: String, repo_dir: String).returns(T.nilable(String)) }
    def current_sha(repo_url, repo_dir)
      # Create a minimal repo context for Git operations
      context = create_repo_context(repo_dir, repo_url)

      CookstyleRunner::Git.clone_or_update_repo(context, { branch_name: @configuration.default_branch })
      CookstyleRunner::Git.current_commit_sha(context)
    end

    # Check if the repository is up to date in the cache
    def cache_up_to_date?(repo_name, commit_sha)
      return false unless @cache_manager && @configuration.use_cache
      return false if @configuration.force_refresh

      max_age_days = @configuration.cache_max_age
      max_age_seconds = max_age_days * 24 * 60 * 60
      @cache_manager.up_to_date?(repo_name, commit_sha, max_age: max_age_seconds)
    end

    # Run Cookstyle checks on the repository
    def run_cookstyle_checks(repo_dir)
      logger.debug('Running Cookstyle', payload: { repo_dir: repo_dir, operation: 'run_cookstyle' })

      # Create a repo context for Cookstyle operations
      context = create_repo_context(repo_dir)

      result = CookstyleOperations.run_cookstyle(context)
      report = result[:report]

      # Transform the result to match expected format
      {
        issue_count: report.total_correctable,
        auto_correctable_count: report.num_auto,
        manual_fixes_count: report.num_manual,
        offense_details: result[:parsed_json]
      }
    end

    # Handle issues found in the repository by creating PR or issue
    def handle_issues(result, repo_dir, repo_name, commit_sha)
      return result unless @pr_manager

      # Prepare strings for PR/issue
      repo_full_name = "#{@configuration.owner}/#{repo_name}"
      branch_name = @configuration.branch_name

      if result['auto_correctable'].positive?
        # Create pull request with auto-corrected changes
        handle_auto_correctable_issues(result, repo_dir, repo_full_name, branch_name, commit_sha)
      elsif result['manual_fixes'].positive?
        # Create issue with details for manual fixing
        handle_manual_fixes(result, repo_full_name)
      else
        # No actionable issues, just return the result
        result
      end
    end

    # Handle auto-correctable issues by creating a pull request
    def handle_auto_correctable_issues(result, repo_dir, repo_full_name, branch_name, _base_commit)
      return result unless @pr_manager

      # Run Cookstyle with auto-correct
      logger.info('Auto-correcting issues', payload: { repo: repo_full_name, count: result['auto_correctable'], operation: 'auto_correct' })

      # Create a repo context for Cookstyle operations
      context = create_repo_context(repo_dir)

      # Run cookstyle with autocorrect to fix issues
      CookstyleOperations.run_cookstyle(context)
      pr_description = format_pr_description(result['offense_details'])

      # Commit changes and create PR
      begin
        # Commit the changes locally
        commit_message = "Cookstyle auto-corrections\n\nThis change is automatically generated by the GitHub Cookstyle Runner."
        # Create a repo context for Git operations
        context = create_repo_context(repo_dir)

        # Prepare git configuration
        git_config = {
          branch_name: branch_name,
          git_user_name: @configuration.git_name,
          git_user_email: @configuration.git_email
        }

        # Create branch first (this sets up git config)
        Git.create_branch(context, git_config)
        Git.add_and_commit_changes(context, commit_message)
        Git.push_branch(context, branch_name)

        pr_success = @pr_manager.create_pull_request(
          repo_full_name,
          @configuration.default_branch,
          branch_name,
          @configuration.pr_title,
          pr_description
        )

        if pr_success
          result['message'] = 'Created PR with auto-corrected changes'
          logger.info('Created PR', payload: { repo: repo_full_name, operation: 'create_pr' })
        else
          result['error'] = 'Failed to create PR'
          logger.error('Failed to create PR', payload: { repo: repo_full_name, operation: 'create_pr' })
        end
      rescue StandardError => e
        result['error'] = "Failed to create PR: #{e.message}"
        logger.error('Error creating PR', payload: { repo: repo_full_name, error: e.message, operation: 'create_pr' })
      end

      result
    end

    # Handle manual fixes by creating an issue
    def handle_manual_fixes(result, repo_full_name)
      return result unless @pr_manager

      logger.info('Creating issue for manual fixes', payload: { repo: repo_full_name, count: result['manual_fixes'], operation: 'create_issue' })
      issue_success = create_manual_fix_issue(repo_full_name, result['offense_details'])

      if issue_success
        result['message'] = 'Created issue for manual fixes'
        logger.info('Created issue', payload: { repo: repo_full_name, operation: 'create_issue' })
      else
        result['error'] = 'Failed to create issue'
        logger.error('Failed to create issue', payload: { repo: repo_full_name, operation: 'create_issue' })
      end

      result
    end

    # Format PR description based on offense details
    def format_pr_description(offense_details)
      CookstyleRunner::Formatter.format_pr_description(offense_details)
    end

    # Format issue description based on offense details
    def format_issue_description(offense_details)
      CookstyleRunner::Formatter.format_issue_description(offense_details)
    end

    # Create a manual fix issue
    sig { params(repo_full_name: String, offense_details: T::Hash[String, Object]).returns(T::Boolean) }
    def create_manual_fix_issue(repo_full_name, offense_details)
      T.must(@pr_manager).create_issue(
        repo_full_name,
        'Manual Cookstyle Fixes Required',
        format_issue_description(offense_details)
      )
    end

    # Update cache with processing results
    def update_cache(repo_name, commit_sha, had_issues, result, processing_time)
      return unless @cache_manager && @configuration.use_cache

      @cache_manager.update(repo_name, commit_sha, had_issues, result, processing_time)
      logger.debug('Updated cache', payload: { repo: repo_name, operation: 'update_cache' })
    end

    # Convert result hash to symbol keys for reporter compatibility
    sig { params(result: T::Hash[String, Object], repo_name: String).returns(T::Hash[Symbol, Object]) }
    def convert_result_to_symbols(result, repo_name)
      status = if result['state'] == 'processed'
                 result['issues_found'] ? :issues_found : :no_issues
               elsif result['state'] == 'skipped'
                 :skipped
               else
                 :error # Treat error and unknown states as errors
               end

      {
        repo_name: repo_name,
        status: status,
        error_message: result['error'],
        message: result['message'],
        time_taken: result['time_taken']
      }
    end
  end
end
