# frozen_string_literal: true
# typed: true

require 'sorbet-runtime'
require 'table_tennis'

module CookstyleRunner
  # Renders data as pretty tables using the TableTennis gem
  class TableRenderer
    extend T::Sig

    # Render repositories as a pretty table
    # @param repositories [Array<String>] Array of repository URLs
    # @return [String] Formatted table output
    sig { params(repositories: T::Array[String]).returns(String) }
    def self.render_repositories(repositories)
      return 'No repositories found' if repositories.empty?

      # Convert repository URLs to table data
      table_data = repositories.map.with_index(1) do |repo, index|
        {
          '#' => index,
          'Repository' => File.basename(repo, '.git')
        }
      end

      TableTennis.new(table_data,
                      title: "Found #{repositories.length} repositories",
                      row_numbers: false,
                      zebra: true).to_s
    end

    # Render summary data as a pretty table
    # @param summary_data [Hash] Hash of summary statistics
    # @return [String] Formatted table output
    sig { params(summary_data: T::Hash[String, T.untyped]).returns(String) }
    def self.render_summary(summary_data)
      return 'No summary data' if summary_data.empty?

      table_data = summary_data.map do |key, value|
        {
          'Metric' => key,
          'Value' => value.to_s
        }
      end

      TableTennis.new(table_data,
                      title: 'Summary',
                      row_numbers: false,
                      zebra: true).to_s
    end

    # Render artifacts as a pretty table
    # @param artifacts [Array<Hash>] Array of artifact hashes
    # @return [String] Formatted table output
    sig { params(artifacts: T::Array[T::Hash[Symbol, T.untyped]]).returns(String) }
    def self.render_artifacts(artifacts)
      return 'No artifacts created' if artifacts.empty?

      table_data = artifacts.map do |artifact|
        {
          'Repository' => artifact[:repo],
          'Type' => artifact[:type],
          'Number' => "##{artifact[:number]}",
          'Title' => artifact[:title],
          'URL' => artifact[:url]
        }
      end

      TableTennis.new(table_data,
                      title: "Created Artifacts (#{artifacts.size})",
                      row_numbers: false,
                      zebra: true).to_s
    end
  end
end
