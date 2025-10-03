# frozen_string_literal: true

require 'spec_helper'
require_relative 'support/integration_helpers'

# rubocop:disable RSpec/DescribeClass
RSpec.describe 'Cache Integration', :integration do
  include IntegrationHelpers

  describe 'cache status' do
    it 'displays cache statistics' do
      result = expect_successful_run(command: 'status')
      stats = extract_cache_stats(result.output)

      aggregate_failures do
        expect(stats).to include(:cache_directory)
        expect(stats).to include(:cache_hits, :cache_misses, :cache_updates, :cache_hit_rate)
        expect(stats[:cache_hits]).to be >= 0
        expect(stats[:cache_misses]).to be >= 0
        expect(stats[:cache_updates]).to be >= 0
        expect(stats[:cache_hit_rate]).to be_a(Numeric)
      end
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
      result1 = expect_successful_run(command: 'status')
      stats1 = extract_cache_stats(result1.output)
      cache_dir = extract_cache_directory(result1.output)
      expect(cache_dir).not_to be_nil

      # Second run - should use cached data
      result2 = expect_successful_run(command: 'status')
      stats2 = extract_cache_stats(result2.output)
      expect(extract_cache_directory(result2.output)).to eq(cache_dir)
      expect(stats2[:cache_hit_rate]).to be >= stats1[:cache_hit_rate]
    end
  end

  describe 'cache directory' do
    it 'creates cache directory if it does not exist' do
      result = expect_successful_run(command: 'status')

      expect(extract_cache_directory(result.output)).not_to be_nil
    end
  end
end
# rubocop:enable RSpec/DescribeClass
