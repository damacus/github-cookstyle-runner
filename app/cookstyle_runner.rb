#!/usr/bin/env ruby
# frozen_string_literal: true

# =============================================================================
# GitHub Cookstyle Runner - Main Application
# =============================================================================
#
# This is the main entry point for the GitHub Cookstyle Runner application.
# It orchestrates the entire workflow of finding repositories, running
# cookstyle checks, applying fixes, and creating pull requests.
#
# Required environment variables:
#   - GITHUB_TOKEN: Authentication token for GitHub API
#   - GCR_DESTINATION_REPO_OWNER: Target GitHub organization/user
#   - GCR_MANAGE_CHANGELOG: Whether to update changelog (0 or 1)
#
# Optional environment variables:
#   - GCR_DESTINATION_REPO_TOPICS: Repository topics to filter by (comma-separated)
#   - GCR_BRANCH_NAME: Branch name for cookstyle fixes (default: "cookstyle-fixes")
#   - GCR_PULL_REQUEST_TITLE: Title for pull requests (default: "Automated PR: Cookstyle Changes")
#   - GCR_CHANGELOG_LOCATION: Path to changelog file (default: "CHANGELOG.md")
#   - GCR_CHANGELOG_MARKER: Marker in changelog for adding entries (default: "## Unreleased")
#   - GCR_DEBUG_MODE: Enable debug logging (default: 0)
#

require 'logger'
require 'fileutils'
require 'octokit'
require 'json'
require 'open3'
require 'parallel'

# Load our library modules
require_relative '../lib/git_operations'
require_relative '../lib/github_api'
require_relative '../lib/repository_manager'
require_relative '../lib/cookstyle_operations'
require_relative '../lib/config_manager'

# Load our application classes
require_relative 'cache_manager'
require_relative 'github_pr_manager'

# Main application class for GitHub Cookstyle Runner
class CookstyleRunner
  attr_reader :logger

  def initialize
    # Use ConfigManager to set up logger and load configuration
    @logger = ConfigManager.setup_logger(ENV['GCR_DEBUG_MODE'] == '1')
    @config = ConfigManager.load_config(@logger)

    # Set up Git configuration
    setup_git_config

    # Set up cache directory and cache manager
    ConfigManager.setup_cache_directory(@config[:cache_dir], @logger)
    setup_cache_manager

    # Set up PR manager
    setup_pr_manager

    # Initialize tracking arrays
    @created_prs = [] # Track created PRs
    @pr_errors = []   # Track PR creation errors
  end

  def run
    # Use the GitHubAPI module to fetch repositories
    repositories = GitHubAPI.fetch_repositories(
      @pr_manager.github_client,
      @config[:owner],
      @config[:topics],
      logger
    )

    if repositories.empty?
      logger.warn('No repositories found matching the criteria. Exiting.')
      return 0
    end

    # Apply repository filtering if specified using the RepositoryManager module
    if @config[:filter_repos] && !@config[:filter_repos].empty?
      filtered_repos = RepositoryManager.filter_repositories(repositories, @config[:filter_repos], logger)
      logger.info("Filtered from #{repositories.length} to #{filtered_repos.length} repositories.")
      repositories = filtered_repos
    end

    logger.info("Found #{repositories.length} repositories.")

    # Process repositories in parallel
    total_repos = repositories.length
    thread_count = [@config[:thread_count], total_repos].min
    logger.info("Processing #{total_repos} repositories using #{thread_count} threads")

    # Use mutex to safely update counters from multiple threads
    mutex = Mutex.new
    issues_count = 0
    error_count = 0
    skipped_count = 0
    processed_count = 0
    pr_count = 0

    # Process repositories in parallel using the Parallel gem
    Parallel.each(repositories, in_threads: thread_count) do |repo_url|
      # Thread-safe counter increment
      current_count = mutex.synchronize do
        processed_count += 1
        processed_count
      end

      # Process the repository
      result = process_repository(repo_url, current_count, total_repos)

      # Thread-safe update of counters
      mutex.synchronize do
        case result
        when :issues_found
          issues_count += 1
        when :error
          error_count += 1
        when :skipped
          skipped_count += 1
        end

        # Add PR details if available
        if Thread.current[:pr_details]
          @created_prs << Thread.current[:pr_details]
          Thread.current[:pr_details] = nil
          pr_count += 1
        end

        # Add PR error if available
        if Thread.current[:pr_error]
          @pr_errors << Thread.current[:pr_error]
          Thread.current[:pr_error] = nil
        end
      end
    end

    # Report results
    logger.info('--- Summary ---')
    logger.info("Processed #{processed_count} repositories.")
    logger.info("Found issues in #{issues_count} repositories.")
    logger.info("Encountered errors in #{error_count} repositories.") if error_count > 0
    logger.info("Skipped #{skipped_count} repositories.") if skipped_count > 0

    # Print cache statistics if caching is enabled
    if @config[:use_cache]
      stats = @cache_manager.runtime_stats
      logger.info('--- Cache Statistics ---')
      logger.info("Cache hits: #{stats['cache_hits']}")
      logger.info("Cache misses: #{stats['cache_misses']}")
      logger.info("Cache hit rate: #{stats['cache_hit_rate']}%")
      logger.info("Estimated time saved: #{stats['estimated_time_saved']} seconds")
      logger.info("Total runtime: #{stats['runtime']} seconds")
    end

    if issues_count > 0
      logger.warn("#{issues_count} repositories had cookstyle issues.")
    else
      logger.info('All repositories passed cookstyle checks!')
    end

    # Report created PRs
    if @created_prs.any?
      logger.info("--- Created Pull Requests (#{@created_prs.size}) ---")
      @created_prs.each do |pr|
        logger.info("Repository: #{pr[:repo]}")
        logger.info("PR ##{pr[:number]}: #{pr[:title]}")
        logger.info("Type: #{pr[:type]}")
        logger.info("URL: #{pr[:url]}")
        logger.info('')
      end
    else
      logger.info('No pull requests were created during this run.')
    end

    # Report PR errors if any
    if @pr_errors.any?
      logger.info("--- Pull Request Creation Errors (#{@pr_errors.size}) ---")
      @pr_errors.each do |error|
        logger.info("Repository: #{error[:repo]}")
        logger.info("Error: #{error[:message]}")
        logger.info("Type: #{error[:type]}")
        logger.info('')
      end
    end

    # Return success code
    0
  end

  private

  def setup_logger
    @logger = Logger.new($stdout)
    @logger.level = ENV['GCR_DEBUG_MODE'] == '1' ? Logger::DEBUG : Logger::INFO
    @logger.formatter = proc do |severity, datetime, _progname, msg|
      "[#{datetime.strftime('%Y-%m-%dT%H:%M:%SZ')}] #{severity}: #{msg}\n"
    end
  end

  def validate_environment
    required_vars = %w[GITHUB_TOKEN GCR_DESTINATION_REPO_OWNER GCR_MANAGE_CHANGELOG]
    missing_vars = required_vars.select { |var| ENV[var].nil? || ENV[var].empty? }

    return if missing_vars.empty?

    missing_vars.each { |var| logger.error("Required environment variable #{var} is not set") }
    exit 1
  end

  def setup_configuration
    # Set defaults for optional variables
    @config = {
      owner: ENV['GCR_DESTINATION_REPO_OWNER'],
      topics: ENV['GCR_DESTINATION_REPO_TOPICS']&.split(',')&.map(&:strip) || ['chef-cookbook'],
      branch_name: ENV['GCR_BRANCH_NAME'] || 'cookstyle-fixes',
      pr_title: ENV['GCR_PULL_REQUEST_TITLE'] || 'Automated PR: Cookstyle Changes',
      default_branch: ENV['GCR_DEFAULT_GIT_BRANCH'] || 'main',
      manage_changelog: ENV['GCR_MANAGE_CHANGELOG'] == '1',
      changelog_location: ENV['GCR_CHANGELOG_LOCATION'] || 'CHANGELOG.md',
      changelog_marker: ENV['GCR_CHANGELOG_MARKER'] || '## Unreleased',
      git_name: ENV['GCR_GIT_NAME'] || 'Cookstyle Bot',
      git_email: ENV['GCR_GIT_EMAIL'] || 'cookstyle@example.com',
      pr_labels: ENV['GCR_PULL_REQUEST_LABELS']&.split(',')&.map(&:strip) || [],
      cache_dir: ENV['CACHE_DIR'] || '/tmp/cookstyle-runner',
      thread_count: ENV['GCR_THREAD_COUNT']&.to_i || 5,
      use_cache: ENV['GCR_USE_CACHE'] != '0',
      cache_max_age: ENV['GCR_CACHE_MAX_AGE']&.to_i || (7 * 24 * 60 * 60), # 7 days in seconds
      force_refresh: ENV['GCR_FORCE_REFRESH'] == '1',
      force_refresh_repos: ENV['GCR_FORCE_REFRESH_REPOS']&.split(',')&.map(&:strip),
      include_repos: ENV['GCR_INCLUDE_REPOS']&.split(',')&.map(&:strip),
      exclude_repos: ENV['GCR_EXCLUDE_REPOS']&.split(',')&.map(&:strip),
      retry_count: ENV['GCR_RETRY_COUNT']&.to_i || 3,
      filter_repos: ENV['GCR_FILTER_REPOS']&.split(',')&.map(&:strip),
      create_manual_fix_prs: ENV['GCR_CREATE_MANUAL_FIX_PRS'] == '1'
    }

    # Log configuration
    logger.info('--- Configuration ---')
    logger.info("Destination Repo Owner: #{@config[:owner]}")
    logger.info("Destination Repo Topics: #{@config[:topics].join(', ')}")
    logger.info("Branch Name: #{@config[:branch_name]}")
    logger.info("PR Title: #{@config[:pr_title]}")
    logger.info("PR Labels: #{@config[:pr_labels].empty? ? 'None' : @config[:pr_labels].join(', ')}")
    logger.info("Git Author: #{@config[:git_name]} <#{@config[:git_email]}>")
    logger.info("Default Branch: #{@config[:default_branch]}")
    logger.info("Cache Dir: #{@config[:cache_dir]}")
    logger.info("Cache Enabled: #{@config[:use_cache] ? 'Yes' : 'No'}")
    logger.info("Cache Max Age: #{@config[:cache_max_age] / (24 * 60 * 60)} days")
    logger.info("Force Refresh: #{@config[:force_refresh] ? 'Yes' : 'No'}")
    logger.info("Retry Count: #{@config[:retry_count]}")

    if @config[:force_refresh_repos]&.any?
      logger.info("Force Refresh Repos: #{@config[:force_refresh_repos].join(', ')}")
    end

    logger.info("Include Only Repos: #{@config[:include_repos].join(', ')}") if @config[:include_repos]&.any?

    logger.info("Exclude Repos: #{@config[:exclude_repos].join(', ')}") if @config[:exclude_repos]&.any?

    logger.info("Filter Repos: #{@config[:filter_repos].join(', ')}") if @config[:filter_repos]&.any?

    logger.info("Manage Changelog: #{@config[:manage_changelog] ? 'Yes' : 'No'}")
    logger.info("Changelog Location: #{@config[:changelog_location]}")
    logger.info("Changelog Marker: #{@config[:changelog_marker]}")
    logger.info('---------------------')
  end

  def setup_git_config
    # Configure git for PR creation
    system("git config --global user.name \"#{@config[:git_name]}\"")
    system("git config --global user.email \"#{@config[:git_email]}\"")
  end

  def setup_cache_directory
    FileUtils.mkdir_p(@config[:cache_dir])
  end

  # Initialize the cache manager
  def setup_cache_manager
    @cache_manager = CacheManager.new(@config[:cache_dir], logger)
    logger.info("Cache initialized with #{@cache_manager.cache_stats['total_repositories']} repositories")
    logger.info("Last cache update: #{@cache_manager.cache_stats['last_updated']}")
  end

  # Initialize the PR manager
  def setup_pr_manager
    @pr_manager = GitHubPRManager.new(@config, logger)
  end

  def github_client
    @github_client ||= Octokit::Client.new(
      access_token: ENV['GITHUB_TOKEN'],
      auto_paginate: true
    )
  end

  def fetch_repositories
    logger.info("Fetching repositories for organization: #{@config[:owner]}")

    begin
      # Build the search query
      query = "org:#{@config[:owner]}"
      @config[:topics].each { |topic| query += " topic:#{topic}" unless topic.empty? }

      logger.debug("Search query: #{query}")

      # Execute the search
      results = github_client.search_repositories(query)

      logger.info("Found #{results.total_count} repositories")

      # Extract clone URLs
      results.items.map(&:clone_url)
    rescue Octokit::Error => e
      logger.error("GitHub API error: #{e.message}")
      logger.debug(e.backtrace.join("\n"))
      []
    rescue StandardError => e
      logger.error("Error fetching repositories: #{e.message}")
      logger.debug(e.backtrace.join("\n"))
      []
    end
  end

  # Filter repositories based on specified criteria
  # @param repositories [Array<String>] List of repository URLs
  # @param filter_repos [Array<String>] List of repository names to filter by
  # @return [Array<String>] Filtered list of repository URLs
  def filter_repositories(repositories, filter_repos)
    # Use the RepositoryManager module to filter repositories
    RepositoryManager.filter_repositories(repositories, filter_repos, logger)
  end

  def process_repository(repo_url, processed_count, total_repos)
    # Extract repo name from URL
    repo_name = File.basename(repo_url, '.git')

    # Create a thread-safe working directory with a unique ID for this thread
    thread_id = Thread.current.object_id
    thread_dir = File.join(@config[:cache_dir], "thread_#{thread_id}")
    repo_dir = File.join(thread_dir, repo_name)

    # Ensure thread directory exists
    FileUtils.mkdir_p(thread_dir) unless Dir.exist?(thread_dir)

    logger.info("[#{processed_count}/#{total_repos}] Processing: #{repo_name}")

    # Check if we should skip this repository based on inclusion/exclusion lists
    if RepositoryManager.should_skip_repository?(repo_name, @config[:include_repos], @config[:exclude_repos])
      logger.info("Skipping repository #{repo_name} (excluded)")
      return :skipped
    end

    # Check if we should force refresh this repository
    force_refresh = @config[:force_refresh] ||
                    (@config[:force_refresh_repos] && @config[:force_refresh_repos].include?(repo_name))

    # Check if repository exists locally
    unless Dir.exist?(repo_dir)
      logger.info("Repository #{repo_name} not found locally, cloning...")
      clone_result = system("git clone #{repo_url} #{repo_dir} 2>/dev/null")
      unless clone_result
        logger.error("Failed to clone repository #{repo_name}")
        return retry_operation(repo_url, processed_count, total_repos) ? :success : :error
      end
    end

    # Get the latest commit SHA before any updates
    current_sha = get_latest_commit_sha(repo_dir)
    if current_sha.nil?
      logger.error("Failed to get commit SHA for repository #{repo_name}")
      return retry_operation(repo_url, processed_count, total_repos) ? :success : :error
    end

    # Check if the repository is up-to-date in the cache
    start_time = Time.now.utc
    if !force_refresh && @config[:use_cache] && @cache_manager.up_to_date?(repo_name, current_sha,
                                                                           @config[:cache_max_age],
                                                                           @cache_manager.average_processing_time)
      cached_result = @cache_manager.get_result(repo_name)
      logger.info("Using cached result for #{repo_name} (SHA: #{current_sha})")
      logger.info(cached_result['last_result'])
      return cached_result['had_issues'] ? :issues_found : :success
    end

    # Repository needs processing - use process isolation to avoid threading issues
    result, output, had_issues, = run_in_subprocess(repo_url, repo_dir, repo_name)
    processing_time = Time.now.utc - start_time

    # Clean up repository directory after processing using the RepositoryManager module
    RepositoryManager.cleanup_repo_dir(repo_dir)

    # Update cache with the result if successful
    if @config[:use_cache] && result == 0
      @cache_manager.update(repo_name, current_sha, had_issues, output, processing_time)
    end

    # Return appropriate status
    if result != 0
      return retry_operation(repo_url, processed_count, total_repos) ? :success : :error
    end

    had_issues ? :issues_found : :success
  rescue StandardError => e
    logger.error("Error processing repository #{repo_name}: #{e.message}")
    logger.debug(e.backtrace.join("\n"))
    retry_operation(repo_url, processed_count, total_repos) ? :success : :error
  end

  # Retry a failed operation if retries are enabled
  # @param repo_url [String] Repository URL
  # @param processed_count [Integer] Current repository count
  # @param total_repos [Integer] Total repositories count
  # @return [Boolean] True if retry was successful, false otherwise
  def retry_operation(repo_url, processed_count, total_repos)
    return false unless @config[:retry_count] > 0

    repo_name = File.basename(repo_url, '.git')
    logger.info("Retrying repository #{repo_name} (#{@config[:retry_count]} attempts remaining)")

    # Create a new configuration with one less retry
    retry_config = @config.dup
    retry_config[:retry_count] -= 1

    # Store the original config, set the new one, process, then restore
    original_config = @config
    @config = retry_config

    # Clear the cache for this repository if it exists
    @cache_manager.clear_repo(repo_name) if @config[:use_cache]

    # Sleep before retry to avoid hammering the system
    sleep(1)

    # Retry the operation
    result = process_repository(repo_url, processed_count, total_repos)

    # Restore the original config
    @config = original_config

    # Return true if the retry was successful
    %i[success skipped].include?(result)
  end

  # Check if a repository should be skipped based on inclusion/exclusion lists
  # @param repo_name [String] Repository name
  # @return [Boolean] True if the repository should be skipped
  def should_skip_repository?(repo_name)
    # Use the RepositoryManager module to check if a repository should be skipped
    RepositoryManager.should_skip_repository?(repo_name, @config[:include_repos], @config[:exclude_repos])
  end

  # Get the latest commit SHA for a repository
  def get_latest_commit_sha(repo_dir)
    stdout, _stderr, status = Open3.capture3("cd #{repo_dir} && git rev-parse HEAD")
    return nil unless status.success?

    stdout.strip
  end

  # Run repository processing in a separate process to avoid directory conflicts
  def run_in_subprocess(repo_url, repo_dir, repo_name)
    # Create unique temporary files for this repository
    thread_id = Thread.current.object_id
    cookstyle_output_file = "/tmp/cookstyle_output_#{repo_name}_#{thread_id}.txt"
    cookstyle_fixes_file = "/tmp/cookstyle_fixes_#{repo_name}_#{thread_id}.txt"
    changes_file = "/tmp/changes_#{repo_name}_#{thread_id}.txt"

    # Create or clean the repository directory
    FileUtils.mkdir_p(repo_dir) unless Dir.exist?(repo_dir)

    # Use Open3 to capture output from the subprocess
    stdout, stderr, status = Open3.capture3(
      # Clone the repository if it doesn't exist or update it if it does
      "if [ ! -d '#{repo_dir}/.git' ]; then " +
      "  git clone #{repo_url} #{repo_dir} 2>/dev/null; " +
      'else ' +
      "  (cd #{repo_dir} && git fetch origin && git reset --hard origin/#{@config[:default_branch]} && git clean -fdx); " +
      'fi && ' +
      "cd #{repo_dir} && " +
      # First run cookstyle without auto-correction to check for issues
      'cookstyle_result=$(cookstyle -D 2>&1); cookstyle_status=$?; ' +
      "echo \"Cookstyle exit status: $cookstyle_status\" > #{cookstyle_output_file}; " +
      "echo \"$cookstyle_result\" >> #{cookstyle_output_file}; " +
      'if [ $cookstyle_status -eq 0 ]; then ' +
      "  echo 'No issues found'; " +
      '  had_issues=false; ' +
      'else ' +
      '  echo "Cookstyle found issues:"; ' +
      '  echo "$cookstyle_result"; ' +
      '  had_issues=true; ' +
      # Run cookstyle with auto-corrections
      "  cookstyle -a > #{cookstyle_fixes_file} 2>&1; " +
      "  cat #{cookstyle_fixes_file}; " +
      # Check for any changes (including permission changes) - use git diff to catch mode changes
      "  git diff --name-status > #{changes_file}; " +
      "  git status --porcelain >> #{changes_file}; " +
      "  if [ -s #{changes_file} ]; then " +
      '    echo "Changes detected after cookstyle auto-correction:"; ' +
      "    cat #{changes_file}; " +
      '    has_changes=true; ' +
      '  else ' +
      '    echo "No changes detected after cookstyle auto-correction"; ' +
      '    has_changes=false; ' +
      '  fi; ' +
      'fi; ' +
      'echo $had_issues; ' + # Output whether the repository had issues
      'echo $has_changes' # Output whether there were changes after auto-correction
    )

    # Log the output
    logger.debug("Subprocess output: #{stdout}")
    logger.debug("Subprocess errors: #{stderr}") unless stderr.empty?

    # Check if the repository had issues by parsing the output
    had_issues = stdout.include?('had_issues=true') || stdout.include?('Cookstyle found issues')

    # Check if there were changes after auto-correction
    has_changes = stdout.include?('has_changes=true') || stdout.include?('Changes detected after cookstyle auto-correction')

    # Read the cookstyle output files if they exist
    cookstyle_output = File.exist?(cookstyle_output_file) ? File.read(cookstyle_output_file) : ''
    cookstyle_fixes = File.exist?(cookstyle_fixes_file) ? File.read(cookstyle_fixes_file) : ''
    changes = File.exist?(changes_file) ? File.read(changes_file) : ''

    # Combine all outputs for the PR description
    combined_output = "Cookstyle Output:\n#{cookstyle_output}\n\nAuto-correction Output:\n#{cookstyle_fixes}\n\nChanges Made:\n#{changes}"

    # If there were issues and changes, create a PR using our PR manager
    if had_issues && has_changes && status.exitstatus == 0
      # Create a pull request
      pr_created, pr_details = @pr_manager.create_pull_request(repo_name, repo_dir, combined_output)
      logger.info("Pull request #{pr_created ? 'created' : 'not created'} for #{repo_name}")

      # Track the created PR or error
      if pr_created && pr_details
        # Thread-safe update of PR list
        Thread.current[:pr_details] = {
          repo: repo_name,
          number: pr_details[:number],
          url: pr_details[:html_url],
          title: pr_details[:title],
          type: 'auto-fix'
        }
      else
        # Track the error
        Thread.current[:pr_error] = {
          repo: repo_name,
          message: 'Failed to create auto-fix PR',
          type: 'auto-fix'
        }
      end
    elsif had_issues && !has_changes
      # Some issues can't be auto-fixed, so we should create a PR with manual instructions
      manual_fix_message = "Cookstyle found issues that require manual fixes:\n\n#{cookstyle_output}\n\nThese issues cannot be automatically fixed and require manual intervention."
      logger.info("Repository #{repo_name} had cookstyle issues that require manual fixes")

      # Create a PR with instructions for manual fixes
      if @config[:create_manual_fix_prs]
        pr_created, pr_details = @pr_manager.create_pull_request(repo_name, repo_dir, manual_fix_message, true)
        logger.info("Manual fix PR #{pr_created ? 'created' : 'not created'} for #{repo_name}")

        # Track the created PR or error
        if pr_created && pr_details
          # Thread-safe update of PR list
          Thread.current[:pr_details] = {
            repo: repo_name,
            number: pr_details[:number],
            url: pr_details[:html_url],
            title: pr_details[:title],
            type: 'manual-fix'
          }
        else
          # Track the error
          Thread.current[:pr_error] = {
            repo: repo_name,
            message: 'Failed to create manual-fix PR',
            type: 'manual-fix'
          }
        end
      end
    end

    # Clean up temporary files
    [cookstyle_output_file, cookstyle_fixes_file, changes_file].each do |file|
      File.delete(file) if File.exist?(file)
    end

    # Return the exit status, output, and whether the repository had issues
    [status.exitstatus, stdout, had_issues]
  end

  def clone_or_update_repo(repo_url, repo_dir)
    if Dir.exist?(File.join(repo_dir, '.git'))
      logger.info("Updating existing repository: #{repo_dir}")
      Dir.chdir(repo_dir) do
        # Fetch latest changes and reset to origin/main
        system("git fetch origin && git reset --hard origin/#{@config[:default_branch]} && git clean -fdx")
      end
    else
      logger.info("Cloning repository: #{repo_url}")
      system("git clone #{repo_url} #{repo_dir}")
    end

    $?.success?
  rescue StandardError => e
    logger.error("Error cloning/updating repository: #{e.message}")
    false
  end

  def create_cookstyle_branch(repo_name)
    logger.info("Creating branch #{@config[:branch_name]} for #{repo_name}")
    system("git checkout -b #{@config[:branch_name]}")
    $?.success?
  rescue StandardError => e
    logger.error("Error creating branch: #{e.message}")
    false
  end

  def run_cookstyle_check(repo_name)
    logger.info("Running cookstyle on #{repo_name}...")

    stdout, stderr, status = Open3.capture3('cookstyle')

    if status.success?
      logger.debug("Cookstyle output: #{stdout}")
      true
    else
      logger.debug("Cookstyle errors: #{stderr}")
      false
    end
  rescue StandardError => e
    logger.error("Error running cookstyle check: #{e.message}")
    false
  end

  def run_cookstyle_autocorrect(repo_name)
    logger.info("Running cookstyle auto-correct on #{repo_name}...")

    stdout, stderr, status = Open3.capture3('cookstyle -a')

    if status.success?
      # Check if any changes were made
      stdout, _stderr, = Open3.capture3('git diff --name-only')
      if stdout.strip.empty?
        logger.info('No changes after auto-correction')
        :no_changes
      else
        logger.info("Auto-correct applied successfully to #{repo_name}")
        logger.debug("Changed files: #{stdout}")
        :success
      end
    else
      logger.error("Auto-correct failed: #{stderr}")
      :failure
    end
  rescue StandardError => e
    logger.error("Error running cookstyle auto-correct: #{e.message}")
    :failure
  end

  def update_changelog
    changelog_file = @config[:changelog_location]
    marker = @config[:changelog_marker]

    return unless File.exist?(changelog_file)

    logger.info("Updating changelog at #{changelog_file}")

    content = File.read(changelog_file)
    today = Time.now.strftime('%Y-%m-%d')

    if content.include?(marker)
      new_content = content.gsub(marker, "#{marker}\n- Cookstyle auto-corrections applied on #{today}")
      File.write(changelog_file, new_content)
      logger.info('Changelog updated successfully')
    else
      logger.warn("Changelog marker '#{marker}' not found in #{changelog_file}")
    end
  rescue StandardError => e
    logger.error("Error updating changelog: #{e.message}")
  end

  def commit_and_push_changes(repo_name)
    logger.info("Committing and pushing changes for #{repo_name}")

    # Add all changes
    system('git add .')

    # Commit changes
    commit_message = "#{@config[:pr_title]}\n\nSigned-off-by: #{@config[:git_name]} <#{@config[:git_email]}>"
    system("git commit -m \"#{commit_message}\"")

    # Push to remote
    system("git push -u origin #{@config[:branch_name]}")

    $?.success?
  rescue StandardError => e
    logger.error("Error committing and pushing changes: #{e.message}")
    false
  end

  def create_pull_request(repo_name)
    repo_full_name = "#{@config[:owner]}/#{repo_name}"
    logger.info("Creating pull request for #{repo_full_name}")

    begin
      # Create the pull request
      pr = github_client.create_pull_request(
        repo_full_name,
        @config[:default_branch],
        @config[:branch_name],
        @config[:pr_title],
        'This PR applies automatic Cookstyle fixes using the [GitHub Cookstyle Runner](https://github.com/damacus/github-cookstyle-runner).'
      )

      logger.info("Pull request created: #{pr.html_url}")

      # Add labels if specified
      unless @config[:pr_labels].empty?
        github_client.add_labels_to_an_issue(repo_full_name, pr.number, @config[:pr_labels])
        logger.info("Added labels to PR: #{@config[:pr_labels].join(', ')}")
      end

      true
    rescue Octokit::Error => e
      logger.error("GitHub API error creating PR: #{e.message}")
      false
    rescue StandardError => e
      logger.error("Error creating pull request: #{e.message}")
      false
    end
  end
end

# Run the application if this file is executed directly
if __FILE__ == $PROGRAM_NAME
  runner = CookstyleRunner.new
  exit runner.run
end
