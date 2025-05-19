# typed: false
# frozen_string_literal: true

require 'simplecov'
SimpleCov.start do
  add_filter '/spec/'
  add_filter '/vendor/'
  enable_coverage :branch
end

require 'bundler/setup'
require 'sorbet-runtime'
require 'webmock/rspec'

# Load application code - ensure configuration is loaded first
require 'cookstyle_bot/configuration'
require 'cookstyle_bot'

# Ensure the main library is loaded for all specs
require File.expand_path('../lib/cookstyle_bot', __dir__)

RSpec.configure do |config|
  config.example_status_persistence_file_path = '.rspec_status'
  config.disable_monkey_patching!
  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.before(:suite) do
    CookstyleBot::Logging.logger.level = Logger::FATAL unless ENV['CI_DEBUG_LOGS']
    WebMock.disable_net_connect!(allow_localhost: true)
  end
end
