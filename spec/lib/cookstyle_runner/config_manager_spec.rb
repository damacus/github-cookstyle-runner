# frozen_string_literal: true
# typed: false

require 'spec_helper'
require 'cookstyle_runner/config_manager'
require 'semantic_logger'

RSpec.describe CookstyleRunner::ConfigManager do
  let(:logger) { SemanticLogger['Test'] }
  let(:capture_logger) { SemanticLogger::Test::CaptureLogEvents.new }

  describe '.setup_logger' do
    it 'returns a SemanticLogger instance' do
      logger = described_class.setup_logger
      expect(logger).to respond_to(:info)
      expect(logger).to respond_to(:debug)
      expect(logger).to respond_to(:error)
    end

    it 'sets debug level when debug_mode is true' do
      described_class.setup_logger(debug_mode: true)
      expect(SemanticLogger.default_level).to eq(:debug)
    end
  end

  describe '.parse_log_level' do
    it 'parses valid log levels' do
      expect(described_class.parse_log_level('trace')).to eq(:trace)
      expect(described_class.parse_log_level('debug')).to eq(:debug)
      expect(described_class.parse_log_level('info')).to eq(:info)
      expect(described_class.parse_log_level('warn')).to eq(:warn)
      expect(described_class.parse_log_level('error')).to eq(:error)
      expect(described_class.parse_log_level('fatal')).to eq(:fatal)
    end

    it 'handles uppercase levels' do
      expect(described_class.parse_log_level('INFO')).to eq(:info)
      expect(described_class.parse_log_level('DEBUG')).to eq(:debug)
    end

    it 'returns :info for invalid levels' do
      expect(described_class.parse_log_level('invalid')).to eq(:info)
      expect(described_class.parse_log_level(nil)).to eq(:info)
      expect(described_class.parse_log_level('')).to eq(:info)
    end

    it 'handles symbol input' do
      expect(described_class.parse_log_level(:debug)).to eq(:debug)
    end
  end

  describe '.log_config_summary' do
    it 'logs configuration summary with structured data' do
      expect { described_class.log_config_summary }.not_to raise_error
    end

    context 'with structured logging' do
      it 'logs with structured payload data' do
        # Stub the logger to capture events
        allow(SemanticLogger).to receive(:[]).with(described_class).and_return(capture_logger)

        described_class.log_config_summary

        event = capture_logger.events.first
        expect(event.message).to eq('Configuration loaded')
        expect(event.level).to eq(:debug)
        expect(event.payload).to be_a(Hash)
      end

      it 'includes all configuration fields in payload' do
        allow(SemanticLogger).to receive(:[]).with(described_class).and_return(capture_logger)

        described_class.log_config_summary

        event = capture_logger.events.first
        expect(event.payload.keys).to include(
          :repo_owner, :topics, :branch_name, :pr_title, :issue_labels,
          :git_author, :default_branch, :cache, :processing
        )
      end

      it 'structures cache configuration as nested hash' do
        allow(SemanticLogger).to receive(:[]).with(described_class).and_return(capture_logger)

        described_class.log_config_summary

        event = capture_logger.events.first
        expect(event.payload[:cache]).to include(
          :dir, :enabled, :max_age_days, :force_refresh
        )
      end

      it 'structures processing configuration as nested hash' do
        allow(SemanticLogger).to receive(:[]).with(described_class).and_return(capture_logger)

        described_class.log_config_summary

        event = capture_logger.events.first
        expect(event.payload[:processing]).to include(
          :retry_count, :filter_repos, :create_manual_fix_issues
        )
      end
    end
  end

  describe '.setup_cache_directory' do
    let(:cache_dir) { '/tmp/test_cache' }

    after do
      FileUtils.rm_rf(cache_dir)
    end

    it 'creates the cache directory' do
      result = described_class.setup_cache_directory(cache_dir, logger)
      expect(result).to be true
      expect(File.directory?(cache_dir)).to be true
    end

    it 'returns false and logs error if directory creation fails' do
      allow(FileUtils).to receive(:mkdir_p).and_raise(StandardError, 'Permission denied')
      expect(logger).to receive(:error).with(a_string_including('Permission denied'))
      result = described_class.setup_cache_directory(cache_dir, logger)
      expect(result).to be false
    end
  end
end
