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
    def initialize(config:, logger:, cache_manager:, pr_manager:)
      @config = config
      @logger = logger
      @cache_manager = cache_manager
      @pr_manager = pr_manager
    end

    # Process a single repository
    # @param repo_url [String] Repository URL
    # @param processed_count [Integer] Number of repositories processed so far
    # @param total_repos [Integer] Total number of repositories to process
    # @return [Symbol] :success, :error, or :skipped
    def process_repository(repo_url, processed_count, total_repos)
      repo_name, _, repo_dir = setup_working_directory(repo_url)
      log_processing(repo_name, processed_count, total_repos)

      # Get a repository context from the context manager
      context = ContextManager.instance.get_repo_context(repo_url, repo_dir)
      return :error unless GitOperations.clone_or_update_repo(context, @config[:default_branch])

      return :skipped if should_skip_repository?(repo_name)

      result = run_in_subprocess(repo_url, repo_dir, repo_name)
      update_cache_if_needed(repo_name, result)
      result[:status]
    rescue StandardError => e
      handle_processing_error(e, repo_name, repo_url, processed_count, total_repos)
    end

    private

    def setup_working_directory(repo_url)
      repo_name = File.basename(repo_url, '.git')
      thread_id = Thread.current.object_id
      thread_dir = File.join(@config[:cache_dir], "thread_#{thread_id}")
      repo_dir = File.join(thread_dir, repo_name)
      FileUtils.mkdir_p(thread_dir) unless Dir.exist?(thread_dir)
      [repo_name, thread_dir, repo_dir]
    end

    def log_processing(repo_name, processed_count, total_repos)
      logger.info("[#{processed_count}/#{total_repos}] Processing: #{repo_name}")
    end

    def update_cache_if_needed(repo_name, result)
      return unless @config[:use_cache] && result[:status] == :success

      @cache_manager.update(repo_name, result[:commit_sha], result[:had_issues], result[:output],
                            result[:processing_time])
    end

    def handle_processing_error(error, repo_name, repo_url, processed_count, total_repos)
      logger.error("Error processing repository #{repo_name}: #{error.message}")
      logger.debug(error.backtrace.join("\n"))
      retry_operation(repo_url, processed_count, total_repos) ? :success : :error
    end

    attr_reader :logger


    # Run Cookstyle checks and auto-correction in a subprocess
    # @param repo_url [String] Repository URL
    # @param repo_dir [String] Directory containing repository
    # @param repo_name [String] Repository name
    # @return [Hash] Result of Cookstyle execution
    def run_in_subprocess(repo_url, repo_dir, repo_name)
      start_time = Time.now
      initial_commit_sha = GitOperations.get_latest_commit_sha(repo_dir)
      @logger.debug("Initial commit SHA for #{repo_name}: #{initial_commit_sha}")

      # --- Run Cookstyle using CookstyleOperations ---
      parsed_json, num_auto_correctable, num_manual_correctable, pr_description, issue_description = CookstyleOperations.run_cookstyle(repo_dir, @logger)

      final_commit_sha = GitOperations.get_latest_commit_sha(repo_dir)
      @logger.debug("Final commit SHA for #{repo_name}: #{final_commit_sha}")

      # Determine outcomes
      git_changes_made = initial_commit_sha != final_commit_sha
      manual_attention_needed = num_manual_correctable.positive?
      total_offenses = num_auto_correctable + num_manual_correctable
      exit_status = total_offenses.positive? ? 1 : 0 # Simulate exit status

      @logger.info("Cookstyle run finished for #{repo_name}. Auto-correctable: #{num_auto_correctable}, Manual: #{num_manual_correctable}, Git changes: #{git_changes_made}")

      # --- Handle PR or Issue Creation ---
      handle_cookstyle_pr_creation(
        repo_name: repo_name,
        repo_dir: repo_dir,
        num_auto_correctable: num_auto_correctable,
        num_manual_correctable: num_manual_correctable,
        pr_description: pr_description,
        issue_description: issue_description,
        git_changes_made: git_changes_made
      )
      # ---------------------------------

      # --- Build Result ---
      build_result_hash(
        exit_status, # Simulate exit status
        final_commit_sha,
        total_offenses, # Pass total offenses count
        parsed_json, # Pass the full parsed JSON
        Time.now - start_time
      )
      # -------------------
    end

    # --- Helper methods for run_in_subprocess ---
    def handle_cookstyle_pr_creation(repo_name:, repo_dir:, num_auto_correctable:, num_manual_correctable:, pr_description:, issue_description:, git_changes_made:)
      return unless num_auto_correctable.positive? || num_manual_correctable.positive?

      if auto_fix_applicable?(num_auto_correctable, git_changes_made)
        pr_created, pr_details = @pr_manager.create_pull_request(repo_name, repo_dir, pr_description)
        logger.info("Pull request #{pr_created ? 'created' : 'not created'} for #{repo_name}")
        assign_pr_result(pr_created, pr_details, repo_name, 'auto-fix')
        return
      end
      return unless manual_fix_applicable?(num_manual_correctable)

      handle_manual_fix_pr(repo_name, repo_dir, issue_description)
    end

    def auto_fix_applicable?(num_auto_correctable, git_changes_made)
      num_auto_correctable.positive? && git_changes_made
    end

    def manual_fix_applicable?(num_manual_correctable)
      num_manual_correctable.positive? && @config[:create_manual_fix_prs]
    end

    def handle_manual_fix_pr(repo_name, repo_dir, issue_description)
      manual_fix_message = <<~MSG
        Cookstyle found issues that require manual fixes:

        #{issue_description}

        These issues cannot be automatically fixed and require manual intervention.
      MSG
      logger.info("Repository #{repo_name} had cookstyle issues that require manual fixes")
      pr_created, pr_details = @pr_manager.create_pull_request(repo_name, repo_dir, manual_fix_message, true)
      logger.info("Manual fix PR #{pr_created ? 'created' : 'not created'} for #{repo_name}")
      assign_pr_result(pr_created, pr_details, repo_name, 'manual-fix')
    end

    def assign_pr_result(pr_created, pr_details, repo_name, type)
      if pr_created && pr_details
        Thread.current[:pr_details] = {
          repo: repo_name,
          number: pr_details[:number],
          url: pr_details[:html_url],
          title: pr_details[:title],
          type: type
        }
      else
        Thread.current[:pr_error] = {
          repo: repo_name,
          message: "Failed to create #{type} PR",
          type: type
        }
      end
    end

    def build_result_hash(exit_status, commit_sha, total_offenses, parsed_json, processing_time)
      {
        status: exit_status.zero? ? :success : :error,
        commit_sha: commit_sha || '',
        had_issues: total_offenses.positive?,
        output: parsed_json,
        processing_time: processing_time
      }
    end

    def should_skip_repository?(repo_name)
      RepositoryManager.should_skip_repository?(repo_name, @config[:include_repos], @config[:exclude_repos])
    end

    def retry_operation(repo_url, processed_count, total_repos)
      return false unless @config[:retry_count].positive?

      repo_name = File.basename(repo_url, '.git')
      logger.info("Retrying repository #{repo_name} (#{@config[:retry_count]} attempts remaining)")
      perform_retry(repo_url, processed_count, total_repos, repo_name)
    end

    def perform_retry(repo_url, processed_count, total_repos, repo_name)
      retry_config = @config.dup
      retry_config[:retry_count] -= 1
      original_config = @config
      @config = retry_config
      @cache_manager.clear_repo(repo_name) if @config[:use_cache]
      sleep(1)
      result = process_repository(repo_url, processed_count, total_repos)
      @config = original_config
      %i[success skipped].include?(result)
    end
  end
  # rubocop:enable Metrics/ClassLength
end
