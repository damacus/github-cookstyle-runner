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

      log_output_io = case output_setting&.downcase
                      when 'stderr' then $stderr
                      when nil, 'stdout' then $stdout
                      else
                        # File path logic to be fully implemented later
                        $stdout # Default to stdout for now if path
                      end

      new_logger = ::Logger.new(log_output_io)
      new_logger.level = begin
        ::Logger.const_get(level_str)
      rescue StandardError
        ::Logger::INFO
      end
      new_logger.formatter = proc do |severity, datetime, progname, msg|
        "[#{datetime.strftime('%Y-%m-%d %H:%M:%S.%L')}] #{severity.ljust(5)} -- #{progname || 'CookstyleBot'}: #{msg}\n"
      end
      new_logger
    end
  end
end
