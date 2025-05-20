# typed: strict
# frozen_string_literal: true

require 'logger'
require 'fileutils'
require 'sorbet-runtime'

module CookstyleBot
  module Logging
    extend T::Sig

    @logger = T.let(nil, T.nilable(::Logger))

    sig { returns(::Logger) }
    def self.logger
      @logger ||= setup_logger
    end

    sig { returns(::Logger) }
    def self.setup_logger
      settings = Settings.logging if Settings.respond_to?(:logging)
      level_str = T.let(settings&.level&.upcase || 'INFO', String)
      output_setting = T.let(settings&.output, T.nilable(String))

      # Determine output destination
      log_output_io = if output_setting&.downcase == 'stderr'
                        $stderr
                      else
                        # Default to stdout for nil, 'stdout', or file paths (to be implemented later)
                        $stdout
                      end

      new_logger = ::Logger.new(log_output_io)

      # Map log level strings to Logger constants
      log_levels = {
        'DEBUG' => ::Logger::DEBUG,
        'INFO' => ::Logger::INFO,
        'WARN' => ::Logger::WARN,
        'ERROR' => ::Logger::ERROR,
        'FATAL' => ::Logger::FATAL,
        'UNKNOWN' => ::Logger::UNKNOWN
      }

      new_logger.level = log_levels.fetch(level_str, ::Logger::INFO)
      new_logger.formatter = proc do |severity, datetime, progname, msg|
        "[#{datetime.strftime('%Y-%m-%d %H:%M:%S.%L')}] #{severity.ljust(5)} -- #{progname || 'CookstyleBot'}: #{msg}\n"
      end
      new_logger
    end
  end
end
