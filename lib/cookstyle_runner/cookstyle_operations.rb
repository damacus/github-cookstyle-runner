#!/usr/bin/env ruby
# frozen_string_literal: true

require 'logger'
require 'tty-command'
require 'fileutils'
require 'json'
require_relative 'git_operations'

# Module for cookstyle operations
module CookstyleRunner
  # Default return value for run_cookstyle in case of critical errors
  DEFAULT_ERROR_RETURN = [{}, 0, 0, '', '', false].freeze

  CookstyleReport = Struct.new(:num_auto, :num_manual, :pr_description, :issue_description)

  # Encapsulates operations related to running Cookstyle, parsing its output,
  # handling auto-correction, and generating descriptions for reports/PRs.
  module CookstyleOperations
    # Runs cookstyle, parses output, optionally runs auto-correction and commits, and formats descriptions.
    # @param context [RepoContext] Git context
    # @param logger [Logger] Logger instance
    # @return [Array<Hash, Integer, Integer, String, String, Boolean>]
    #   - Parsed JSON output from the initial run
    #   - Number of auto-correctable offenses found
    #   - Number of manually correctable (uncorrectable) offenses found
    #   - Formatted PR description (if applicable)
    #   - Formatted Issue description (if applicable)
    #   - Boolean indicating if changes were committed
    #   - Returns default values ([{}, 0, 0, '', '', false]) on errors.
    def self.run_cookstyle(context, logger)
      cmd = TTY::Command.new(output: logger, pty: true)

      begin
        # Execute main logic; result needed only for parse error handling
        logger.debug('Calling _execute_cookstyle_and_process...')
        process_results = _execute_cookstyle_and_process(context, logger, cmd)
        logger.debug("Received process_results in run_cookstyle: #{process_results.inspect}")
        parsed_json, report = process_results
        changes_committed = _run_autocorrection(context, logger, cmd, report.num_auto)
        [parsed_json, report.num_auto, report.num_manual, report.pr_description, report.issue_description, changes_committed]
      rescue TTY::Command::ExitError => e
        _handle_command_exit_error(logger, e)
      rescue StandardError => e
        _handle_unexpected_error(logger, e)
      end
    end

    # --- Private Helper Methods ---

    # Executes the core cookstyle command, parses results, and handles autocorrect.
    # Returns results array and the command result object.
    # Raises errors to be caught by run_cookstyle.
    private_class_method def self._execute_cookstyle_and_process(context, logger, cmd)
      cookstyle_result = cmd.run!('cookstyle --display-cop-names --format json', chdir: context.repo_dir, timeout: 300)

      if cookstyle_result.failure?
        # Command failed, attempt secondary parse via handler
        parsed_json_secondary, success = _handle_command_exit_error(logger, cookstyle_result)
        return DEFAULT_ERROR_RETURN unless success

        # Use the successfully parsed JSON from the handler
        parsed_json = parsed_json_secondary
      else
        # Command succeeded, parse primary output
        parsed_json = _parse_json_safely(logger, cookstyle_result.out)
      end

      # Calculate results using the determined parsed_json
      cookstyle_report = _calculate_results(parsed_json)

      # Return all relevant data
      logger.debug("Returning from _execute_cookstyle_and_process with parsed_json: #{parsed_json.inspect}")
      [parsed_json, cookstyle_report]
    end

    # Calculates offense counts and generates descriptions from parsed JSON.
    # @param parsed_json [Hash] The parsed JSON output from Cookstyle.
    # @return [Array] [num_auto, num_manual, pr_desc, issue_desc]
    private_class_method def self._calculate_results(parsed_json)
      num_auto = count_correctable_offences(parsed_json)
      num_manual = count_uncorrectable_offences(parsed_json)
      total = num_auto + num_manual

      pr_summary = format_pr_summary(total, num_auto)
      pr_details = format_pr_description(parsed_json, num_auto)
      pr_description = "#{pr_summary}\n\n#{pr_details}".strip

      issue_summary = format_issue_summary(total, num_manual)
      issue_details = format_issue_description(parsed_json)
      issue_description = "#{issue_summary}\n\n#{issue_details}".strip

      CookstyleReport.new(num_auto, num_manual, pr_description, issue_description)
    end

    # Handles running auto-correction and committing changes.
    # Returns true if changes were successfully committed, false otherwise.
    private_class_method def self._run_autocorrection(context, logger, cmd, num_auto)
      return false unless num_auto.positive?

      begin
        logger.info("Running cookstyle --autocorrect-all for #{context.repo_name}")
        cmd.run!('cookstyle --autocorrect-all', chdir: context.repo_dir, timeout: 300)
        _commit_autocorrections(context, logger)
      rescue TTY::Command::ExitError => e
        _log_autocorrect_command_error(logger, e)
        false
      rescue StandardError => e # Catch unexpected errors during autocorrect/commit
        _log_unexpected_autocorrect_error(context.repo_name, logger, e)
        false
      end
    end

    # Commits changes after a successful auto-correction run.
    private_class_method def self._commit_autocorrections(context, logger)
      if GitOperations.changes_to_commit?(context)
        logger.info("Detected changes after auto-correction for #{context.repo_name}, attempting commit.")
        commit_message = 'Fix: Apply Cookstyle auto-corrections'
        GitOperations.add_and_commit_changes(context, commit_message) # Returns true/false
      else
        logger.info("No effective changes detected after auto-correction for #{context.repo_name}.")
        false # No changes committed
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

    # Determines if manual attention is required based on offense flags.
    # @param has_offenses [Boolean] Whether any offenses were detected.
    # @param correctable [Boolean] Whether any of the detected offenses are correctable.
    # @return [Boolean] True if there are offenses, none of which are correctable.
    def self.manual_attention_required?(has_offenses, correctable)
      has_offenses && !correctable.zero?
    end

    # Counts the number of offenses present in the parsed JSON.
    # @param parsed_json [Hash] Parsed JSON object from cookstyle run
    # @return [Integer] Total number of offenses
    private_class_method def self.count_total_offences(parsed_json)
      parsed_json.dig('summary', 'offense_count') || 0
    end

    # Processes a single offense, updating counts and details arrays.
    # @param offense [Hash] The offense hash.
    # @param file_path [String] The path of the file containing the offense.
    # @param corrected_count [Integer] The current count of corrected offenses.
    # @param uncorrected_details [Array<String>] The array of uncorrected details.
    # @return [Integer, Array<String>] The updated corrected_count and uncorrected_details.
    private_class_method def self._process_offense(offense, file_path, corrected_count, uncorrected_details)
      if offense['corrected']
        [corrected_count + 1, uncorrected_details]
      else
        message_line = offense['message'] ? offense['message'].lines.map(&:strip).join(' ') : 'No message'
        [corrected_count, uncorrected_details << "* `#{file_path}`: #{offense['cop_name']} - #{message_line}"]
      end
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

    # Handles JSON parsing errors from the initial cookstyle run.
    private_class_method def self._handle_json_parse_error(logger, error, result)
      logger.error("Failed to parse Cookstyle JSON output: #{error.message}")
      logger.error("Raw output:\n#{result&.out}")
      DEFAULT_ERROR_RETURN # Defaults on parse error
    end

    # Handles command exit errors from the initial cookstyle run, including secondary JSON parse attempt.
    private_class_method def self._handle_command_exit_error(logger, error)
      _log_command_error_details(logger, error)
      _attempt_secondary_parse(logger, error.out)
    end

    # Logs the details of a TTY::Command::ExitError.
    private_class_method def self._log_command_error_details(logger, error)
      logger.error("Cookstyle command failed: #{error.message}")
      logger.error("STDOUT:\n#{error.out}") unless error.out.empty?
      logger.error("STDERR:\n#{error.err}") unless error.err.empty?
    end

    # Attempts to parse the output string as JSON after a command error.
    # Calculates results if parse succeeds, otherwise returns defaults.
    private_class_method def self._attempt_secondary_parse(logger, output_string)
      parsed_json = _parse_json_safely(logger, output_string)

      # Calculate results based on parsed_json (which is {} if parse failed or skipped)
      if parsed_json.empty?
        DEFAULT_ERROR_RETURN # Defaults on secondary parse error
      else
        num_auto, num_manual, pr_desc, issue_desc = _calculate_results(parsed_json)
        # Don't run autocorrect here as the initial run failed
        [parsed_json, num_auto, num_manual, pr_desc, issue_desc, false]
      end
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

    # Handles unexpected standard errors during the cookstyle run.
    private_class_method def self._handle_unexpected_error(logger, error)
      logger.error("Unexpected error in run_cookstyle: #{error.message}")
      logger.debug(error.backtrace.join("\n"))
      # Return defaults for unexpected errors
      DEFAULT_ERROR_RETURN
    end
  end
end
