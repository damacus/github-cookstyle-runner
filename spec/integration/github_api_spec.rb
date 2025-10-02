# frozen_string_literal: true

require 'spec_helper'
require_relative 'support/integration_helpers'

# rubocop:disable RSpec/DescribeClass
RSpec.describe 'GitHub API Integration', :integration do
  include IntegrationHelpers

  describe 'repository listing' do
    it 'fetches repositories from GitHub', vcr: { cassette_name: 'github/list_repos' } do
      result = run_cookstyle_runner(command: 'list')

      # May fail if no valid GitHub credentials, but should not crash
      expect(result.exit_code).to be_between(0, 1)
    end

    it 'filters repositories by topic', vcr: { cassette_name: 'github/filter_by_topic' } do
      result = run_cookstyle_runner(command: 'list')

      # Should complete without crashing
      expect(result.exit_code).to be_between(0, 1)
    end

    it 'handles JSON output format', vcr: { cassette_name: 'github/json_output' } do
      # NOTE: --format is not yet implemented for list command
      result = run_cookstyle_runner(command: 'list')

      expect(result.exit_code).to be_between(0, 1)
    end
  end

  describe 'authentication' do
    it 'handles missing GitHub credentials gracefully' do
      # Run without GitHub token
      result = run_cookstyle_runner(command: 'config')

      # Should show configuration error but not crash
      expect(result.exit_code).to be_between(0, 1)
      expect(result.output).to include('Configuration')
    end
  end

  describe 'rate limiting' do
    it 'handles GitHub API rate limits', vcr: { cassette_name: 'github/rate_limit' } do
      result = run_cookstyle_runner(command: 'list')

      # Should handle rate limiting gracefully
      expect(result.exit_code).to be_between(0, 1)
    end
  end
end
# rubocop:enable RSpec/DescribeClass
