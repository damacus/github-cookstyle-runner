#!/usr/bin/env ruby
# frozen_string_literal: true

require 'logger'
require 'tty-command'
require 'fileutils'
require 'json'

# Module for cookstyle operations
module CookstyleRunner
  module CookstyleOperations
    # Runs cookstyle, parses output, optionally runs auto-correction, and formats descriptions.
    # @param repo_dir [String] Repository directory
    # @param logger [Logger] Logger instance
    # @return [Array<Hash, Integer, Integer, String, String>]
    #   - Parsed JSON output from the initial run
    #   - Number of auto-correctable offenses found
    #   - Number of manually correctable (uncorrectable) offenses found
    #   - Formatted PR description (if applicable)
    #   - Formatted Issue description (if applicable)
    # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
    def self.run_cookstyle(repo_dir, logger)
      cmd = TTY::Command.new
      parsed_json = {}
      num_auto_correctable = 0
      num_manual_correctable = 0
      pr_description = ''
      issue_description = ''

      begin
        # 1. Run cookstyle to get JSON output
        result = cmd.run!('cookstyle --display-cop-names --format json', chdir: repo_dir, timeout: 300)
        parsed_json = JSON.parse(result.out)

        # 2. Count offenses
        num_auto_correctable = count_correctable_offences(parsed_json)
        num_manual_correctable = count_uncorrectable_offences(parsed_json)
        (num_auto_correctable + num_manual_correctable).positive?

        # 3. Format descriptions using the counts
        pr_description = format_pr_summary(num_auto_correctable + num_manual_correctable, num_auto_correctable) + \
                         format_pr_description(parsed_json, num_auto_correctable)

        issue_description = format_issue_summary(num_auto_correctable + num_manual_correctable, num_manual_correctable) + \
                            format_issue_description(parsed_json, num_manual_correctable)

        # 4. Run auto-correction if correctable offenses exist
        cmd.run!('cookstyle --auto-correct-all', chdir: repo_dir, timeout: 300) if num_auto_correctable.positive?

        # Return the initial state counts and descriptions
        [parsed_json, num_auto_correctable, num_manual_correctable, pr_description, issue_description]
      rescue JSON::ParserError => e
        logger.error("Failed to parse Cookstyle JSON output: #{e.message}")
        logger.error("Raw output:\n#{result&.out}") # Use safe navigation for result
        [parsed_json || {}, 0, 0, '', ''] # Return default empty/zero values
      rescue TTY::Command::ExitError => e
        logger.error("Cookstyle command failed: #{e.message}")
        logger.error("STDOUT:\n#{e.out}") unless e.out.empty?
        logger.error("STDERR:\n#{e.err}") unless e.err.empty?
        # Still return counts and descriptions derived from potentially partial JSON
        [parsed_json || {}, num_auto_correctable, num_manual_correctable, pr_description, issue_description]
      rescue StandardError => e
        logger.error("Unexpected error in run_cookstyle: #{e.message}")
        logger.debug(e.backtrace.join("\n"))
        [parsed_json || {}, 0, 0, '', ''] # Return default empty/zero values
      end
    end
    # rubocop:enable Metrics/MethodLength, Metrics/AbcSize

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
    # rubocop:enableMetrics/MethodLength

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
        # Extract only the first line of the message for brevity
        message_line = offense['message']&.lines&.first&.strip || 'No message'
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

      # for every offense, create a formatted description
      message = "\n\n### Offences\n\n"
      message += parsed_json['files']&.map do |file|
        file['offenses']&.map do |offense|
          "* #{file['path']}: #{offense['message']}"
        end
      end&.flatten&.join("\n")
      message
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

    # Format cookstyle output for an Issue description (when only manual fixes are needed)
    # @param parsed_json [Hash] Parsed JSON object from cookstyle run
    # @return [String] Formatted output for issue description
    def self.format_issue_description(parsed_json, num_manual_correctable)
      return '' if num_manual_correctable.zero?

      # for every offense that requires manual attention, create a formatted description
      message = "\n\n### Manual Intervention Required\n\n"
      manual_offenses = parsed_json['files']&.flat_map do |file|
        file['offenses']&.select { |offense| !offense['correctable'] }&.map do |offense|
          "* `#{file['path']}`: #{offense['cop_name']} - #{offense['message']&.lines&.first&.strip}"
        end
      end&.compact # Use flat_map and compact to handle nils
      message += manual_offenses.join("\n") unless manual_offenses.nil? || manual_offenses.empty?
      message
    end
  end
end
