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

  sig { void }
  def self.run
    logger.info("CookstyleBot version #{VERSION} starting...")
    logger.debug("Settings: #{Settings.to_h.inspect}")
    # Main logic will be added here
    logger.info('CookstyleBot finished.')
  end
end
