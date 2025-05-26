# frozen_string_literal: true

require 'spec_helper'
require 'cookstyle_runner/configuration'
require 'logger'

RSpec.describe CookstyleRunner::Configuration do
  subject(:config_instance) { described_class.new(logger) }

  let(:logger) { instance_double(Logger, info: nil, warn: nil, error: nil, debug: nil, fatal: nil) }

  # Load expected values from test.yml
  let(:test_config_values) do
    YAML.safe_load_file(File.expand_path('../../../config/settings/test.yml', __dir__))
  end

  # Setup and teardown for environment variables
  around do |example|
    # Store original environment
    original_env = ENV.fetch('COOKSTYLE_ENV', nil)
    env_vars_to_manage = %w[
      GITHUB_TOKEN APP_ID INSTALLATION_ID GITHUB_APP_PRIVATE_KEY
      GCR_GITHUB_TOKEN GCR_APP_ID GCR_INSTALLATION_ID GCR_GITHUB_APP_PRIVATE_KEY
      GCR_GITHUB_API_ENDPOINT GCR_OWNER GCR_TOPICS GCR_FILTER_REPOS
      GCR_BRANCH_NAME GCR_PR_TITLE GCR_ISSUE_LABELS GCR_DEFAULT_BRANCH GCR_GIT_NAME GCR_GIT_EMAIL
      GCR_CACHE_DIR GCR_USE_CACHE GCR_CACHE_MAX_AGE GCR_FORCE_REFRESH GCR_MANAGE_CHANGELOG
      GCR_CHANGELOG_LOCATION GCR_CHANGELOG_MARKER GCR_RETRY_COUNT GCR_THREAD_COUNT
      GCR_CREATE_MANUAL_FIX_ISSUES
    ]

    # Backup original values
    original_env_values = env_vars_to_manage.to_h { |k| [k, ENV.fetch(k, nil)] }

    # Clear environment variables for clean test
    env_vars_to_manage.each { |k| ENV.delete(k) }

    # Set test environment
    ENV['COOKSTYLE_ENV'] = 'test'

    # Make sure Settings are reloaded
    Object.const_get('ConfigGem').reload! if Object.const_defined?('ConfigGem')

    example.run
  ensure
    # Restore environment
    ENV['COOKSTYLE_ENV'] = original_env
    env_vars_to_manage.each { |k| ENV.delete(k) }
    original_env_values.each { |k, v| ENV[k] = v if v }

    # Reset Settings
    Object.const_get('ConfigGem').reload! if Object.const_defined?('ConfigGem')
  end

  describe '#initialize' do
    it 'initializes with a logger' do
      expect(config_instance).to be_a(described_class)
    end

    it 'logs an info message on successful validation' do
      allow(logger).to receive(:info)
      config_instance
      expect(logger).to have_received(:info).with('Configuration loaded and validated successfully.')
    end

    context 'when validation fails' do
      let(:sample_failure_messages) do
        ['owner: is missing',
         'Authentication: Either github_token OR (github_app_id AND github_app_installation_id AND github_app_private_key) must be provided']
      end

      before do
        allow(CookstyleRunner::SettingsValidator).to receive(:validate).and_return(sample_failure_messages)
      end

      it 'logs the validation errors' do
        allow(logger).to receive(:error)
        expect { config_instance }.to raise_error(ArgumentError, /Configuration validation failed/)
        expect(logger).to have_received(:error).with(/Configuration validation failed/)
      end
    end
  end

  describe 'configuration values' do
    it 'provides correct values from test.yml' do
      expect(config_instance.owner).to eq('test-owner')
      expect(config_instance.github_token).to eq('test_token')
      expect(config_instance.github_api_endpoint).to eq('https://api.github.com')
      expect(config_instance.branch_name).to eq('test-cookstyle-fixes')
      expect(config_instance.cache_max_age).to eq(7)
    end

    it 'correctly handles array values' do
      expect(config_instance.topics).to be_an(Array)
      expect(config_instance.topics).to include('test-topic')
      expect(config_instance.issue_labels).to include('TestLabel', 'Cookstyle')
    end
  end

  describe '#to_h' do
    it 'returns a hash with all configuration attributes' do
      hash = config_instance.to_h

      expect(hash).to be_a(Hash)
      expect(hash.keys).to match_array(CookstyleRunner::Configuration::CONFIG_ATTRIBUTES)
      expect(hash[:owner]).to eq('test-owner')
      expect(hash[:github_token]).to eq('test_token')
      expect(hash[:cache_max_age]).to eq(7)
    end
  end

  describe 'environment variable overrides' do
    before do
      ENV['GCR_GITHUB_TOKEN'] = 'env-override-token'
      ENV['GCR_OWNER'] = 'env-override-owner'
      ENV['GCR_CACHE_MAX_AGE'] = '42'
      Object.const_get('ConfigGem').reload! if Object.const_defined?('ConfigGem')
    end

    it 'uses values from environment variables when set' do
      config = described_class.new(logger)

      expect(config.github_token).to eq('env-override-token')
      expect(config.owner).to eq('env-override-owner')
      expect(config.cache_max_age).to eq(42)
    end

    it 'supports direct environment variables via aliasing' do
      ENV.delete('GCR_GITHUB_TOKEN')
      ENV['GITHUB_TOKEN'] = 'direct-token-override'
      Object.const_get('ConfigGem').reload! if Object.const_defined?('ConfigGem')

      config = described_class.new(logger)
      expect(config.github_token).to eq('direct-token-override')
    end
  end
end
