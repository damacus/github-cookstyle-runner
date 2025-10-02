# frozen_string_literal: true

require 'vcr'
require 'webmock/rspec'

VCR.configure do |c|
  # Where to store cassettes
  c.cassette_library_dir = 'spec/fixtures/vcr_cassettes'

  # Use webmock for HTTP stubbing
  c.hook_into :webmock

  # Integrate with RSpec metadata
  c.configure_rspec_metadata!

  # Filter sensitive data from cassettes
  c.filter_sensitive_data('<GITHUB_TOKEN>') { ENV.fetch('GITHUB_TOKEN', nil) }
  c.filter_sensitive_data('<GCR_GITHUB_TOKEN>') { ENV.fetch('GCR_GITHUB_TOKEN', nil) }
  c.filter_sensitive_data('<GITHUB_APP_ID>') { ENV.fetch('GCR_GITHUB_APP_ID', nil) }
  c.filter_sensitive_data('<GITHUB_APP_INSTALLATION_ID>') { ENV.fetch('GCR_GITHUB_APP_INSTALLATION_ID', nil) }
  c.filter_sensitive_data('<GITHUB_APP_PRIVATE_KEY>') do
    ENV['GCR_GITHUB_APP_PRIVATE_KEY']&.gsub("\n", '\n')
  end

  # Allow connections to localhost (for test servers)
  c.ignore_localhost = true

  # Allow real HTTP connections when no cassette is active (useful for recording)
  c.allow_http_connections_when_no_cassette = false

  # Default cassette options
  c.default_cassette_options = {
    record: :once,                    # Record new interactions once, then replay
    match_requests_on: %i[method uri body],
    allow_playback_repeats: true,
    serialize_with: :json,            # Use JSON for better readability
    decode_compressed_response: true  # Decode gzipped responses
  }

  # Debug mode (uncomment for troubleshooting)
  # c.debug_logger = File.open('vcr_debug.log', 'w')
end

# Configure WebMock
# Only allow localhost - VCR will handle GitHub API calls
WebMock.disable_net_connect!(allow_localhost: true)
