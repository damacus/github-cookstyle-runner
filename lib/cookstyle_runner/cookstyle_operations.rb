# typed: true
# frozen_string_literal: true

require 'logger'
require 'tty-command'
require 'fileutils'
require 'json'
require_relative 'git'

# Module for cookstyle operations
module CookstyleRunner
  # Class for Cookstyle report
  class Report
    attr_reader :num_auto, :num_manual, :total_correctable, :pr_description, :issue_description, :error, :status

    # rubocop:disable Metrics/ParameterLists
    def initialize(num_auto: 0, num_manual: 0, pr_description: '', issue_description: '', error: false, status: :no_issues)
      @num_auto = num_auto
      @num_manual = num_manual
      @total_correctable = num_auto + num_manual
      @pr_description = pr_description
      @issue_description = issue_description
      @error = error
      @status = status
    end
    # rubocop:enable Metrics/ParameterLists
  end
  # Default return value for run_cookstyle in case of critical errors
  DEFAULT_ERROR_RETURN = { parsed_json: nil, report: Report.new(error: true) }.freeze

  # Encapsulates operations related to running Cookstyle, parsing its output,
  # handling auto-correction, and generating descriptions for reports/PRs.
  module CookstyleOperations
    # Runs Cookstyle twice: once for reporting, and again for autocorrect if needed.
    # @param context [Git::RepoContext] The run context.
    # @param config [Hash] Configuration hash.
    # @param logger [TTY::Logger] Logger instance.
    # @return [Hash] Contains :parsed_json (from first run) and :report (final state report) or DEFAULT_ERROR_RETURN.
    # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    def self.run_cookstyle(context, logger)
      cmd = TTY::Command.new(output: logger, pty: true)
      report = nil # Initialize report variable
      report_run = nil # Initialize report_run variable

      begin
        # Run 1: Report mode
        report_run = _execute_cookstyle_and_process(context, logger, cmd, autocorrect: false)
        report = report_run[:report]

        if report.num_auto.positive?
          # Run 2: Autocorrect mode
          autocorrect_run = _execute_cookstyle_and_process(context, logger, cmd, autocorrect: true)
          # Update the report variable only if the autocorrect run was successful and returned a report
          report = autocorrect_run[:report]
        elsif report.num_manual.positive?
          logger.debug("Initial run found no auto-correctable offenses (num_auto: #{report.num_auto}). Skipping autocorrect.")
          logger.debug("#{report.num_manual} issues will be created for #{context.repo_name}.")
        end
      rescue TTY::Command::ExitError, StandardError => e
        logger.error("*** Caught exception in run_cookstyle: #{e.message} ***")
        logger.debug(T.must(e.backtrace).join("\n"))

        return DEFAULT_ERROR_RETURN
      end

      # Ensure report_run and its parsed_json are valid before returning
      unless report_run && report_run[:parsed_json]
        logger.error('Missing parsed_json from the initial report run.')
        return DEFAULT_ERROR_RETURN
      end

      { parsed_json: report_run[:parsed_json], report: report }
    end
    # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

    # --- Private Helper Methods ---
    # Executes the core cookstyle command, parses results, and handles autocorrect.
    # Returns results array and the command result object.
    # Raises errors to be caught by run_cookstyle.
    # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    private_class_method def self._execute_cookstyle_and_process(context, logger, cmd, autocorrect: false)
      logger.debug("Executing Cookstyle: autocorrect=#{autocorrect}")

      command = 'cookstyle --format json --display-cop-names'
      command += ' --autocorrect-all' if autocorrect

      cookstyle_result = cmd.run!(
        command,
        chdir: context.repo_dir,
        timeout: 300,
        only_output_on_error: true
      )

      # changes_committed = _commit_autocorrections(context, logger) if autocorrect

      if cookstyle_result.exit_status == 2
        logger.error('Cookstyle command failed unexpectedly.')
        logger.error("Exit Status: #{cookstyle_result.exit_status}")
        logger.error("Stderr: #{cookstyle_result.err}".strip)
        logger.error("Stdout: #{cookstyle_result.out}".strip)
        return DEFAULT_ERROR_RETURN
      end

      logger.debug("Cookstyle command finished. Exit Status: #{cookstyle_result.exit_status}")
      logger.debug("Cookstyle stdout (first 500 chars):\n#{cookstyle_result.out.slice(0, 500)}")
      logger.debug("Cookstyle stderr:\n#{cookstyle_result.err}")

      # Proceed to parse JSON if exit status was 0 or 1
      parsed_json = _parse_json_safely(logger, cookstyle_result.out)

      # Check if parsing failed or resulted in empty data
      if parsed_json.nil? || parsed_json.empty?
        logger.error("Cookstyle command ran (exit status #{cookstyle_result.exit_status}) but produced no parsable JSON output or empty data.")
        logger.debug("Raw Stdout: #{cookstyle_result.out}")
        logger.debug("Raw Stderr: #{cookstyle_result.err}")
        return DEFAULT_ERROR_RETURN
      end

      # Calculate results using the valid parsed_json
      logger.debug('JSON parsed successfully. Calculating results.')
      report = _parse_results(parsed_json)

      # Return all relevant data
      logger.debug("Returning from _execute_cookstyle_and_process with parsed_json: #{parsed_json.inspect}")
      { parsed_json: parsed_json, report: report }
    end
    # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

    # Calculates offense counts and generates descriptions from parsed JSON.
    # @param parsed_json [Hash] The parsed JSON output from Cookstyle.
    # @return [Array] [num_auto, num_manual, pr_desc, issue_desc]
    private_class_method def self._parse_results(parsed_json)
      num_auto = count_correctable_offences(parsed_json)
      num_manual = count_uncorrectable_offences(parsed_json)
      total = num_auto + num_manual

      pr_summary = format_pr_summary(total, num_auto)
      pr_details = format_pr_description(parsed_json, num_auto)
      pr_description = "#{pr_summary}\n\n#{pr_details}".strip

      issue_summary = format_issue_summary(total, num_manual)
      issue_details = format_issue_description(parsed_json)
      issue_description = "#{issue_summary}\n\n#{issue_details}".strip

      Report.new(num_auto: num_auto,
                 num_manual: num_manual,
                 pr_description: pr_description,
                 issue_description: issue_description)
    end

    # Commits changes after a successful auto-correction run.
    private_class_method def self._commit_autocorrections(context, logger)
      if Git.changes_to_commit?(context)
        logger.info("Detected changes after auto-correction for #{context.repo_name}, attempting commit.")
        commit_message = 'Fix: Apply Cookstyle auto-corrections'
        Git.add_and_commit_changes(context, commit_message)
      else
        logger.info("No changes detected after auto-correction for #{context.repo_name}.")
        false
      end
    end

    # Logs errors from the cookstyle auto-correct command.
    private_class_method def self._log_autocorrect_command_error(logger, error)
      logger.error("Cookstyle auto-correct command failed: #{error.message}")
      logger.error("STDOUT:\n#{error.out}") unless error.out.empty?
      logger.error("STDERR:\n#{error.err}") unless error.err.empty?
    end

    # Logs unexpected errors during the auto-correction/commit phase.
    private_class_method def self._log_unexpected_autocorrect_error(repo_name, logger, error)
      logger.error("Unexpected error during auto-correction/commit for #{repo_name}: #{error.message}")
      logger.debug(error.backtrace.join("\n"))
    end

    # Determines if any offenses are present in the parsed JSON.
    # @param parsed_json [Hash] Parsed JSON object from cookstyle run
    # @return [Boolean] True if any offenses are present
    def self.offenses?(parsed_json)
      parsed_json['files']&.any? do |file|
        # Check that 'offenses' exists AND is not empty
        file['offenses'] && !file['offenses'].empty?
      end || false
    end

    # Counts the number of correctable offenses in the parsed JSON.
    # @param parsed_json [Hash] Parsed JSON object from cookstyle run
    # @return [Integer] Number of correctable offenses
    def self.count_correctable_offences(parsed_json)
      count = 0
      parsed_json['files']&.each do |file|
        file['offenses']&.each { |offense| count += 1 if offense['correctable'] }
      end
      count
    end

    # Counts the number of uncorrectable offenses in the parsed JSON.
    # @param parsed_json [Hash] Parsed JSON object from cookstyle run
    # @return [Integer] Number of uncorrectable offenses
    def self.count_uncorrectable_offences(parsed_json)
      count = 0
      parsed_json['files']&.each do |file|
        file['offenses']&.each { |offense| count += 1 unless offense['correctable'] }
      end
      count
    end

    # Formats the main summary section of the PR description.
    # @param offense_count [Integer] Total number of offenses.
    # @param corrected_count [Integer] Number of auto-corrected offenses.
    # @return [String] Formatted summary string.
    def self.format_pr_summary(offense_count, corrected_count)
      review_needed = offense_count.zero? ? 0 : offense_count - corrected_count

      <<~SUMMARY.strip
        ### Cookstyle Run Summary
        - **Total Offenses Detected:** #{offense_count}
        - **Auto-corrected:** #{corrected_count}
        - **Manual Review Needed:** #{review_needed}
      SUMMARY
    end

    # Format cookstyle output for PR description
    # @param parsed_json [Hash] Parsed JSON object from cookstyle run
    # @param num_auto_correctable [Integer] Number of offenses that were auto-corrected.
    # @return [String] Formatted output for PR description detailing offenses.
    def self.format_pr_description(parsed_json, num_auto_correctable)
      return '' if num_auto_correctable.zero?

      <<~OFFENCES.strip
        ### Offences
        #{format_offenses(parsed_json)}
      OFFENCES
    end

    # Formats the offenses section of the PR description.
    # @param parsed_json [Hash] Parsed JSON object from cookstyle run
    # @return [String] Formatted output for PR description detailing offenses.
    def self.format_offenses(parsed_json)
      return '' unless parsed_json['files']

      parsed_json['files'].flat_map do |file|
        next unless file['offenses']

        file['offenses'].map { |offense| "* #{file['path']}:#{offense['message']}" }
      end.compact.flatten.join("\n")
    end

    # Formats the summary section of the Issue description.
    # @param offense_count [Integer] Total number of offenses.
    # @param manual_count [Integer] Number of offenses needing manual correction.
    # @return [String] Formatted summary string.
    def self.format_issue_summary(offense_count, manual_count)
      return '' if manual_count.zero?

      <<~SUMMARY.strip
        ### Cookstyle Manual Review Summary
        - **Total Offenses Detected:** #{offense_count}
        - **Manual Review Needed:** #{manual_count}
      SUMMARY
    end

    # Formats the offenses section of the Issue description.
    # @param parsed_json [Hash] Parsed JSON object from cookstyle run
    # @return [String] Formatted output for issue description detailing offenses.
    def self.format_issue_description(parsed_json)
      offenses = manual_offenses(parsed_json)
      return '' if offenses.empty?

      <<~STRING.strip
        ### Manual Intervention Required
        #{offenses.join("\n")}
      STRING
    end

    # Returns an array of formatted offenses that require manual attention.
    # @param parsed_json [Hash] Parsed JSON object from cookstyle run
    # @return [Array<String>] Array of formatted offense strings.
    def self.manual_offenses(parsed_json)
      return [] unless parsed_json['files']

      parsed_json['files'].flat_map do |file|
        next unless file['offenses']

        file['offenses']
          .reject { |offense| offense['correctable'] }
          .map { |offense| format_manual_offense(file, offense) }
      end.compact.flatten
    end

    # Formats a single offense for the manual intervention section.
    # @param file [Hash] File containing the offense.
    # @param offense [Hash] The offense hash.
    # @return [String] Formatted offense string.
    def self.format_manual_offense(file, offense)
      message = offense['message']
      message_line = message ? message.lines.map(&:strip).join(' ') : 'No message'
      "* `#{file['path']}`:#{offense['cop_name']} - #{message_line}"
    end

    # Safely parses a JSON string, logging errors and returning {} on failure.
    private_class_method def self._parse_json_safely(logger, json_string)
      return {} unless json_string && !json_string.empty?

      begin
        JSON.parse(json_string)
      rescue JSON::ParserError => e
        logger.error("JSON parse failed: #{e.message}")
        {}
      end
    end
  end
end
