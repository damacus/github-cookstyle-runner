# typed: strict
# frozen_string_literal: true

require 'sorbet-runtime'

require_relative 'cookstyle_bot/configuration'
require_relative 'cookstyle_bot/logging'
require_relative 'cookstyle_bot/version'
require_relative 'cookstyle_bot/runner'

module CookstyleBot
  extend T::Sig

  class Error < StandardError; end

  sig { returns(::Logger) }
  private_class_method def self.logger
    CookstyleBot::Logging.logger
  end

  # Sanitize settings by redacting sensitive information before logging
  # @return [Hash] Settings hash with sensitive values redacted
  sig { returns(T::Hash[T.untyped, T.untyped]) }
  private_class_method def self.sanitize_settings
    settings_hash = Settings.to_h

    # List of keys that might contain sensitive information
    sensitive_keys = %w[token password key secret credential auth]

    # Helper method to recursively sanitize nested hashes
    sanitize = lambda do |hash|
      hash.each_with_object({}) do |(k, v), result|
        result[k] = if sensitive_keys.any? { |sensitive| k.to_s.downcase.include?(sensitive) }
                      '[REDACTED]'
                    elsif v.is_a?(Hash)
                      sanitize.call(v)
                    else
                      v
                    end
      end
    end

    sanitize.call(settings_hash)
  end

  sig { void }
  def self.run
    logger.info("CookstyleBot version #{VERSION} starting...")
    logger.debug("Settings: #{sanitize_settings.inspect}")
    runner = Runner.new
    runner.run
    logger.info('CookstyleBot finished.')
  end
end
