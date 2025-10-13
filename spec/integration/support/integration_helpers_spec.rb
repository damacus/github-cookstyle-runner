# typed: false
# frozen_string_literal: true

require 'spec_helper'
require_relative 'integration_helpers'

RSpec.describe IntegrationHelpers do
  include described_class

  describe '#strip_ansi' do
    it 'removes ANSI color codes from text' do
      colored_text = "\e[31mError\e[0m: \e[1mBold text\e[0m"
      expect(strip_ansi(colored_text)).to eq('Error: Bold text')
    end

    it 'handles text without ANSI codes' do
      plain_text = 'Plain text without colors'
      expect(strip_ansi(plain_text)).to eq('Plain text without colors')
    end

    it 'handles empty string' do
      expect(strip_ansi('')).to eq('')
    end

    it 'removes multiple ANSI sequences' do
      text = "\e[32m\e[1mGreen Bold\e[0m\e[0m Normal"
      expect(strip_ansi(text)).to eq('Green Bold Normal')
    end
  end

  describe '#numeric_value?' do
    it 'returns true for integer strings' do
      expect(numeric_value?('123')).to be true
    end

    it 'returns true for float strings' do
      expect(numeric_value?('123.45')).to be true
    end

    it 'returns true for percentage strings' do
      expect(numeric_value?('85%')).to be true
      expect(numeric_value?('12.5%')).to be true
    end

    it 'returns false for non-numeric strings' do
      expect(numeric_value?('abc')).to be false
      expect(numeric_value?('12abc')).to be false
      expect(numeric_value?('12.34.56')).to be false
    end

    it 'returns false for empty strings' do
      expect(numeric_value?('')).to be false
    end
  end

  describe '#parse_numeric' do
    it 'parses integer strings' do
      expect(parse_numeric('123')).to eq(123)
    end

    it 'parses float strings' do
      expect(parse_numeric('123.45')).to eq(123.45)
    end

    it 'removes percentage sign and parses as integer' do
      expect(parse_numeric('85%')).to eq(85)
    end

    it 'removes percentage sign and parses as float' do
      expect(parse_numeric('12.5%')).to eq(12.5)
    end
  end

  describe '#extract_cache_stats' do
    it 'extracts cache statistics from SemanticLogger formatted output' do
      output = <<~OUTPUT
        2025-10-13 16:00:00.123456 I [1234:5678] CookstyleRunner::Application -- Cache Statistics:
        2025-10-13 16:00:00.234567 I [1234:5678] CookstyleRunner::Application --   Total Repositories: 10
        2025-10-13 16:00:00.345678 I [1234:5678] CookstyleRunner::Application --   Cache Hits: 7
        2025-10-13 16:00:00.456789 I [1234:5678] CookstyleRunner::Application --   Cache Misses: 3
        2025-10-13 16:00:00.567890 I [1234:5678] CookstyleRunner::Application --   Hit Rate: 70%
      OUTPUT

      stats = extract_cache_stats(output)

      expect(stats[:total_repositories]).to eq(10)
      expect(stats[:cache_hits]).to eq(7)
      expect(stats[:cache_misses]).to eq(3)
      expect(stats[:hit_rate]).to eq(70)
    end

    it 'extracts cache statistics from output without SemanticLogger prefix' do
      output = <<~OUTPUT
        Cache Statistics:
          Total Repositories: 5
          Cache Hits: 4
          Cache Misses: 1
      OUTPUT

      stats = extract_cache_stats(output)

      expect(stats[:total_repositories]).to eq(5)
      expect(stats[:cache_hits]).to eq(4)
      expect(stats[:cache_misses]).to eq(1)
    end

    it 'extracts cache directory from output' do
      output = <<~OUTPUT
        2025-10-13 16:00:00.123456 I [1234:5678] CookstyleRunner::Application --   Cache Directory: /tmp/cache
      OUTPUT

      stats = extract_cache_stats(output)

      expect(stats[:cache_directory]).to eq('/tmp/cache')
    end

    it 'handles output with ANSI color codes' do
      output = "\e[32m2025-10-13 16:00:00.123456 I [1234:5678] CookstyleRunner::Application -- \e[0m  Total Repositories: 10"

      stats = extract_cache_stats(output)

      expect(stats[:total_repositories]).to eq(10)
    end

    it 'returns empty hash for output without statistics' do
      output = "Some random log output\nWith no statistics"

      stats = extract_cache_stats(output)

      expect(stats).to eq({})
    end

    it 'handles malformed output gracefully' do
      output = <<~OUTPUT
        Invalid line without colon
        Another: invalid: line: with: multiple: colons
        Valid Line: 123
      OUTPUT

      stats = extract_cache_stats(output)

      expect(stats[:valid_line]).to eq(123)
    end
  end

  describe '#extract_cache_directory' do
    it 'extracts cache directory from SemanticLogger formatted output' do
      output = <<~OUTPUT
        2025-10-13 16:00:00.123456 I [1234:5678] CookstyleRunner::Application -- Cache Statistics:
        2025-10-13 16:00:00.234567 I [1234:5678] CookstyleRunner::Application --   Cache Directory: /var/cache/cookstyle
      OUTPUT

      directory = extract_cache_directory(output)

      expect(directory).to eq('/var/cache/cookstyle')
    end

    it 'extracts cache directory from output without SemanticLogger prefix' do
      output = <<~OUTPUT
        Cache Statistics:
          Cache Directory: /tmp/test-cache
      OUTPUT

      directory = extract_cache_directory(output)

      expect(directory).to eq('/tmp/test-cache')
    end

    it 'handles cache directory without leading spaces' do
      output = 'Cache Directory: /home/user/cache'

      directory = extract_cache_directory(output)

      expect(directory).to eq('/home/user/cache')
    end

    it 'returns nil when cache directory is not found' do
      output = <<~OUTPUT
        Some log output
        Without cache directory
      OUTPUT

      directory = extract_cache_directory(output)

      expect(directory).to be_nil
    end

    it 'handles output with ANSI color codes' do
      output = "\e[32m2025-10-13 16:00:00.123456 I [1234:5678] CookstyleRunner::Application -- \e[0m  Cache Directory: /colored/path"

      directory = extract_cache_directory(output)

      expect(directory).to eq('/colored/path')
    end
  end
end
