# frozen_string_literal: true
# typed: false

require 'spec_helper'
require 'cookstyle_runner/config_manager'
require 'logger'

RSpec.describe CookstyleRunner::ConfigManager do
  let(:logger) { instance_double(Logger, info: nil, error: nil, debug: nil) }

  describe '.setup_logger' do
    it 'creates a logger with INFO level by default' do
      logger = described_class.setup_logger
      expect(logger).to be_a(Logger)
      expect(logger.level).to eq(Logger::INFO)
    end

    it 'creates a logger with DEBUG level when debug_mode is true' do
      logger = described_class.setup_logger(debug_mode: true)
      expect(logger).to be_a(Logger)
      expect(logger.level).to eq(Logger::DEBUG)
    end
  end

  describe '.log_config_summary' do
    it 'logs configuration summary' do
      expect(logger).to receive(:info).with(a_string_including('Configuration'))
      described_class.log_config_summary(logger)
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
