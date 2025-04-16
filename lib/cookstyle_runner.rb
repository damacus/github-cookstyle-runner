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

require 'English'
require 'logger'
require 'fileutils'
require 'octokit'
require 'json'
require 'open3'
require 'parallel'

# Load our library modules
require_relative 'cookstyle_runner/git_operations'
require_relative 'cookstyle_runner/github_api'
require_relative 'cookstyle_runner/repository_manager'
require_relative 'cookstyle_runner/cookstyle_operations'
require_relative 'cookstyle_runner/config_manager'

# Load our application classes
require_relative 'cookstyle_runner/cache_manager'
require_relative 'cookstyle_runner/github_pr_manager'

# Main application class for GitHub Cookstyle Runner
module CookstyleRunner
  class Application
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

      # Instantiate a single RepositoryProcessor for all threads
      repo_processor = RepositoryProcessor.new(
        config: @config,
        logger: logger,
        cache_manager: @cache_manager,
        pr_manager: @pr_manager
      )

      # Process repositories in parallel using the Parallel gem
      Parallel.each(repositories, in_threads: thread_count) do |repo_url|
        # Thread-safe counter increment
        current_count = mutex.synchronize do
          processed_count += 1
          processed_count
        end

        # Delegate all per-repository processing to RepositoryProcessor
        result = repo_processor.process_repository(repo_url, current_count, total_repos)

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

      summary = <<~SUMMARY
        --- Summary ---
        Processed #{processed_count} repositories.
        Found issues in #{issues_count} repositories.
        #{error_count.positive? ? "Encountered errors in #{error_count} repositories." : ''}
        #{skipped_count.positive? ? "Skipped #{skipped_count} repositories." : ''}
      SUMMARY
      logger.info(summary.strip)

      # Print cache statistics if caching is enabled
      if @config[:use_cache]
        stats = @cache_manager.runtime_stats
        logger.info(<<~STATS)
          --- Cache Statistics ---
          Cache hits: #{stats['cache_hits']}
          Cache misses: #{stats['cache_misses']}
          Cache hit rate: #{stats['cache_hit_rate']}%
          Estimated time saved: #{stats['estimated_time_saved']} seconds
          Total runtime: #{stats['runtime']} seconds
        STATS
      end

      issues_count.positive? ? logger.warn("#{issues_count} repositories had cookstyle issues.") : logger.info('All repositories passed cookstyle checks!')

      # Report created PRs
      if @created_prs.any?
        pr_report = ["--- Created Pull Requests (#{@created_prs.size}) ---"]
        @created_prs.each do |pr|
          pr_report << <<~PR_ENTRY
            Repository: #{pr[:repo]}
            PR ##{pr[:number]}: #{pr[:title]}
            Type: #{pr[:type]}
            URL: #{pr[:url]}
          PR_ENTRY
        end
        logger.info(pr_report.join("\n").strip)
      else
        logger.info('No pull requests were created during this run.')
      end

      # Report PR errors if any
      if @pr_errors.any?
        pr_error_report = ["--- Pull Request Creation Errors (#{@pr_errors.size}) ---"]
        @pr_errors.each do |error|
          pr_error_report << <<~PR_ERROR_ENTRY
            Repository: #{error[:repo]}
            Error: #{error[:message]}
            Type: #{error[:type]}
          PR_ERROR_ENTRY
        end
        logger.info(pr_error_report.join("\n").strip)
      end

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
      config_lines = []
      config_lines << <<~CONFIGURATION
        --- Configuration ---
        Destination Repo Owner: #{@config[:owner]}
        Destination Repo Topics: #{@config[:topics].join(', ')}
        Branch Name: #{@config[:branch_name]}
        PR Title: #{@config[:pr_title]}
        PR Labels: #{@config[:pr_labels].empty? ? 'None' : @config[:pr_labels].join(', ')}
        Git Author: #{@config[:git_name]} <#{@config[:git_email]}>
        Default Branch: #{@config[:default_branch]}
        Cache Dir: #{@config[:cache_dir]}
        Cache Enabled: #{@config[:use_cache] ? 'Yes' : 'No'}
        Cache Max Age: #{@config[:cache_max_age] / (24 * 60 * 60)} days
        Force Refresh: #{@config[:force_refresh] ? 'Yes' : 'No'}
        Retry Count: #{@config[:retry_count]}
        Changelog Location: #{@config[:changelog_location]}
        Changelog Marker: #{@config[:changelog_marker]}
        Manage Changelog: #{@config[:manage_changelog] ? 'Yes' : 'No'}
        Excluding Repos: #{@config[:exclude_repos]}
        Force Refresh Repos: #{@config[:force_refresh_repos]}
        Include Only Repos: #{@config[:include_repos]}
        Filter Repos: #{@config[:filter_repos]}
        Create Manual Fix PRs: #{@config[:create_manual_fix_prs] ? 'Yes' : 'No'}
        ---------------------
      CONFIGURATION

      logger.info(config_lines.join("\n"))
    end

    # Configure git for PR creation
    def setup_git_config
      GitOperations.setup_git_config(@config[:git_name], @config[:git_email], logger)
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
                      @config[:force_refresh_repos]&.include?(repo_name)

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
      if @config[:use_cache] && result.zero?
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
      return false unless @config[:retry_count].positive?

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

    def create_cookstyle_branch(repo_name)
      logger.info("Creating branch #{@config[:branch_name]} for #{repo_name}")
      system("git checkout -b #{@config[:branch_name]}")
      $CHILD_STATUS.success?
    rescue StandardError => e
      logger.error("Error creating branch: #{e.message}")
      false
    end

    # Cookstyle checking is now handled by RepositoryProcessor.
    # This method has been removed as part of codebase refactoring.

    # Cookstyle auto-correction is now handled by RepositoryProcessor.
    # This method has been removed as part of codebase refactoring.

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

      $CHILD_STATUS.success?
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
end