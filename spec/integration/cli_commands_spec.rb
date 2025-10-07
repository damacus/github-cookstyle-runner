# typed: false
# frozen_string_literal: true

require 'spec_helper'
require_relative 'support/integration_helpers'

# rubocop:disable RSpec/DescribeClass
RSpec.describe 'CLI Commands', :integration do
  include IntegrationHelpers

  describe 'version command' do
    it 'displays version information' do
      result = expect_successful_run(command: 'version')

      expect(result.stdout).to include('Cookstyle Runner')
      expect(result.stdout).to match(/v\d+\.\d+\.\d+/)
    end
  end

  describe 'help command' do
    it 'displays help information' do
      result = expect_successful_run(command: 'help')

      expect(result.stdout).to include('Usage: cookstyle-runner')
      expect(result.stdout).to include('Commands:')
    end
  end

  describe 'config command' do
    it 'displays configuration' do
      result = run_cookstyle_runner(command: 'config')

      # May fail if config is invalid, but should not crash
      expect(result.exit_code).to be_between(0, 1)
      expect(result.output).to include('Configuration')
    end
  end
end
# rubocop:enable RSpec/DescribeClass
