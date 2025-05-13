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
require_relative 'changelog_updater'

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

    sig { returns(T::Hash[String, T.untyped]) }
    attr_reader :config

    sig { returns(T.untyped) }
    attr_reader :logger

    sig { returns(T.nilable(Cache)) }
    attr_reader :cache_manager

    sig { returns(T.nilable(T.untyped)) }
    attr_reader :github_client

    sig { returns(T.nilable(T.untyped)) }
    attr_reader :pr_manager

    # Initialize a new repository processor
    # @param config [Hash] Configuration hash
    # @param logger [Logger] Logger instance
    # @param cache_manager [Cache, nil] Cache manager instance (optional)
    # @param github_client [Object, nil] GitHub API client (optional)
    # @param pr_manager [Object, nil] Pull request manager (optional)
    sig do
      params(
        config: T::Hash[String, T.untyped],
        logger: T.untyped,
        cache_manager: T.nilable(Cache),
        github_client: T.nilable(T.untyped),
        pr_manager: T.nilable(T.untyped)
      ).void
    end
    def initialize(config:, logger:, cache_manager: nil, github_client: nil, pr_manager: nil)
      @config = T.let(config, T::Hash[String, T.untyped])
      @logger = T.let(logger, T.untyped)
      @cache_manager = T.let(cache_manager, T.nilable(Cache))
      @github_client = T.let(github_client, T.nilable(T.untyped))
      @pr_manager = T.let(pr_manager, T.nilable(T.untyped))
    end

    # Process a single repository
    # @param repo_name [String] Repository name
    # @param repo_url [String] Repository URL
    # @return [Hash] Processing result hash
    sig do
      params(
        repo_name: String,
        repo_url: String
      ).returns(T::Hash[String, T.untyped])
    end
    def process_repository(repo_name, repo_url)
      start_time = Time.now
      logger.info("Processing repository: #{repo_name}")

      # Prepare result hash with defaults
      result = {
        name: repo_name,
        url: repo_url,
        state: 'skipped',
        issues_found: false,
        time_taken: 0,
        error: nil,
        message: ''
      }

      # Set up the working directory for this repository
      repo_dir = prepare_repo_directory(repo_name)

      # Clone or update the repository
      begin
        commit_sha = clone_or_update_repository(repo_url, repo_dir)
        return result.merge(state: 'error', error: 'Failed to get commit SHA') if commit_sha.nil?
      rescue StandardError => e
        logger.error("Error cloning/updating repository #{repo_name}: #{e.message}")
        return result.merge(state: 'error', error: "Git error: #{e.message}")
      end

      # Check if repository is up to date in cache
      if cache_up_to_date?(repo_name, commit_sha)
        logger.info("Skipping #{repo_name} - No changes detected since last run")
        return result.merge(state: 'skipped', message: 'No changes detected since last run')
      end

      # Run Cookstyle on the repository
      begin
        cookstyle_result = run_cookstyle_checks(repo_dir)
        issues_found = cookstyle_result[:issue_count].positive?

        result = result.merge(
          state: 'processed',
          issues_found: issues_found,
          auto_correctable: cookstyle_result[:auto_correctable_count],
          manual_fixes: cookstyle_result[:manual_fixes_count],
          offense_details: cookstyle_result[:offense_details]
        )
      rescue StandardError => e
        logger.error("Error running Cookstyle on #{repo_name}: #{e.message}")
        return result.merge(state: 'error', error: "Cookstyle error: #{e.message}")
      end

      # Create pull request or issue if there are issues and we're not in dry run mode
      result = handle_issues(result, repo_dir, repo_name, commit_sha) unless @config[:dry_run] || !issues_found

      # Update cache if enabled
      update_cache(repo_name, commit_sha, issues_found, JSON.generate(cookstyle_result), Time.now - start_time) if @cache_manager

      # Add the time taken to the result
      result[:time_taken] = Time.now - start_time
      logger.info("Finished processing #{repo_name} in #{result[:time_taken].round(2)}s")
      result
    end

    private

    # Prepare the repository directory
    # @param repo_name [String] Repository name
    # @return [String] Repository directory path
    sig { params(repo_name: String).returns(String) }
    def prepare_repo_directory(repo_name)
      repo_dir = File.join(@config[:workspace_dir], repo_name)
      FileUtils.mkdir_p(repo_dir)
      repo_dir
    end

    # Clone or update the repository
    # @param repo_url [String] Repository URL
    # @param repo_dir [String] Repository directory path
    # @return [String, nil] The current commit SHA or nil if failed
    sig { params(repo_url: String, repo_dir: String).returns(T.nilable(String)) }
    def clone_or_update_repository(repo_url, repo_dir)
      if Dir.exist?(File.join(repo_dir, '.git'))
        # Update existing repository
        logger.debug("Updating existing repository in #{repo_dir}")
        Git.update_repository(repo_dir, logger)
      else
        # Clone new repository
        logger.debug("Cloning #{repo_url} to #{repo_dir}")
        Git.clone_repository(repo_url, repo_dir, logger)
      end

      # Get current commit SHA
      Git.get_current_sha(repo_dir, logger)
    end

    # Check if the repository is up to date in the cache
    # @param repo_name [String] Repository name
    # @param commit_sha [String] Current commit SHA
    # @return [Boolean] True if up to date in cache
    sig { params(repo_name: String, commit_sha: String).returns(T::Boolean) }
    def cache_up_to_date?(repo_name, commit_sha)
      return false unless @cache_manager && @config[:use_cache]

      max_age = @config[:cache_max_age] || (7 * 24 * 60 * 60) # Default to 7 days in seconds
      @cache_manager.up_to_date?(repo_name, commit_sha, max_age: max_age)
    end

    # Run Cookstyle checks on the repository
    sig { params(repo_dir: String).returns(T::Hash[Symbol, T.untyped]) }
    def run_cookstyle_checks(repo_dir)
      logger.debug("Running Cookstyle on #{repo_dir}")
      CookstyleOperations.run_cookstyle(repo_dir, logger, @config[:auto_correct])
    end

    # Handle issues found in the repository by creating PR or issue
    sig do
      params(
        result: T::Hash[String, T.untyped],
        repo_dir: String,
        repo_name: String,
        commit_sha: String
      ).returns(T::Hash[String, T.untyped])
    end
    def handle_issues(result, repo_dir, repo_name, commit_sha)
      return result unless @pr_manager

      # Prepare strings for PR/issue
      repo_full_name = "#{@config[:owner]}/#{repo_name}"
      branch_name = @config[:branch_name] || 'cookstyle-fixes'

      if result[:auto_correctable].positive?
        # Create pull request with auto-corrected changes
        handle_auto_correctable_issues(result, repo_dir, repo_full_name, branch_name, commit_sha)
      elsif result[:manual_fixes].positive?
        # Create issue with details for manual fixing
        handle_manual_fixes(result, repo_full_name)
      else
        # No actionable issues, just return the result
        result
      end
    end

    # Handle auto-correctable issues by creating a pull request
    sig do
      params(
        result: T::Hash[String, T.untyped],
        repo_dir: String,
        repo_full_name: String,
        branch_name: String,
        base_commit: String
      ).returns(T::Hash[String, T.untyped])
    end
    def handle_auto_correctable_issues(result, repo_dir, repo_full_name, branch_name, _base_commit)
      return result unless @pr_manager

      # Run Cookstyle with auto-correct
      logger.info("Auto-correcting #{result[:auto_correctable]} issues in #{repo_full_name}")
      auto_correct_result = CookstyleOperations.run_cookstyle(repo_dir, logger, true)

      # Update changelog if configured
      if @config[:manage_changelog]
        context = {
          repo_dir: repo_dir,
          repo_name: repo_full_name.split('/').last,
          owner: @config[:owner]
        }

        ChangelogUpdater.update_changelog(context, @config, result[:offense_details])
      end

      # Commit changes and create PR
      begin
        # Commit the changes locally
        commit_message = "Cookstyle auto-corrections\n\nThis change is automatically generated by the GitHub Cookstyle Runner."
        Git.commit_changes(repo_dir, branch_name, commit_message, logger)

        # Push changes and create PR
        default_branch = Git.get_default_branch(repo_dir, logger)
        pr_result = @pr_manager.create_pr(repo_full_name, branch_name, default_branch, {
                                            title: @config[:pull_request_title] || 'Automated PR: Cookstyle Changes',
                                            body: format_pr_description(auto_correct_result[:offense_details]),
                                            labels: %w[cookstyle automated-pr]
                                          })

        if pr_result[:success]
          result[:pr_url] = pr_result[:url]
          result[:pr_number] = pr_result[:number]
          result[:message] = "Created PR ##{pr_result[:number]} with auto-corrected changes"
          logger.info("Created PR ##{pr_result[:number]} for #{repo_full_name}")
        else
          result[:error] = pr_result[:error]
          logger.error("Failed to create PR for #{repo_full_name}: #{pr_result[:error]}")
        end
      rescue StandardError => e
        result[:error] = "Failed to create PR: #{e.message}"
        logger.error("Error creating PR for #{repo_full_name}: #{e.message}")
      end

      result
    end

    # Handle manual fixes by creating an issue
    sig do
      params(
        result: T::Hash[String, T.untyped],
        repo_full_name: String
      ).returns(T::Hash[String, T.untyped])
    end
    def handle_manual_fixes(result, repo_full_name)
      return result unless @pr_manager

      # Create issue with details for manual fixing
      logger.info("Creating issue for #{result[:manual_fixes]} manual fixes in #{repo_full_name}")

      issue_result = @pr_manager.create_issue(repo_full_name, {
                                                title: 'Manual Cookstyle Fixes Required',
                                                body: format_issue_description(result[:offense_details]),
                                                labels: %w[cookstyle manual-fixes-required]
                                              })

      if issue_result[:success]
        result[:issue_url] = issue_result[:url]
        result[:issue_number] = issue_result[:number]
        result[:message] = "Created issue ##{issue_result[:number]} for manual fixes"
        logger.info("Created issue ##{issue_result[:number]} for #{repo_full_name}")
      else
        result[:error] = issue_result[:error]
        logger.error("Failed to create issue for #{repo_full_name}: #{issue_result[:error]}")
      end

      result
    end

    # Format PR description based on offense details
    sig { params(offense_details: T::Hash[String, T.untyped]).returns(String) }
    def format_pr_description(offense_details)
      pr_body = "## Cookstyle Automated Changes\n\n"
      pr_body += "This pull request applies automatic Cookstyle fixes to ensure code quality and consistency.\n\n"
      pr_body += "### Changes Made\n\n"

      offense_details[:files]&.each do |file|
        pr_body += "* **#{file[:path]}**: "
        pr_body += file[:offenses].map { |o| o[:cop_name] }.uniq.join(', ')
        pr_body += "\n"
      end

      pr_body += "\n### Summary\n\n"
      pr_body += "* Total offenses fixed: #{offense_details[:summary][:offense_count]}\n"
      pr_body += "* Files updated: #{offense_details[:files]&.length || 0}\n\n"
      pr_body += '*This PR was automatically generated by the [GitHub Cookstyle Runner](https://github.com/damacus/github-cookstyle-runner).*'

      pr_body
    end

    # Format issue description based on offense details
    sig { params(offense_details: T::Hash[String, T.untyped]).returns(String) }
    def format_issue_description(offense_details)
      issue_body = "## Cookstyle Manual Fixes Required\n\n"
      issue_body += "The following Cookstyle offenses were found but require manual fixes:\n\n"

      offense_details[:files]&.each do |file|
        next if file[:offenses].empty?

        issue_body += "### #{file[:path]}\n\n"

        file[:offenses].each do |offense|
          next if offense[:correctable]

          issue_body += "* **#{offense[:cop_name]}** at line #{offense[:location][:line]}: "
          issue_body += "#{offense[:message]}\n"
        end

        issue_body += "\n"
      end

      issue_body += "### Summary\n\n"
      issue_body += "* Total offenses requiring manual fixes: #{offense_details[:summary][:offense_count]}\n"
      issue_body += "* Files with issues: #{offense_details[:files]&.length || 0}\n\n"
      issue_body += '*This issue was automatically generated by the [GitHub Cookstyle Runner](https://github.com/damacus/github-cookstyle-runner).*'

      issue_body
    end

    # Update cache with processing results
    sig do
      params(
        repo_name: String,
        commit_sha: String,
        had_issues: T::Boolean,
        result: String,
        processing_time: Float
      ).returns(NilClass)
    end
    def update_cache(repo_name, commit_sha, had_issues, result, processing_time)
      @cache.update_cache(repo_name, commit_sha, had_issues, result, processing_time)
    end
    sig do
      params(
        repo_name: String,
        commit_sha: String,
        had_issues: T::Boolean,
        result: String,
        processing_time: Float
      ).void
    end
    def update_cache(repo_name, commit_sha, had_issues, result, processing_time)
      return unless @cache_manager && @config[:use_cache]

      @cache_manager.update(repo_name, commit_sha, had_issues, result, processing_time)
      logger.debug("Updated cache for #{repo_name}")
    end
  end
end
