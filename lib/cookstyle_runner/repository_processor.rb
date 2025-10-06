# frozen_string_literal: true
# typed: strict

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

    sig { returns(Logger) }
    attr_reader :logger

    sig { returns(T.nilable(Cache)) }
    attr_reader :cache_manager

    sig { returns(T.nilable(T.any(Octokit::Client, Object))) }
    attr_reader :github_client

    sig { returns(T.nilable(GitHubPRManager)) }
    attr_reader :pr_manager

    sig do
      params(
        configuration: Configuration,
        logger: Logger,
        cache_manager: T.nilable(Cache),
        github_client: T.nilable(T.any(Octokit::Client, Object)),
        pr_manager: T.nilable(GitHubPRManager),
        context_manager: T.nilable(ContextManager)
      ).void
    end
    def initialize(configuration:, logger:, cache_manager: nil, github_client: nil, pr_manager: nil, context_manager: nil)
      @configuration = T.let(configuration, Configuration)
      @logger = T.let(logger, Logger)
      @cache_manager = T.let(cache_manager, T.nilable(Cache))
      @github_client = T.let(github_client, T.nilable(T.any(Octokit::Client, Object)))
      @pr_manager = T.let(pr_manager, T.nilable(GitHubPRManager))
      @context_manager = T.let(context_manager, T.nilable(ContextManager))
    end

    # Process a single repository
    def process_repository(repo_name, repo_url)
      start_time = Time.now
      logger.info("Processing repository: #{repo_name}")

      # Prepare result hash with defaults
      result = {
        'name' => repo_name,
        'url' => repo_url,
        'state' => 'skipped',
        'issues_found' => false,
        'time_taken' => 0,
        'error' => nil,
        'message' => ''
      }

      # Set up the working directory for this repository
      repo_dir = prepare_repo_directory(repo_name)

      # Clone or update the repository and check cache status
      begin
        # Get the latest commit SHA from the repository
        commit_sha = current_sha(repo_url, repo_dir)
        return result.merge('state' => 'error', 'error' => 'Failed to get commit SHA') unless commit_sha

        # Skip processing if repository is up to date in cache
        if cache_up_to_date?(repo_name, commit_sha)
          logger.info("Skipping #{repo_name} - No changes detected since last run")
          return result.merge('state' => 'skipped', 'message' => 'No changes detected since last run')
        end
      rescue StandardError => e
        logger.error("Error processing repository #{repo_name}: #{e.message}")
        return result.merge('state' => 'error', 'error' => "Git error: #{e.message}")
      end

      # Run Cookstyle on the repository
      begin
        cookstyle_result = run_cookstyle_checks(repo_dir)
        issues_found = cookstyle_result[:issue_count].positive?

        result = result.merge(
          'state' => 'processed',
          'issues_found' => issues_found,
          'auto_correctable' => cookstyle_result[:auto_correctable_count],
          'manual_fixes' => cookstyle_result[:manual_fixes_count],
          'offense_details' => cookstyle_result[:offense_details]
        )
      rescue StandardError => e
        logger.error("Error running Cookstyle on #{repo_name}: #{e.message}")
        return result.merge('state' => 'error', 'error' => "Cookstyle error: #{e.message}")
      end

      # Create pull request or issue if there are issues (no dry run mode in current implementation)
      result = handle_issues(result, repo_dir, repo_name, commit_sha) if issues_found

      # Update cache if enabled
      update_cache(repo_name, commit_sha, issues_found, JSON.generate(cookstyle_result), Time.now - start_time) if @cache_manager

      # Add the time taken to the result
      result['time_taken'] = Time.now - start_time
      logger.info("Finished processing #{repo_name} in #{result['time_taken'].round(2)}s")

      # Convert to symbol keys for reporter compatibility
      convert_result_to_symbols(result, repo_name)
    end

    private

    # Prepare the repository directory
    def prepare_repo_directory(repo_name)
      workspace_dir = ENV.fetch('GCR_WORKSPACE_DIR', File.join(Dir.pwd, 'tmp', 'repositories'))
      repo_dir = File.join(workspace_dir, repo_name)
      FileUtils.mkdir_p(repo_dir)
      repo_dir
    end

    # Clone or update the repository
    sig { params(repo_url: String, repo_dir: String).returns(String) }
    def current_sha(repo_url, repo_dir)
      # Create a minimal repo context for Git operations
      repo_name = T.must(repo_dir.split('/').last)
      context = Git::RepoContext.new(
        repo_name: repo_name,
        owner: @configuration.owner,
        logger: logger,
        repo_dir: repo_dir,
        repo_url: repo_url
      )

      CookstyleRunner::Git.clone_or_update_repo(context, { branch_name: @configuration.default_branch })
      T.must(CookstyleRunner::Git.current_commit_sha(context))
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
      logger.debug("Running Cookstyle on #{repo_dir}")

      # Create a repo context for Cookstyle operations
      repo_name = T.must(repo_dir.split('/').last)
      context = Git::RepoContext.new(
        repo_name: repo_name,
        owner: @configuration.owner,
        logger: logger,
        repo_dir: repo_dir
      )

      result = CookstyleOperations.run_cookstyle(context, logger)
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
      logger.info("Auto-correcting #{result['auto_correctable']} issues in #{repo_full_name}")

      # Create a repo context for Cookstyle operations
      repo_name = T.must(repo_full_name.split('/').last)
      context = Git::RepoContext.new(
        repo_name: repo_name,
        owner: @configuration.owner,
        logger: logger,
        repo_dir: repo_dir
      )

      # Run cookstyle with autocorrect to fix issues
      CookstyleOperations.run_cookstyle(context, logger)

      # Generate PR description from the ORIGINAL offense details (before auto-correction)
      pr_description = format_pr_description(result['offense_details'])

      # Commit changes and create PR
      begin
        # Commit the changes locally
        commit_message = "Cookstyle auto-corrections\n\nThis change is automatically generated by the GitHub Cookstyle Runner."
        # Create a repo context for Git operations
        repo_name = T.must(repo_dir.split('/').last)
        context = Git::RepoContext.new(
          repo_name: repo_name,
          owner: @configuration.owner,
          logger: logger,
          repo_dir: repo_dir
        )

        # Prepare git configuration
        git_config = {
          branch_name: branch_name,
          git_user_name: @configuration.git_name,
          git_user_email: @configuration.git_email
        }

        Git.add_and_commit_changes(context, commit_message, git_config: git_config)
        Git.create_branch(context, git_config, logger)
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
          logger.info("Created PR for #{repo_full_name}")
        else
          result['error'] = 'Failed to create PR'
          logger.error("Failed to create PR for #{repo_full_name}")
        end
      rescue StandardError => e
        result['error'] = "Failed to create PR: #{e.message}"
        logger.error("Error creating PR for #{repo_full_name}: #{e.message}")
      end

      result
    end

    # Handle manual fixes by creating an issue
    def handle_manual_fixes(result, repo_full_name)
      return result unless @pr_manager

      logger.info("Creating issue for #{result['manual_fixes']} manual fixes in #{repo_full_name}")
      issue_success = create_manual_fix_issue(repo_full_name, result['offense_details'])

      if issue_success
        result['message'] = 'Created issue for manual fixes'
        logger.info("Created issue for #{repo_full_name}")
      else
        result['error'] = 'Failed to create issue'
        logger.error("Failed to create issue for #{repo_full_name}")
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
    sig { params(repo_full_name: String, offense_details: T::Hash[String, T.untyped]).returns(T::Boolean) }
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
      logger.debug("Updated cache for #{repo_name}")
    end

    # Convert result hash to symbol keys for reporter compatibility
    sig { params(result: T::Hash[String, T.untyped], repo_name: String).returns(T::Hash[String, T.untyped]) }
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
