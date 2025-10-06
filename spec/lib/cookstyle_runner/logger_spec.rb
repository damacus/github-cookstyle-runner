# frozen_string_literal: true

require 'spec_helper'
require 'json'
require 'tempfile'
require 'fileutils'

RSpec.describe CookstyleRunner::Logger do
  let(:log_output) { StringIO.new }
  let(:log_level) { Logger::INFO }

  describe '#initialize' do
    it 'creates a logger with default text format' do
      logger = described_class.new(log_output, level: log_level)
      expect(logger).to be_a(described_class)
    end

    it 'creates a logger with JSON format' do
      logger = described_class.new(log_output, level: log_level, format: :json)
      expect(logger).to be_a(described_class)
    end

    it 'accepts component filter' do
      logger = described_class.new(log_output, level: log_level, components: %w[git cache])
      expect(logger).to be_a(described_class)
    end
  end

  describe 'text format logging' do
    let(:logger) { described_class.new(log_output, level: log_level) }

    it 'logs info messages' do
      logger.info('Test message')
      expect(log_output.string).to include('INFO')
      expect(log_output.string).to include('Test message')
    end

    it 'logs error messages' do
      logger.error('Error occurred')
      expect(log_output.string).to include('ERROR')
      expect(log_output.string).to include('Error occurred')
    end

    it 'logs debug messages when level is DEBUG' do
      debug_logger = described_class.new(log_output, level: Logger::DEBUG)
      debug_logger.debug('Debug info')
      expect(log_output.string).to include('DEBUG')
      expect(log_output.string).to include('Debug info')
    end

    it 'does not log debug messages when level is INFO' do
      logger.debug('Debug info')
      expect(log_output.string).not_to include('Debug info')
    end
  end

  describe 'JSON format logging' do
    let(:logger) { described_class.new(log_output, level: log_level, format: :json) }

    it 'logs messages in JSON format' do
      logger.info('Test message')
      log_line = log_output.string.strip
      parsed = JSON.parse(log_line)

      expect(parsed['level']).to eq('INFO')
      expect(parsed['message']).to eq('Test message')
      expect(parsed['timestamp']).to be_a(String)
    end

    it 'includes component in JSON output' do
      logger.info('Test message', component: 'git')
      log_line = log_output.string.strip
      parsed = JSON.parse(log_line)

      expect(parsed['component']).to eq('git')
    end

    it 'includes additional context in JSON output' do
      logger.info('Test message', repo: 'test-repo', status: 'success')
      log_line = log_output.string.strip
      parsed = JSON.parse(log_line)

      expect(parsed['repo']).to eq('test-repo')
      expect(parsed['status']).to eq('success')
    end
  end

  describe 'component filtering' do
    let(:logger) { described_class.new(log_output, level: Logger::DEBUG, components: %w[git cache]) }

    it 'logs messages from enabled components' do
      logger.debug('Git operation', component: 'git')
      expect(log_output.string).to include('Git operation')
    end

    it 'filters out messages from disabled components' do
      logger.debug('API call', component: 'api')
      expect(log_output.string).to be_empty
    end

    it 'logs messages without component specification' do
      logger.info('General message')
      expect(log_output.string).to include('General message')
    end

    it 'logs error and warn messages regardless of component filter' do
      logger.error('Critical error', component: 'api')
      expect(log_output.string).to include('Critical error')
    end
  end

  describe '#with_context' do
    let(:logger) { described_class.new(log_output, level: log_level, format: :json) }

    it 'adds context to subsequent log messages' do
      logger.with_context(repo: 'test-repo') do
        logger.info('Processing')
      end

      log_line = log_output.string.strip
      parsed = JSON.parse(log_line)
      expect(parsed['repo']).to eq('test-repo')
    end

    it 'removes context after block execution' do
      logger.with_context(repo: 'test-repo') do
        logger.info('Inside context')
      end

      log_output.truncate(0)
      log_output.rewind
      logger.info('Outside context')

      log_line = log_output.string.strip
      parsed = JSON.parse(log_line)
      expect(parsed['repo']).to be_nil
    end
  end

  describe 'convenience methods' do
    let(:logger) { described_class.new(log_output, level: log_level) }

    it 'supports info level' do
      logger.info('Info message')
      expect(log_output.string).to include('INFO')
    end

    it 'supports warn level' do
      logger.warn('Warning message')
      expect(log_output.string).to include('WARN')
    end

    it 'supports error level' do
      logger.error('Error message')
      expect(log_output.string).to include('ERROR')
    end

    it 'supports debug level' do
      debug_logger = described_class.new(log_output, level: Logger::DEBUG)
      debug_logger.debug('Debug message')
      expect(log_output.string).to include('DEBUG')
    end

    it 'supports fatal level' do
      logger.fatal('Fatal message')
      expect(log_output.string).to include('FATAL')
    end
  end
end
