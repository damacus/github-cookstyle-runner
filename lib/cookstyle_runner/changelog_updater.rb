# frozen_string_literal: true

# Module for handling changelog updates
module ChangelogUpdater
  # Update the changelog with a new entry
  # @param config [Hash] Configuration hash containing changelog location and marker
  # @param logger [Logger] Logger instance
  def self.update_changelog(config, logger)
    changelog_file = config[:changelog_location]
    marker = config[:changelog_marker]
    content = File.read(changelog_file)
    today = Time.now.strftime('%Y-%m-%d')

    return unless File.exist?(changelog_file)

    unless content.include?(marker)
      logger.warn("Changelog marker '#{marker}' not found in #{changelog_file}")
      return
    end

    logger.info("Updating changelog at #{changelog_file}")
    new_content = content.gsub(marker, "#{marker}\n- Cookstyle auto-corrections applied on #{today}")
    File.write(changelog_file, new_content)
    logger.info('Changelog updated successfully')
  rescue StandardError => e
    logger.error("Error updating changelog: #{e.message}")
  end
end
