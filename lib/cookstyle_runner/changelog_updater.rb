# frozen_string_literal: true
# typed: true

require 'logger'
require_relative 'git' # Defines Git::RepoContext
require 'sorbet-runtime'

module CookstyleRunner
  # Module for updating Changelog files
  module ChangelogUpdater
    extend T::Sig

    # Update changelog with cookstyle fixes
    # rubocop:disable Metrics/MethodLength
    sig { params(context: Git::RepoContext, config: T::Hash[Symbol, T.untyped], offense_details: String).returns(T::Boolean) }
    def self.update_changelog(context, config, offense_details)
      changelog_path = File.join(context.repo_dir, config[:changelog_location])
      unless File.exist?(changelog_path)
        context.logger.warn("Changelog file not found at #{changelog_path}, skipping update.")
        return false
      end

      content = File.readlines(changelog_path)
      # Ensure config[:changelog_marker] is not nil before calling strip
      marker_value = T.let(config[:changelog_marker], T.nilable(String))
      return false unless marker_value # Or handle error appropriately if marker is mandatory

      marker_index = content.find_index { |line| line.strip.start_with?(marker_value.strip) }

      unless marker_index
        context.logger.warn("Changelog marker '#{marker_value}' not found in #{changelog_path}, skipping update.")
        return false
      end

      # Find the index of the next header (line starting with '## ') after the marker
      # T.must ensures marker_index is not nil here, which is guaranteed by the 'unless marker_index' check above.
      next_header_index = content.find_index.with_index do |line, idx|
        idx > T.must(marker_index) && line.strip.start_with?('## ')
      end

      # Determine insertion point
      # If no next header found, insert at the end. Otherwise, insert before the next header.
      insertion_point = next_header_index || content.length

      # Insert the offense details
      content.insert(insertion_point, "\n#{offense_details.strip}\n")

      File.write(changelog_path, content.join)
      context.logger.info("Updated changelog file: #{changelog_path}")
      true
    rescue StandardError => e
      context.logger.error("Failed to update changelog: #{e.message}")
      false
    end
    # rubocop:enable Metrics/MethodLength
  end
end
