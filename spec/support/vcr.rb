# frozen_string_literal: true

# VCR helpers
#
# Re-recording cassettes:
#   VCR_RECORD_MODE=all bundle exec rspec spec/integration
#
# Allow real HTTP traffic (dangerous outside of cassette recording):
#   VCR_ALLOW_HTTP=true bundle exec rspec spec/integration
#
# Enable VCR debug logging:
#   VCR_DEBUG=true bundle exec rspec spec/integration

require 'vcr'
require 'webmock/rspec'

module VCRSupport
  ALLOWED_RECORD_MODES = %w[once none new_episodes all].freeze

  module_function

  def record_mode
    raw_mode = ENV.fetch('VCR_RECORD_MODE', 'once').downcase
    symbolized = raw_mode.to_sym
    return symbolized if ALLOWED_RECORD_MODES.include?(raw_mode)

    warn "[VCR] Unknown record mode '#{raw_mode}', falling back to :once"
    :once
  end

  def allow_http_connections?
    ENV.fetch('VCR_ALLOW_HTTP', 'false').casecmp('true').zero?
  end

  def debug?
    ENV.fetch('VCR_DEBUG', 'false').casecmp('true').zero?
  end
end

VCR.configure do |c|
  # Where to store cassettes
  c.cassette_library_dir = 'spec/fixtures/vcr_cassettes'

  # Use webmock for HTTP stubbing
  c.hook_into :webmock

  # Integrate with RSpec metadata
  c.configure_rspec_metadata!

  # Filter sensitive data from cassettes
  # Only filter if the environment variable is actually set
  c.filter_sensitive_data('<GITHUB_TOKEN>') { ENV['GITHUB_TOKEN'] } if ENV['GITHUB_TOKEN']
  c.filter_sensitive_data('<GCR_GITHUB_TOKEN>') { ENV['GCR_GITHUB_TOKEN'] } if ENV['GCR_GITHUB_TOKEN']
  c.filter_sensitive_data('<GITHUB_APP_ID>') { ENV['GCR_GITHUB_APP_ID'] } if ENV['GCR_GITHUB_APP_ID']
  c.filter_sensitive_data('<GITHUB_APP_INSTALLATION_ID>') { ENV['GCR_GITHUB_APP_INSTALLATION_ID'] } if ENV['GCR_GITHUB_APP_INSTALLATION_ID']
  c.filter_sensitive_data('<GITHUB_APP_PRIVATE_KEY>') { ENV['GCR_GITHUB_APP_PRIVATE_KEY'].gsub("\n", '\\n') } if ENV['GCR_GITHUB_APP_PRIVATE_KEY']

  # Allow connections to localhost (for test servers)
  c.ignore_localhost = true

  # Allow real HTTP connections when no cassette is active (useful for recording)
  c.allow_http_connections_when_no_cassette = VCRSupport.allow_http_connections?

  # Default cassette options
  c.default_cassette_options = {
    record: VCRSupport.record_mode,   # Controlled via VCR_RECORD_MODE
    match_requests_on: %i[method uri body],
    allow_playback_repeats: true,
    serialize_with: :json,            # Use JSON for better readability
    decode_compressed_response: true  # Decode gzipped responses
  }

  c.debug_logger = File.open('tmp/vcr_debug.log', 'w') if VCRSupport.debug?
end

# Configure WebMock
if VCRSupport.allow_http_connections?
  WebMock.allow_net_connect!
else
  # Only allow localhost - VCR will handle GitHub API calls
  WebMock.disable_net_connect!(allow_localhost: true)
end

at_exit do
  next unless VCRSupport.debug?

  puts '[VCR] Debug log written to tmp/vcr_debug.log'
end
