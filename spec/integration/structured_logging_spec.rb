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

      # Should have JSON formatted log entries with timestamp, level, message
      log_lines = result.output.lines.grep(/"timestamp":/)
      expect(log_lines).not_to be_empty

      # Verify logs contain structured JSON data
      expect(result.output).to include('"level":').and include('"message":')
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
