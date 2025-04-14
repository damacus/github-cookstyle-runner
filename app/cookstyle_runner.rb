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
require_relative 'cache_manager'

# Main application class for GitHub Cookstyle Runner
class CookstyleRunner
  attr_reader :logger

  def initialize
    setup_logger
    validate_environment
    setup_configuration
    setup_git_config
    setup_cache_directory
    setup_cache_manager
  end

  def run
    repositories = fetch_repositories
    if repositories.empty?
      logger.warn("No repositories found matching the criteria. Exiting.")
      return 0
    end

    logger.info("Found #{repositories.length} repositories.")

    # Process repositories in parallel
    total_repos = repositories.length
    thread_count = [ENV['GCR_THREAD_COUNT']&.to_i || 5, total_repos].min
    logger.info("Processing #{total_repos} repositories using #{thread_count} threads")
    
    # Use mutex to safely update counters from multiple threads
    mutex = Mutex.new
    lint_failed_count = 0
    processed_count = 0
    
    # Process repositories in parallel using the Parallel gem
    Parallel.each(repositories, in_threads: thread_count) do |repo_url|
      # Thread-safe counter increment
      current_count = mutex.synchronize do
        processed_count += 1
        processed_count
      end
      
      # Process the repository
      result = process_repository(repo_url, current_count, total_repos)
      
      # Thread-safe update of failure count
      mutex.synchronize do
        lint_failed_count += 1 unless result
      end
    end

    # Report results
    logger.info("--- Summary ---")
    logger.info("Processed #{processed_count} repositories.")
    logger.info("Found issues in #{lint_failed_count} repositories.")

    if lint_failed_count > 0
      logger.warn("#{lint_failed_count} repositories had cookstyle issues.")
      return 0
    else
      logger.info("All repositories passed cookstyle checks!")
      return 0
    end
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

    unless missing_vars.empty?
      missing_vars.each { |var| logger.error("Required environment variable #{var} is not set") }
      exit 1
    end
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
      cache_max_age: ENV['GCR_CACHE_MAX_AGE']&.to_i || (7 * 24 * 60 * 60) # 7 days in seconds
    }

    # Log configuration
    logger.info("--- Configuration ---")
    logger.info("Destination Repo Owner: #{@config[:owner]}")
    logger.info("Destination Repo Topics: #{@config[:topics].join(', ')}")
    logger.info("Branch Name: #{@config[:branch_name]}")
    logger.info("PR Title: #{@config[:pr_title]}")
    logger.info("PR Labels: #{@config[:pr_labels].empty? ? 'None' : @config[:pr_labels].join(', ')}")
    logger.info("Git Author: #{@config[:git_name]} <#{@config[:git_email]}>")
    logger.info("Default Branch: #{@config[:default_branch]}")
    logger.info("Cache Dir: #{@config[:cache_dir]}")
    logger.info("Manage Changelog: #{@config[:manage_changelog] ? 'Yes' : 'No'}")
    logger.info("Changelog Location: #{@config[:changelog_location]}")
    logger.info("Changelog Marker: #{@config[:changelog_marker]}")
    logger.info("---------------------")
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
    logger.info("Cache initialized with #{@cache_manager.stats['total_repositories']} repositories")
    logger.info("Last cache update: #{@cache_manager.stats['last_updated']}")
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

  def process_repository(repo_url, processed_count, total_repos)
    # Extract repo name from URL
    repo_name = File.basename(repo_url, '.git')
    repo_dir = File.join(@config[:cache_dir], repo_name)

    logger.info("[#{processed_count}/#{total_repos}] Processing: #{repo_name}")
    
    # Check if repository exists locally
    unless Dir.exist?(repo_dir)
      logger.info("Repository #{repo_name} not found locally, cloning...")
      clone_result = system("git clone #{repo_url} #{repo_dir} 2>/dev/null")
      unless clone_result
        logger.error("Failed to clone repository #{repo_name}")
        return false
      end
    end
    
    # Get the latest commit SHA before any updates
    current_sha = get_latest_commit_sha(repo_dir)
    if current_sha.nil?
      logger.error("Failed to get commit SHA for repository #{repo_name}")
      return false
    end
    
    # Check if the repository is up-to-date in the cache
    if @config[:use_cache] && @cache_manager.up_to_date?(repo_name, current_sha)
      cached_result = @cache_manager.get_result(repo_name)
      logger.info("Using cached result for #{repo_name} (SHA: #{current_sha})")
      logger.info(cached_result['last_result'])
      return !cached_result['had_issues']
    end
    
    # Repository needs processing - use process isolation to avoid threading issues
    result, output, had_issues = run_in_subprocess(repo_url, repo_dir, repo_name)
    
    # Update cache with the result
    if @config[:use_cache] && result == 0
      @cache_manager.update(repo_name, current_sha, had_issues, output)
    end
    
    # Return true if the repository was processed successfully and had no issues
    result == 0 && !had_issues
  rescue StandardError => e
    logger.error("Error processing repository #{repo_name}: #{e.message}")
    logger.debug(e.backtrace.join("\n"))
    false
  end
  
  # Get the latest commit SHA for a repository
  def get_latest_commit_sha(repo_dir)
    stdout, _stderr, status = Open3.capture3("cd #{repo_dir} && git rev-parse HEAD")
    return nil unless status.success?
    stdout.strip
  end
  
  # Run repository processing in a separate process to avoid directory conflicts
  def run_in_subprocess(repo_url, repo_dir, repo_name)
    # Use Open3 to capture output from the subprocess
    stdout, stderr, status = Open3.capture3(
      "cd #{@config[:cache_dir]} && " +
      # Update the repository
      "(cd #{repo_dir} && git fetch origin && git reset --hard origin/#{@config[:default_branch]} && git clean -fdx) && " +
      "cd #{repo_dir} && " +
      # Run cookstyle to check for issues
      "cookstyle > /tmp/cookstyle_output.txt 2>&1 && " +
      "if [ $? -eq 0 ]; then " +
      "  echo 'No issues found'; " +
      "  had_issues=false; " +
      "else " +
      # Create branch and apply auto-corrections
      "  had_issues=true; " +
      "  git checkout -b #{@config[:branch_name]} 2>/dev/null || git checkout #{@config[:branch_name]} && " +
      "  cookstyle -a && " +
      "  if [ -n \"$(git status --porcelain)\" ]; then " +
      # Commit and push changes if any
      "    git add . && " +
      "    git config user.name \"#{@config[:git_name]}\" && " +
      "    git config user.email \"#{@config[:git_email]}\" && " +
      "    git commit -m \"#{@config[:pr_title]}\" && " +
      "    git push -u origin #{@config[:branch_name]} -f && " +
      "    echo 'Changes pushed'; " +
      "  else " +
      "    echo 'No changes after auto-correction'; " +
      "  fi; " +
      "fi; " +
      "echo $had_issues" # Output whether the repository had issues
    )
    
    # Log the output
    logger.debug("Subprocess output: #{stdout}")
    logger.debug("Subprocess errors: #{stderr}") unless stderr.empty?
    
    # Check if the repository had issues
    had_issues = stdout.strip.lines.last.strip == 'true'
    
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
      stdout, _stderr, status = Open3.capture3('git diff --name-only')
      if stdout.strip.empty?
        logger.info("No changes after auto-correction")
        return :no_changes
      else
        logger.info("Auto-correct applied successfully to #{repo_name}")
        logger.debug("Changed files: #{stdout}")
        return :success
      end
    else
      logger.error("Auto-correct failed: #{stderr}")
      return :failure
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
      logger.info("Changelog updated successfully")
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
        "This PR applies automatic Cookstyle fixes using the [GitHub Cookstyle Runner](https://github.com/damacus/github-cookstyle-runner)."
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
