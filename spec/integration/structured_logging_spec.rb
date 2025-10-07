# typed: false
# frozen_string_literal: true

require 'spec_helper'
require_relative 'support/integration_helpers'

# rubocop:disable RSpec/DescribeClass
RSpec.describe 'Structured Logging Integration', :integration do
  include IntegrationHelpers

  context 'with JSON log format' do
    it 'outputs structured logs with SemanticLogger' do
      result = run_cookstyle_runner(command: 'list', format: 'json')

      # Should have SemanticLogger formatted log entries (timestamp, level, component)
      log_lines = result.output.lines.grep(/\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}/)
      expect(log_lines).not_to be_empty

      # Verify logs contain structured data (component, action)
      expect(result.output).to include('component:').or include('action:')
    end
  end

  context 'with color log format' do
    it 'outputs human-readable logs when format is color' do
      result = run_cookstyle_runner(command: 'list', format: 'color')

      # Should have timestamp and level indicators
      expect(result.output).to match(/\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}/)
      expect(result.output).to match(/\b(INFO|DEBUG|WARN|ERROR)\b/)
    end
  end

  context 'with backward compatibility' do
    it 'maps text format to color format' do
      result = run_cookstyle_runner(command: 'list', format: 'text')

      # Should output color format (human-readable)
      expect(result.output).to match(/\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}/)
    end
  end
end
# rubocop:enable RSpec/DescribeClass
