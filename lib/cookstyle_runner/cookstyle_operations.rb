#!/usr/bin/env ruby
# frozen_string_literal: true

require 'logger'
require 'open3'
require 'fileutils'

# Module for cookstyle operations
module CookstyleOperations
  # Run cookstyle on a repository
  # @param repo_dir [String] Repository directory
  # @param logger [Logger] Logger instance
  # @return [Array<Integer, String, Boolean>] Exit status, output, and whether issues were found
  def self.run_cookstyle(repo_dir, logger)
    thread_id = Thread.current.object_id
    cookstyle_output_file = "/tmp/cookstyle_output_#{thread_id}.txt"
    cookstyle_fixes_file = "/tmp/cookstyle_fixes_#{thread_id}.txt"
    changes_file = "/tmp/changes_#{thread_id}.txt"

    begin
      # Use Open3 to capture output from the subprocess
      stdout, _, status = Open3.capture3(
        "cd #{repo_dir} && " +
        # First run cookstyle without auto-correction to check for issues
        'cookstyle_result=$(cookstyle -D 2>&1); cookstyle_status=$?; ' \
        "echo \"Cookstyle exit status: $cookstyle_status\" > #{cookstyle_output_file}; " \
        "echo \"$cookstyle_result\" >> #{cookstyle_output_file}; " \
        'if [ $cookstyle_status -eq 0 ]; then ' \
        "  echo 'No issues found'; " \
        '  had_issues=false; ' \
        'else ' \
        '  echo "Cookstyle found issues:"; ' \
        '  echo "$cookstyle_result"; ' \
        '  had_issues=true; ' +
        # Run cookstyle with auto-corrections
        "  cookstyle -a > #{cookstyle_fixes_file} 2>&1; " \
        "  cat #{cookstyle_fixes_file}; " +
        # Check for any changes (including permission changes) - use git diff to catch mode changes
        "  git diff --name-status > #{changes_file}; " \
        "  git status --porcelain >> #{changes_file}; " \
        "  if [ -s #{changes_file} ]; then " \
        '    echo "Changes detected after cookstyle auto-correction:"; ' \
        "    cat #{changes_file}; " \
        '    has_changes=true; ' \
        '  else ' \
        '    echo "No changes detected after cookstyle auto-correction"; ' \
        '    has_changes=false; ' \
        '  fi; ' \
        'fi; ' \
        'echo $had_issues; ' \
        'echo $has_changes'
      )

      # Read output files
      cookstyle_output = File.exist?(cookstyle_output_file) ? File.read(cookstyle_output_file) : ''

      # Parse output to determine if issues were found and if changes were made
      had_issues = stdout.include?('had_issues=true')
      has_changes = stdout.include?('has_changes=true')

      # Clean up temporary files
      [cookstyle_output_file, cookstyle_fixes_file, changes_file].each do |file|
        File.unlink(file) if File.exist?(file)
      end

      # Return the exit status, output, and whether issues were found
      [status.exitstatus, cookstyle_output, had_issues, has_changes]
    rescue StandardError => e
      logger.error("Error running cookstyle: #{e.message}")
      logger.debug(e.backtrace.join("\n"))
      [1, "Error: #{e.message}", false, false]
    end
  end

  # Parse cookstyle output to determine if there are auto-fixable issues
  # @param cookstyle_output [String] Output from cookstyle run
  # @return [Boolean] True if there are auto-fixable issues
  def self.auto_fixable_issues?(cookstyle_output)
    # Look for patterns in the output that indicate auto-fixable issues
    cookstyle_output.include?('auto-correct') ||
      cookstyle_output.include?('auto-correction') ||
      cookstyle_output.include?('(A)')
  end

  # Parse cookstyle output to determine if there are manual fix issues
  # @param cookstyle_output [String] Output from cookstyle run
  # @return [Boolean] True if there are manual fix issues
  def self.manual_fix_issues?(cookstyle_output)
    # If there are issues but no auto-fixable ones, they require manual fixes
    cookstyle_output.include?('offenses detected') && !auto_fixable_issues?(cookstyle_output)
  end

  # Format cookstyle output for PR description
  # @param cookstyle_output [String] Output from cookstyle run
  # @return [String] Formatted output for PR description
  def self.format_pr_description(cookstyle_output)
    # Extract relevant parts of the output for the PR description
    lines = cookstyle_output.split("\n")

    # Find lines with offenses
    offense_lines = lines.select { |line| line.include?('offense') || line.include?('Offenses:') }

    # Format the output
    if offense_lines.empty?
      "Cookstyle auto-corrections applied.\n\n```\n#{cookstyle_output}\n```"
    else
      "Cookstyle auto-corrections applied.\n\n**Offenses fixed:**\n\n```\n#{offense_lines.join("\n")}\n```"
    end
  end
end
