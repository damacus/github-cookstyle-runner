# typed: true
# frozen_string_literal: true

require 'semantic_logger'
require 'tty-command'
require 'fileutils'
require 'json'
require_relative 'git'

# Module for cookstyle operations
module CookstyleRunner
  # Custom printer for TTY::Command that logs to SemanticLogger at DEBUG level
  class CommandPrinter < TTY::Command::Printers::Abstract
    def initialize(logger)
      @logger = logger
      super($stdout)
    end

    def print_command_start(cmd, **)
      @logger.debug("Running command: #{cmd.to_command}")
    end

    def print_command_exit(_cmd, status, runtime, **)
      if status.zero?
        @logger.debug("Command finished in #{runtime.round(3)}s with exit status #{status}")
      else
        @logger.warn("Command failed in #{runtime.round(3)}s with exit status #{status}")
      end
    end

    def print_command_out_data(_cmd, *_args)
      # Suppress stdout - we capture it separately
    end

    def print_command_err_data(_cmd, *_args)
      # Suppress stderr - we capture it separately
    end
  end

  # Class for Cookstyle report
  class Report
    attr_reader :num_auto, :num_manual, :total_correctable, :pr_description, :issue_description, :error, :status, :changes_committed

    def initialize(num_auto: 0, num_manual: 0, pr_description: '', issue_description: '', error: false, status: :no_issues,
                   changes_committed: false)
      @num_auto = num_auto
      @num_manual = num_manual
      @total_correctable = num_auto + num_manual
      @pr_description = pr_description
      @issue_description = issue_description
      @error = error
      @status = status
      @changes_committed = changes_committed
    end
  end
  # Default return value for run_cookstyle in case of critical errors
  DEFAULT_ERROR_RETURN = { parsed_json: nil, report: Report.new(error: true) }.freeze

  # Encapsulates operations related to running Cookstyle, parsing its output,
  # handling auto-correction, and generating descriptions for reports/PRs.
  module CookstyleOperations
    extend T::Sig

    @log = T.let(SemanticLogger[self], SemanticLogger::Logger)

    sig { returns(SemanticLogger::Logger) }
    def self.log
      @log
    end

    # Runs Cookstyle twice: once for reporting, and again for autocorrect if needed.
    # @param context [Git::RepoContext] The run context.
    # @return [Hash] Contains :parsed_json (from first run) and :report (final state report) or DEFAULT_ERROR_RETURN.
    # rubocop:disable Metrics/MethodLength
    def self.run_cookstyle(context)
      cmd = TTY::Command.new(pty: true, printer: CommandPrinter.new(log))
      report = nil # Initialize report variable
      report_run = nil # Initialize report_run variable

      begin
        # Run 1: Report mode
        report_run = _execute_cookstyle_and_process(context, cmd, autocorrect: false)
        report = report_run[:report]

        # Ensure report_run and its parsed_json are valid before proceeding
        unless report_run && report_run[:parsed_json] && report
          log.error('Missing parsed_json or report from the initial report run.')
          return DEFAULT_ERROR_RETURN
        end

        if report.num_auto.positive?
          # Run 2: Autocorrect mode
          autocorrect_run = _execute_cookstyle_and_process(context, cmd, autocorrect: true)
          # Update the report variable only if the autocorrect run was successful and returned a valid report
          if autocorrect_run && autocorrect_run[:report] && !autocorrect_run[:report].error
            report = autocorrect_run[:report]
          else
            log.error('Autocorrect run failed or returned invalid report.')
            return DEFAULT_ERROR_RETURN
          end
        elsif report.num_manual.positive?
          log.debug("Initial run found no auto-correctable offenses (num_auto: #{report.num_auto}). Skipping autocorrect.")
          log.debug("#{report.num_manual} issues will be created for #{context.repo_name}.")
        end
      rescue TTY::Command::ExitError, StandardError => e
        log.error("Caught exception in run_cookstyle: #{e.message}")
        log.debug(T.must(e.backtrace).join("\n"))

        return DEFAULT_ERROR_RETURN
      end

      { parsed_json: report_run[:parsed_json], report: report }
    end

    # --- Private Helper Methods ---
    # Executes the core cookstyle command, parses results, and handles autocorrect.
    # Returns results array and the command result object.
    # Raises errors to be caught by run_cookstyle.
    private_class_method def self._execute_cookstyle_and_process(context, cmd, autocorrect: false)
      log.debug('Executing Cookstyle', payload: { repo: context.repo_name, autocorrect: autocorrect, operation: 'run_cookstyle' })

      command = 'cookstyle --format json --display-cop-names'
      command += ' --autocorrect-all' if autocorrect

      cookstyle_result = cmd.run!(
        command,
        chdir: context.repo_dir,
        timeout: 300,
        only_output_on_error: true
      )

      if cookstyle_result.exit_status == 2
        log.error('Cookstyle command failed unexpectedly', payload: {
                    exit_status: cookstyle_result.exit_status,
                    stderr: cookstyle_result.err.strip
                  })
        return DEFAULT_ERROR_RETURN
      end

      log.trace('Cookstyle output', payload: { repo: context.repo_name, exit_status: cookstyle_result.exit_status })
      parsed_json = _parse_json_safely(cookstyle_result.out)
      if parsed_json.nil? || parsed_json.empty?
        log.error('Cookstyle produced no parsable JSON output', payload: {
                    repo: context.repo_name,
                    exit_status: cookstyle_result.exit_status,
                    stdout: cookstyle_result.out,
                    stderr: cookstyle_result.err
                  })
        return DEFAULT_ERROR_RETURN
      end

      report = _parse_results(parsed_json)
      { parsed_json: parsed_json, report: report }
    end
    # rubocop:enable Metrics/MethodLength

    # Calculates offense counts and generates descriptions from parsed JSON.
    # @param parsed_json [Hash] The parsed JSON output from Cookstyle.
    # @return [Array] [num_auto, num_manual, pr_desc, issue_desc]
    private_class_method def self._parse_results(parsed_json)
      num_auto, num_manual = count_offences(parsed_json).values_at(:correctable, :uncorrectable)
      total = num_auto + num_manual
      pr_description = "#{format_pr_summary(total, num_auto)}\n\n#{format_pr_description(parsed_json, num_auto)}".strip
      issue_description = "#{format_issue_summary(total, num_manual)}\n\n#{format_issue_description(parsed_json)}".strip
      Report.new(num_auto: num_auto, num_manual: num_manual,
                 pr_description: pr_description, issue_description: issue_description)
    end

    # Commits changes after a successful auto-correction run.
    private_class_method def self._commit_autocorrections(context)
      if Git.changes_to_commit?(context)
        log.info('Detected changes after auto-correction, attempting commit', payload: { repo: context.repo_name, operation: 'commit_changes' })
        commit_message = 'Fix: Apply Cookstyle auto-corrections'
        Git.add_and_commit_changes(context, commit_message)
      else
        log.info('No changes detected after auto-correction', payload: { repo: context.repo_name, operation: 'check_changes' })
        false
      end
    end

    # Logs errors from the cookstyle auto-correct command.
    private_class_method def self._log_autocorrect_command_error(error)
      log.error("Cookstyle auto-correct command failed: #{error.message}")
      log.error("STDOUT:\n#{error.out}") unless error.out.empty?
      log.error("STDERR:\n#{error.err}") unless error.err.empty?
    end

    # Logs unexpected errors during the auto-correction/commit phase.
    private_class_method def self._log_unexpected_autocorrect_error(repo_name, error)
      log.error("Unexpected error during auto-correction/commit for #{repo_name}: #{error.message}")
      log.debug(error.backtrace.join("\n"))
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

    # Counts correctable and uncorrectable offenses in a single pass.
    # @param parsed_json [Hash] Parsed JSON object from cookstyle run
    # @return [Hash] { correctable: Integer, uncorrectable: Integer }
    def self.count_offences(parsed_json)
      counts = { correctable: 0, uncorrectable: 0 }
      parsed_json['files']&.each do |file|
        file['offenses']&.each { |o| counts[o['correctable'] ? :correctable : :uncorrectable] += 1 }
      end
      counts
    end

    # @see .count_offences
    def self.count_correctable_offences(parsed_json)
      count_offences(parsed_json)[:correctable]
    end

    # @see .count_offences
    def self.count_uncorrectable_offences(parsed_json)
      count_offences(parsed_json)[:uncorrectable]
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
    private_class_method def self._parse_json_safely(json_string)
      return {} unless json_string && !json_string.empty?

      begin
        JSON.parse(json_string)
      rescue JSON::ParserError => e
        log.error("JSON parse failed: #{e.message}")
        {}
      end
    end

    # Extracts offense data from parsed Cookstyle JSON output.
    # @param parsed_json [Hash, nil] The parsed JSON output from Cookstyle.
    # @return [Array<Hash>] Array of offense hashes with structured data.
    sig { params(parsed_json: T.nilable(T::Hash[String, T.untyped])).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
    def self.extract_offenses(parsed_json)
      return [] if parsed_json.nil? || parsed_json.empty?
      return [] unless parsed_json['files']

      offenses = []
      parsed_json['files'].each do |file_data|
        next unless file_data['offenses']

        file_data['offenses'].each do |offense_data|
          offenses << _build_offense_hash(file_data['path'], offense_data)
        end
      end

      offenses
    end

    # Builds a structured offense hash from file and offense data.
    # @param file_path [String] Path to the file containing the offense.
    # @param offense_data [Hash] The offense data from Cookstyle output.
    # @return [Hash] Structured offense hash.
    private_class_method def self._build_offense_hash(file_path, offense_data)
      location = offense_data['location'] || {}

      {
        path: file_path,
        line: location['line'] || location['start_line'],
        column: location['column'] || location['start_column'],
        severity: offense_data['severity'],
        cop_name: offense_data['cop_name'],
        message: offense_data['message'],
        corrected: offense_data['corrected'] || false,
        correctable: offense_data['correctable'] || false
      }
    end
  end
end
