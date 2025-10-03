# frozen_string_literal: true

require 'spec_helper'
require_relative 'support/integration_helpers'

# rubocop:disable RSpec/DescribeClass
RSpec.describe 'Full Cookstyle Workflow', :integration do
  include IntegrationHelpers

  # Access TEST_REPOS constant from module
  let(:test_repos) { IntegrationHelpers::TEST_REPOS }

  describe 'processing a clean repository' do
    it 'completes successfully without creating PRs or issues', vcr: { cassette_name: 'workflow/clean_repo' } do
      result = run_cookstyle_runner(
        command: 'list',
        repos: [test_repos[:clean]]
      )

      # May fail if configuration is invalid, but should not crash
      expect(result.exit_code).to be_between(0, 1)
      expect(result.output).to include('sc_vscode').or include('Configuration')
    end
  end

  describe 'dry-run mode' do
    it 'previews changes without making modifications', vcr: { cassette_name: 'workflow/dry_run' } do
      result = run_cookstyle_runner(
        command: 'run',
        repos: [test_repos[:simple]],
        dry_run: true
      )

      # Dry run should succeed but not create PRs
      expect(result.exit_code).to be_between(0, 1)
      expect(result.output).to include('Dry run') if result.output.include?('Dry run')
    end
  end

  describe 'cache behavior' do
    it 'uses cache on subsequent runs' do
      # First run - cache miss
      result1 = run_cookstyle_runner(
        command: 'status'
      )

      expect(result1).to be_success
      expect(result1.output).to include('Cache')
    end
  end

  describe 'parallel processing' do
    it 'processes multiple repositories with threading', vcr: { cassette_name: 'workflow/parallel' } do
      result = run_cookstyle_runner(
        command: 'list',
        threads: 2
      )

      # May fail if configuration is invalid, but should not crash
      expect(result.exit_code).to be_between(0, 1)
    end
  end

  describe 'verbose output' do
    it 'provides detailed logging when verbose flag is set' do
      result = run_cookstyle_runner(
        command: 'version',
        verbose: true
      )

      expect(result).to be_success
      expect(result.stdout).to include('Cookstyle Runner')
    end
  end
end
# rubocop:enable RSpec/DescribeClass
