# typed: false
# frozen_string_literal: true

require 'spec_helper'
require 'semantic_logger'
require 'stringio'

# rubocop:disable RSpec/DescribeClass
RSpec.describe 'SemanticLogger log level filtering' do
  let(:log_output) { StringIO.new }
  let(:test_class) do
    Class.new do
      def self.name
        'TestClass'
      end

      def self.log
        @log ||= SemanticLogger[self]
      end

      def self.log_at_all_levels
        log.trace('This is a TRACE message')
        log.debug('This is a DEBUG message')
        log.info('This is an INFO message')
        log.warn('This is a WARN message')
        log.error('This is an ERROR message')
        log.fatal('This is a FATAL message')
      end
    end
  end

  before do
    # Clear any existing appenders
    SemanticLogger.appenders.each(&:close)
    SemanticLogger.appenders.clear

    # Add a test appender
    SemanticLogger.add_appender(io: log_output, formatter: :color)
  end

  after do
    # Clean up
    SemanticLogger.appenders.each(&:close)
    SemanticLogger.appenders.clear
  end

  describe 'DEBUG level' do
    before { SemanticLogger.default_level = :debug }

    it 'shows DEBUG, INFO, WARN, ERROR, and FATAL messages' do
      test_class.log_at_all_levels
      SemanticLogger.flush

      output = log_output.string
      expect(output).to include('DEBUG message')
      expect(output).to include('INFO message')
      expect(output).to include('WARN message')
      expect(output).to include('ERROR message')
      expect(output).to include('FATAL message')
    end

    it 'does not show TRACE messages' do
      test_class.log_at_all_levels
      SemanticLogger.flush

      output = log_output.string
      expect(output).not_to include('TRACE message')
    end
  end

  describe 'INFO level' do
    before { SemanticLogger.default_level = :info }

    it 'shows INFO, WARN, ERROR, and FATAL messages' do
      test_class.log_at_all_levels
      SemanticLogger.flush

      output = log_output.string
      expect(output).to include('INFO message')
      expect(output).to include('WARN message')
      expect(output).to include('ERROR message')
      expect(output).to include('FATAL message')
    end

    it 'does not show DEBUG or TRACE messages' do
      test_class.log_at_all_levels
      SemanticLogger.flush

      output = log_output.string
      expect(output).not_to include('DEBUG message')
      expect(output).not_to include('TRACE message')
    end
  end

  describe 'WARN level' do
    before { SemanticLogger.default_level = :warn }

    it 'shows WARN, ERROR, and FATAL messages' do
      test_class.log_at_all_levels
      SemanticLogger.flush

      output = log_output.string
      expect(output).to include('WARN message')
      expect(output).to include('ERROR message')
      expect(output).to include('FATAL message')
    end

    it 'does not show INFO, DEBUG, or TRACE messages' do
      test_class.log_at_all_levels
      SemanticLogger.flush

      output = log_output.string
      expect(output).not_to include('INFO message')
      expect(output).not_to include('DEBUG message')
      expect(output).not_to include('TRACE message')
    end
  end

  describe 'ERROR level' do
    before { SemanticLogger.default_level = :error }

    it 'shows ERROR and FATAL messages' do
      test_class.log_at_all_levels
      SemanticLogger.flush

      output = log_output.string
      expect(output).to include('ERROR message')
      expect(output).to include('FATAL message')
    end

    it 'does not show WARN, INFO, DEBUG, or TRACE messages' do
      test_class.log_at_all_levels
      SemanticLogger.flush

      output = log_output.string
      expect(output).not_to include('WARN message')
      expect(output).not_to include('INFO message')
      expect(output).not_to include('DEBUG message')
      expect(output).not_to include('TRACE message')
    end
  end

  describe 'per-class log level override' do
    let(:debug_class) do
      Class.new do
        def self.name
          'DebugClass'
        end

        def self.log
          @log ||= begin
            logger = SemanticLogger[self]
            logger.level = :debug
            logger
          end
        end

        def self.log_messages
          log.debug('Debug from DebugClass')
          log.info('Info from DebugClass')
        end
      end
    end

    let(:info_class) do
      Class.new do
        def self.name
          'InfoClass'
        end

        def self.log
          @log ||= begin
            logger = SemanticLogger[self]
            logger.level = :info
            logger
          end
        end

        def self.log_messages
          log.debug('Debug from InfoClass')
          log.info('Info from InfoClass')
        end
      end
    end

    before { SemanticLogger.default_level = :warn }

    it 'allows per-class log level override' do
      debug_class.log_messages
      info_class.log_messages
      SemanticLogger.flush

      output = log_output.string

      # DebugClass should show both debug and info
      expect(output).to include('Debug from DebugClass')
      expect(output).to include('Info from DebugClass')

      # InfoClass should show only info (not debug)
      expect(output).not_to include('Debug from InfoClass')
      expect(output).to include('Info from InfoClass')
    end
  end
end
# rubocop:enable RSpec/DescribeClass
