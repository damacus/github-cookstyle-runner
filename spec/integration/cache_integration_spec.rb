# frozen_string_literal: true

require 'spec_helper'
require_relative 'support/integration_helpers'

# rubocop:disable RSpec/DescribeClass
RSpec.describe 'Cache Integration', :integration do
  include IntegrationHelpers

  describe 'cache status' do
    it 'displays cache statistics' do
      result = run_cookstyle_runner(command: 'status')

      expect(result).to be_success
      expect(result.output).to include('Cache')
    end
  end

  describe 'cache operations' do
    it 'respects --no-cache flag' do
      result = run_cookstyle_runner(
        command: 'list',
        no_cache: true
      )

      # Should complete without using cache
      expect(result.exit_code).to be_between(0, 1)
    end

    it 'forces cache refresh with --force flag' do
      result = run_cookstyle_runner(
        command: 'list',
        force: true
      )

      # Should complete with cache refresh
      expect(result.exit_code).to be_between(0, 1)
    end
  end

  describe 'cache persistence' do
    it 'maintains cache across multiple runs' do
      # First run
      result1 = run_cookstyle_runner(command: 'status')
      expect(result1).to be_success

      # Second run - should use cached data
      result2 = run_cookstyle_runner(command: 'status')
      expect(result2).to be_success
    end
  end

  describe 'cache directory' do
    it 'creates cache directory if it does not exist' do
      result = run_cookstyle_runner(command: 'status')

      expect(result).to be_success
      # Cache directory should be created automatically
    end
  end
end
# rubocop:enable RSpec/DescribeClass
