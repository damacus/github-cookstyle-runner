# typed: false
# frozen_string_literal: true

require 'spec_helper'
require 'cookstyle_bot/configuration'

RSpec.describe CookstyleBot::Configuration do
  describe 'integration with actual settings' do
    # Use around hook to manage environment variables
    around do |example|
      # Save original environment variables
      original_env = {}
      # Define environment variables to save/restore
      env_keys = %w[
        APP_ENV
        GCR__GITHUB__TOKEN
        GCR__GITHUB__DESTINATION_REPO_OWNER
        GCR__GITHUB__DESTINATION_REPO_TOPICS_CSV
      ]

      env_keys.each do |key|
        original_env[key] = ENV.fetch(key, nil)
      end

      example.run

      # Restore original environment variables
      original_env.each do |key, value|
        ENV[key] = value
      end
    end

    context 'with valid configuration' do
      before do
        # Set environment variables
        ENV['APP_ENV'] = 'test'
        ENV['GCR__GITHUB__TOKEN'] = 'test_token'
        ENV['GCR__GITHUB__DESTINATION_REPO_OWNER'] = 'test_owner'
        ENV['GCR__GITHUB__DESTINATION_REPO_TOPICS_CSV'] = 'chef,cookbook'

        # Reload configuration
        config_root = File.expand_path('../../../config', __dir__)
        Config.load_and_set_settings(Config.setting_files(config_root, ENV.fetch('APP_ENV', nil)))

        # Directly set the values in the Settings object to ensure they're available
        Settings.github.token = 'test_token'
        Settings.github.destination_repo_owner = 'test_owner'
        Settings.github.destination_repo_topics_csv = 'chef,cookbook'
      end

      it 'validates successfully' do
        expect { described_class.validate! }.not_to raise_error
      end

      it 'provides typed accessors for common settings' do
        expect(described_class.github_token).to eq('test_token')
      end

      it 'returns correct the correct default GitHub API endpoint' do
        expect(described_class.github_api_root).to eq('api.github.com')
      end

      it 'returns correct the correct default log level' do
        expect(described_class.log_level).to eq('INFO')
      end
    end

    context 'with invalid configuration' do
      before do
        ENV['APP_ENV'] = 'test'
        ENV['GCR__GITHUB__TOKEN'] = nil # Missing required token
        ENV['GCR__GITHUB__DESTINATION_REPO_OWNER'] = 'test_owner'
        ENV['GCR__GITHUB__DESTINATION_REPO_TOPICS_CSV'] = 'chef,cookbook'
        ENV['GCR__LOGGING__LEVEL'] = 'INVALID_LEVEL' # Invalid log level

        # Reload configuration
        config_root = File.expand_path('../../../config', __dir__)
        Config.load_and_set_settings(Config.setting_files(config_root, ENV.fetch('APP_ENV', nil)))
      end

      it 'detects validation errors' do
        expect(described_class.validation_errors).not_to be_empty
      end

      it 'returns false when configuration is invalid' do
        expect(described_class.valid?).to be false
      end

      it 'raises exception on validate!' do
        expect { described_class.validate! }.to raise_error(CookstyleBot::ConfigurationError)
      end
    end
  end
end
