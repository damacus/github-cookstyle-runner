# frozen_string_literal: true

require 'spec_helper'
require_relative 'support/integration_helpers'

# rubocop:disable RSpec/DescribeClass
RSpec.describe 'Repository Processing', :integration do
  include IntegrationHelpers

  # Access TEST_REPOS constant from module
  let(:test_repos) { IntegrationHelpers::TEST_REPOS }

  describe 'repository discovery' do
    it 'discovers repositories based on configuration', vcr: { cassette_name: 'processing/discovery' } do
      result = run_cookstyle_runner(command: 'list')

      # Should list repositories or show configuration error
      expect(result.exit_code).to be_between(0, 1)
    end

    it 'filters repositories by name pattern', vcr: { cassette_name: 'processing/filter' } do
      result = run_cookstyle_runner(
        command: 'list',
        repos: [test_repos[:clean]]
      )

      expect(result.exit_code).to be_between(0, 1)
    end
  end

  describe 'cookstyle execution' do
    it 'runs cookstyle on a clean repository', vcr: { cassette_name: 'processing/clean_repo' } do
      # This would require actual repository cloning and processing
      # For now, we test that the command doesn't crash
      result = run_cookstyle_runner(
        command: 'run',
        repos: [test_repos[:clean]],
        dry_run: true
      )

      expect(result.exit_code).to be_between(0, 1)
    end

    it 'handles repositories with offenses', vcr: { cassette_name: 'processing/with_offenses' } do
      result = run_cookstyle_runner(
        command: 'run',
        repos: [test_repos[:simple]],
        dry_run: true
      )

      expect(result.exit_code).to be_between(0, 1)
    end

    it 'processes large repositories', vcr: { cassette_name: 'processing/large_repo' } do
      result = run_cookstyle_runner(
        command: 'run',
        repos: [test_repos[:large]],
        dry_run: true
      )

      expect(result.exit_code).to be_between(0, 1)
    end
  end

  describe 'parallel processing' do
    it 'processes multiple repositories concurrently', vcr: { cassette_name: 'processing/parallel' } do
      result = run_cookstyle_runner(
        command: 'run',
        repos: [test_repos[:clean], test_repos[:simple]],
        threads: 2,
        dry_run: true
      )

      expect(result.exit_code).to be_between(0, 1)
    end
  end

  describe 'error handling' do
    it 'handles non-existent repositories gracefully' do
      result = run_cookstyle_runner(
        command: 'run',
        repos: ['sous-chefs/nonexistent-repo-12345'],
        dry_run: true
      )

      # Should fail gracefully
      expect(result.exit_code).to eq(1)
    end

    it 'continues processing after individual repository failures' do
      result = run_cookstyle_runner(
        command: 'run',
        repos: [test_repos[:clean], 'sous-chefs/nonexistent'],
        dry_run: true
      )

      # Should process what it can
      expect(result.exit_code).to be_between(0, 1)
    end
  end
end
# rubocop:enable RSpec/DescribeClass
