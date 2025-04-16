# frozen_string_literal: true

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
      return :error unless clone_or_update_repo(repo_url, repo_dir)

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

    def clone_or_update_repo(repo_url, repo_dir)
      context = GitOperations::RepoContext.new(repo_name: File.basename(repo_url, '.git'),
                                              github_token: @config[:github_token], owner: @config[:owner], logger: logger)
      GitOperations.clone_or_update_repo(repo_url, repo_dir, @config[:default_branch], context)
    end

    def run_in_subprocess(repo_url, repo_dir, repo_name)
      require 'open3'
      thread_id = Thread.current.object_id
      temp_files = cookstyle_temp_files(repo_name, thread_id)
      start_time = Time.now

      ensure_temp_dirs_exist(temp_files)
      shell_cmd = build_cookstyle_shell_command(repo_url, repo_dir, temp_files)
      stdout, stderr, shell_cmd_status = run_cookstyle_shell(shell_cmd)
      log_subprocess_output(stdout, stderr)
      had_issues, has_changes = parse_cookstyle_flags(stdout)
      outputs = parse_cookstyle_outputs(temp_files)
      handle_cookstyle_pr_creation(had_issues, has_changes, shell_cmd_status, repo_name, repo_dir, outputs)
      commit_sha = fetch_commit_sha(repo_dir)
      cleanup_temp_files(temp_files)
      build_result_hash(shell_cmd_status.exitstatus, commit_sha, had_issues, outputs, Time.now - start_time)
    end

    def ensure_temp_dirs_exist(temp_files)
      FileUtils.mkdir_p(temp_files.values) unless Dir.exist?(temp_files.values)
    end

    def run_cookstyle_shell(shell_cmd)
      Open3.capture3(shell_cmd)
    end

    def log_subprocess_output(stdout, stderr)
      logger.debug("Subprocess output: #{stdout}")
      logger.debug("Subprocess errors: #{stderr}") unless stderr.empty?
    end

    def parse_cookstyle_flags(stdout)
      had_issues_flag = stdout.include?('had_issues=true')
      cookstyle_found_issues_flag = stdout.include?('Cookstyle found issues')
      had_issues = had_issues_flag || cookstyle_found_issues_flag

      has_changes_flag = stdout.include?('has_changes=true')
      changes_detected_flag = stdout.include?('Changes detected after cookstyle auto-correction')
      has_changes = has_changes_flag || changes_detected_flag

      [had_issues, has_changes]
    end

    def parse_cookstyle_outputs(temp_files)
      {
        cookstyle: File.exist?(temp_files[:cookstyle_output]) ? File.read(temp_files[:cookstyle_output]) : '',
        fixes: File.exist?(temp_files[:cookstyle_fixes]) ? File.read(temp_files[:cookstyle_fixes]) : '',
        changes: File.exist?(temp_files[:changes]) ? File.read(temp_files[:changes]) : ''
      }
    end

    def fetch_commit_sha(repo_dir)
      sha = nil
      Dir.chdir(repo_dir) do
        sha_out, _sha_err, sha_status = Open3.capture3('git rev-parse HEAD')
        sha = sha_out.strip if sha_status.success?
      end
      sha
    end

    def cleanup_temp_files(temp_files)
      temp_files.each_value { |file| File.delete(file) if File.exist?(file) }
    end

    def build_result_hash(shell_cmd_exit_status, commit_sha, had_issues, outputs, processing_time)
      {
        status: shell_cmd_exit_status.zero? ? :success : :error,
        commit_sha: commit_sha || '',
        had_issues: had_issues,
        output: format_combined_output(outputs),
        processing_time: processing_time
      }
    end

    def format_combined_output(outputs)
      <<~MSG
        Cookstyle Output:
        #{outputs[:cookstyle]}

        Auto-correction Output:
        #{outputs[:fixes]}

        Changes Made:
        #{outputs[:changes]}
      MSG
    end

    def cookstyle_temp_files(repo_name, thread_id)
      {
        cookstyle_output: "/tmp/cookstyle_output_#{repo_name}_#{thread_id}.txt",
        cookstyle_fixes: "/tmp/cookstyle_fixes_#{repo_name}_#{thread_id}.txt",
        changes: "/tmp/changes_#{repo_name}_#{thread_id}.txt"
      }
    end

    def handle_cookstyle_pr_creation(had_issues, has_changes, shell_cmd_exit_status, repo_name, repo_dir, outputs)
      return unless had_issues

      if auto_fix_applicable?(has_changes, shell_cmd_exit_status)
        pr_created, pr_details = @pr_manager.create_pull_request(repo_name, repo_dir, outputs)
        logger.info("Pull request #{pr_created ? 'created' : 'not created'} for #{repo_name}")
        assign_pr_result(pr_created, pr_details, repo_name, 'auto-fix')
        return
      end
      return unless manual_fix_applicable?(has_changes)

      handle_manual_fix_pr(repo_name, repo_dir, outputs)
    end

    def auto_fix_applicable?(has_changes, shell_cmd_exit_status)
      has_changes && shell_cmd_exit_status.exitstatus.zero?
    end

    def manual_fix_applicable?(has_changes)
      !has_changes && @config[:create_manual_fix_prs]
    end

    # rubocop:disable Metrics/MethodLength
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
    # rubocop:enable Metrics/MethodLength

    def handle_manual_fix_pr(repo_name, repo_dir, outputs)
      manual_fix_message = <<~MSG
        Cookstyle found issues that require manual fixes:

        #{outputs[:cookstyle]}

        These issues cannot be automatically fixed and require manual intervention.
      MSG
      logger.info("Repository #{repo_name} had cookstyle issues that require manual fixes")
      pr_created, pr_details = @pr_manager.create_pull_request(repo_name, repo_dir, manual_fix_message, true)
      logger.info("Manual fix PR #{pr_created ? 'created' : 'not created'} for #{repo_name}")
      assign_pr_result(pr_created, pr_details, repo_name, 'manual-fix')
    end

    def build_cookstyle_shell_command(repo_url, repo_dir, temp_files)
      <<~SHELL
        if [[ ! -d '#{repo_dir}/.git' ]]; then
          git clone #{repo_url} #{repo_dir} 2>/dev/null;
        else
          (cd #{repo_dir} && git fetch origin && git reset --hard origin/#{@config[:default_branch]} && git clean -fdx);
        fi &&
        cd #{repo_dir} &&
        cookstyle_result=$(cookstyle -D 2>&1); cookstyle_status=$?;
        echo "Cookstyle exit status: $cookstyle_status" > #{temp_files[:cookstyle_output]};
        echo "$cookstyle_result" >> #{temp_files[:cookstyle_output]};
        if [ $cookstyle_status -eq 0 ]; then
          echo 'No issues found';
          had_issues=false;
        else
          echo "Cookstyle found issues:";
          echo "$cookstyle_result";
          had_issues=true;
          cookstyle -a > #{temp_files[:cookstyle_fixes]} 2>&1;
          cat #{temp_files[:cookstyle_fixes]};
          git diff --name-status > #{temp_files[:changes]};
          git status --porcelain >> #{temp_files[:changes]};
          if [ -s #{temp_files[:changes]} ]; then
            echo "Changes detected after cookstyle auto-correction:";
            cat #{temp_files[:changes]};
            has_changes=true;
          else
            echo "No changes detected after cookstyle auto-correction";
            has_changes=false;
          fi;
        fi;
        echo $had_issues;
        echo $has_changes
      SHELL
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