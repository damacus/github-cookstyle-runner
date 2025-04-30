# frozen_string_literal: true

require_relative 'cookstyle_operations'

module CookstyleRunner
  # RepositoryProcessor handles all logic for processing individual repositories:
  # - Cloning/updating repositories
  # - Running Cookstyle checks and autocorrect
  # - Handling retries and error reporting
  # - Interacting with cache and PR managers
  # rubocop:disable Metrics/ClassLength

  class RepositoryProcessor
    # Initialize the repository processor
    # @param config [Hash] Configuration hash
    # @param logger [Logger] Logger instance
    # @param cache_manager [CacheManager] Cache manager instance
    # @param pr_manager [GitHubPRManager] PR manager instance
    # @param context_manager [ContextManager] Context manager instance
    def initialize(config:, logger:, cache_manager:, pr_manager:, context_manager:)
      @config = config
      @logger = logger
      @cache_manager = cache_manager
      @pr_manager = pr_manager
      @context_manager = context_manager # Retained for potential future use
    end

    # Process a single repository
    # @param repo_url [String] Repository URL
    # @param processed_count [Integer] Number of repositories processed so far
    # @param total_repos [Integer] Total number of repositories to process
    # @return [Hash] A hash containing processing results:
    #   - :status [Symbol] :no_issues, :issues_found, :skipped, or :error
    #   - :repo_name [String] The name of the repository processed
    #   - :pr_details [Hash, nil] Details of created PR, if any
    #   - :pr_error [Hash, nil] Details of PR creation error, if any
    #   - :commit_sha [String] Final commit SHA after processing
    #   - :had_issues [Boolean] Whether Cookstyle found any offenses
    #   - :total_offenses [Integer] Count of all offenses found
    #   - :output [Hash] Parsed JSON output from Cookstyle
    #   - :processing_time [Float] Time taken for Cookstyle run
    #   - :error_message [String, nil] Error message if status is :error
    def process_repository(repo_url, processed_count, total_repos)
      repo_name, repo_dir = setup_working_directory(repo_url)
      log_processing(repo_name, processed_count, total_repos)
      context = ContextManager.instance.get_repo_context(repo_url, repo_dir)

      unless GitOperations.clone_or_update_repo(context, @config[:default_branch])
        return { status: :error, repo_name: repo_name, error_message: 'Failed to clone/update repository' }
      end

      return { status: :skipped, repo_name: repo_name } if should_skip_repository?(repo_name)

      # Run cookstyle and get the result hash
      result_hash = run_in_subprocess(context, repo_dir, repo_name)

      update_cache_if_needed(repo_name, result_hash)

      # Return the full result hash, adding repo_name
      result_hash.merge(repo_name: repo_name)
    rescue StandardError => e
      logger.error("Error processing repository #{repo_name}: #{e.message}")
      logger.debug(e.backtrace.join("\n"))
      # Return error status and repo name
      { status: :error, repo_name: repo_name, error_message: e.message }
    end

    private

    # --- Setup and Logging ---
    def setup_working_directory(repo_url)
      repo_name = File.basename(repo_url, '.git')
      # Calculate the intended repo directory path
      repo_dir = File.join(@config[:cache_dir], repo_name)
      # Ensure only the base cache directory exists
      FileUtils.mkdir_p(@config[:cache_dir])
      # Return repo_name and the calculated repo_dir path
      [repo_name, repo_dir]
    end

    def log_processing(repo_name, processed_count, total_repos)
      logger.info("[#{processed_count}/#{total_repos}] Processing: #{repo_name}")
    end

    # --- Caching ---
    def update_cache_if_needed(repo_name, result)
      # Only cache successful runs (no_issues or issues_found)
      return unless @config[:use_cache] && %i[no_issues issues_found].include?(result[:status])

      @cache_manager.update(repo_name, result[:commit_sha], result[:had_issues], result[:output],
                            result[:processing_time])
    end

    attr_reader :logger, :config # Make config accessible

    # --- Core Cookstyle Execution ---
    # Run Cookstyle checks and auto-correction
    # @param context [Context] Context instance
    # @param repo_dir [String] Directory containing repository
    # @param repo_name [String] Repository name
    # @return [Hash] Result of Cookstyle execution, including status and PR info
    def run_in_subprocess(context, repo_dir, repo_name)
      start_time = Time.now
      logger.debug("Starting Cookstyle run for #{repo_name} in #{repo_dir}")

      # CookstyleOperations.run_cookstyle returns an ARRAY:
      # [parsed_json, num_auto, num_manual, pr_desc, issue_desc, changes_committed]
      # OR the DEFAULT_ERROR_RETURN
      parsed_json, report = CookstyleOperations.run_cookstyle(context, logger)

      # Check if CookstyleOperations returned the default error signature
      if report.error
        logger.error("CookstyleOperations reported an error for #{repo_name}, returning error status.")
        return { status: :error, repo_name: repo_name, error_message: 'Cookstyle execution failed' }
      end

      final_commit_sha_after_run = GitOperations.get_latest_commit_sha(context)
      logger.debug("Final commit SHA after run for #{repo_name}: #{final_commit_sha_after_run}")
      total_offenses = report.num_auto + report.num_manual

      logger.info("Cookstyle run finished for #{repo_name}. Auto-correctable: #{report.num_auto}, Manual: #{report.num_manual}, Git changes committed: #{report.changes_committed}")

      # --- Handle PR or Issue Creation --- # Pass repo_dir from context
      pr_result = handle_cookstyle_pr_creation(
        repo_name: repo_name,
        repo_dir: context.repo_dir, # Get repo_dir from context
        num_auto_correctable: report.num_auto, # Use variable
        num_manual_correctable: report.num_manual, # Use variable
        pr_description: report.pr_description,       # Use variable
        issue_description: report.issue_description, # Use variable
        git_changes_made: report.changes_committed    # Use variable
      )

      # Combine status, cookstyle data, and PR result
      {
        status: total_offenses.zero? ? :no_issues : :issues_found,
        commit_sha: final_commit_sha_after_run,
        had_issues: total_offenses.positive?,
        total_offenses: total_offenses,
        output: parsed_json, # Use variable for parsed JSON output
        processing_time: Time.now - start_time
      }.merge(pr_result)
    rescue StandardError => e # Catch errors specifically within run_in_subprocess
      logger.error("Internal error during subprocess processing for #{repo_name}: #{e.message}")
      logger.debug(e.backtrace.join("\n"))
      { status: :error, repo_name: repo_name, error_message: "Internal processing error: #{e.message}" }
    end

    # --- Helper methods for run_in_subprocess ---
    # Handles the creation of Pull Requests or Issues based on Cookstyle results
    # Returns a hash containing :pr_details (for PR/Issue) or :pr_error if creation failed, or empty hash otherwise.
    def handle_cookstyle_pr_creation(repo_name:, repo_dir:, num_auto_correctable:, num_manual_correctable:,
                                     pr_description:, issue_description:, git_changes_made:)
      # No action needed if no offenses or changes
      return {} unless correctable?

      # Attempt auto-fix PR if applicable
      if auto_fix_applicable?(num_auto_correctable, git_changes_made)
        logger.info("Attempting to create auto-fix PR for #{repo_name}")
        # Pass the context object now required by create_pull_request
        pr_created, pr_details = @pr_manager.create_pull_request(repo_name, repo_dir, pr_description, context)
        logger.info("Auto-fix PR creation result for #{repo_name}: #{pr_created ? 'Success' : 'Failed/Skipped'}")
        return assign_pr_result(pr_created, pr_details, repo_name, 'pull_request')

      # Attempt manual-fix Issue if applicable (and auto-fix didn't apply)
      elsif num_manual_correctable.positive? && config[:create_manual_fix_issues]
        logger.info("Attempting to create manual-fix issue for #{repo_name}")
        issue_created, issue_details = @pr_manager.create_issue_for_manual_fixes(repo_name, issue_description)
        logger.info("Manual-fix issue creation result for #{repo_name}: #{issue_created ? 'Success' : 'Failed'}")
        # Use assign_pr_result helper, type will be 'issue' from issue_details
        return assign_pr_result(issue_created, issue_details, repo_name, 'issue')
      end

      # No applicable PR/Issue scenario was met
      logger.info("No PR or Issue created for #{repo_name} (Auto: #{num_auto_correctable}, Manual: #{num_manual_correctable}, Changes: #{git_changes_made}, Create Issues: #{config[:create_manual_fix_issues]})")
      {} # Return empty hash if no action taken
    end

    def correctable?(num_auto_correctable, num_manual_correctable)
      if num_auto_correctable.positive? || num_manual_correctable.positive?
        logger.debug(
          "Auto: #{num_auto_correctable}, " \
          "Manual: #{num_manual_correctable}, " \
          "Changes: #{git_changes_made}, " \
          "Create Issues: #{config[:create_manual_fix_issues]}"
        )
        true
      else
        logger.info("No offenses found for #{repo_name}, skipping PR/Issue creation.")
        false
      end
    end

    def auto_fix_applicable?(num_auto_correctable, git_changes_made)
      num_auto_correctable.positive? && git_changes_made
    end

    # Helper to assign the result hash for PR/Issue creation attempts
    def assign_pr_result(created, details, repo_name, type)
      if created && details
        logger.info("Successfully created #{details[:type]} ##{details[:number]} for #{repo_name}: #{details[:html_url]}")
        { pr_details: details } # Use generic key :pr_details for both PRs and Issues
      else
        logger.error("Failed to create #{type} for #{repo_name}")
        { pr_error: { repo_name: repo_name, type: type, message: "Failed to create #{type}" } }
      end
    end

    # --- Filtering and Skipping ---
    # Check if a repository should be skipped based on inclusion/exclusion lists
    # @param repo_name [String] Repository name
    # @return [Boolean] True if the repository should be skipped
    def should_skip_repository?(repo_name)
      RepositoryManager.should_skip_repository?(repo_name, config[:include_repos], config[:exclude_repos]) # Use attr_reader
    end
  end
  # rubocop:enable Metrics/ClassLength
end
