# frozen_string_literal: true
# typed: false

require 'spec_helper'
require 'cookstyle_runner/config_manager'
require 'cookstyle_runner/configuration'
require 'logger'

RSpec.describe CookstyleRunner::ConfigManager do
  let(:logger) { instance_double(Logger, error: nil, info: nil, debug: nil) }
  let(:required_env) do
    {
      'GITHUB_APP_ID' => '123',
      'GITHUB_APP_INSTALLATION_ID' => '456',
      'GITHUB_APP_PRIVATE_KEY' => 'test-key',
      'GCR_DESTINATION_REPO_OWNER' => 'test-owner'
    }
  end

  describe '.load_config' do
    # Legacy config methods - these will be deprecated in future
    context 'when required environment variables are missing' do
      it 'logs an error and exits if GITHUB_APP_ID is missing' do
        stub_const('ENV', required_env.except('GITHUB_APP_ID'))
        expect(logger).to receive(:error).with('GITHUB_APP_ID environment variable is required when GITHUB_TOKEN is not set')
        expect { described_class.load_config(logger) }.to raise_error(SystemExit)
      end

      it 'logs an error and exits if GITHUB_APP_INSTALLATION_ID is missing' do
        stub_const('ENV', required_env.except('GITHUB_APP_INSTALLATION_ID'))
        expect(logger).to receive(:error).with('GITHUB_APP_INSTALLATION_ID environment variable is required when GITHUB_TOKEN is not set')
        expect { described_class.load_config(logger) }.to raise_error(SystemExit)
      end

      it 'logs an error and exits if GITHUB_APP_PRIVATE_KEY is missing' do
        stub_const('ENV', required_env.except('GITHUB_APP_PRIVATE_KEY'))
        expect(logger).to receive(:error).with('GITHUB_APP_PRIVATE_KEY environment variable is required when GITHUB_TOKEN is not set')
        expect { described_class.load_config(logger) }.to raise_error(SystemExit)
      end

      it 'logs an error and exits if GCR_DESTINATION_REPO_OWNER is missing' do
        stub_const('ENV', required_env.except('GCR_DESTINATION_REPO_OWNER'))
        expect(logger).to receive(:error).with('GCR_DESTINATION_REPO_OWNER environment variable is required')
        expect { described_class.load_config(logger) }.to raise_error(SystemExit)
      end
    end

    context 'when all required variables are present' do
      before do
        stub_const('ENV', required_env)
      end

      it 'returns a hash with the required configuration values' do
        config = described_class.load_config(logger)
        expect(config[:owner]).to eq('sous-chefs')
        # Add checks for app_id, installation_id, private_key if they are stored in the config hash
        # Currently they are read directly but not returned in the hash
      end

      it 'returns default values for optional configuration' do
        config = described_class.load_config(logger)
        expect(config[:branch_name]).to eq('cookstyle-fixes')
        expect(config[:pr_title]).to eq('Automated PR: Cookstyle Changes')
        expect(config[:default_branch]).to eq('main')
        expect(config[:cache_dir]).to eq('/tmp/cookstyle-runner')
        expect(config[:use_cache]).to be true
        expect(config[:cache_max_age]).to eq(7)
        expect(config[:force_refresh]).to be false
        expect(config[:issue_labels]).to eq(['Skip: Announcements', 'Release: Patch', 'Cookstyle'])
        expect(config[:topics]).to be_nil
        expect(config[:include_repos]).to be_nil
      end
    end

    context 'when optional variables are set' do
      let(:optional_env) do
        {
          'GCR_BRANCH_NAME' => 'custom-branch',
          'GCR_PULL_REQUEST_TITLE' => 'My PR Title',
          'GCR_PR_LABELS' => 'label1, label2 ',
          'GCR_DEFAULT_BRANCH' => 'develop',
          'GCR_CACHE_DIR' => '/data/cache',
          'GCR_USE_CACHE' => '0',
          'GCR_CACHE_MAX_AGE' => '30',
          'GCR_FORCE_REFRESH' => '1',
          'GCR_DESTINATION_REPO_TOPICS' => ' topic-a, topic-b',
          'GCR_INCLUDE_REPOS' => ' repo3, repo4 '
        }
      end
      let(:full_env) { required_env.merge(optional_env) }

      before do
        stub_const('ENV', full_env)
      end

      it 'returns the specified values for optional configuration' do
        config = described_class.load_config(logger)
        expect(config[:branch_name]).to eq('custom-branch')
        expect(config[:pr_title]).to eq('My PR Title')
        expect(config[:issue_labels]).to eq(%w[label1 label2])
        expect(config[:default_branch]).to eq('develop')
        expect(config[:cache_dir]).to eq('/data/cache')
        expect(config[:use_cache]).to be false
        expect(config[:cache_max_age]).to eq(30)
        expect(config[:force_refresh]).to be true
        expect(config[:topics]).to eq(%w[topic-a topic-b])
        expect(config[:include_repos]).to eq(%w[repo3 repo4])
      end
    end
  end

  describe '.load_typed_config' do
    let(:config) { instance_double(CookstyleRunner::Configuration, log_summary: nil) }

    before do
      allow(CookstyleRunner::Configuration).to receive(:new).and_return(config)
    end

    it 'creates a new Configuration instance' do
      expect(CookstyleRunner::Configuration).to receive(:new).with(logger)
      described_class.load_typed_config(logger)
    end

    it 'logs that configuration was loaded successfully' do
      expect(logger).to receive(:info).with('Configuration loaded successfully')
      described_class.load_typed_config(logger)
    end

    it 'returns the Configuration instance' do
      result = described_class.load_typed_config(logger)
      expect(result).to eq(config)
    end
  end

  describe '.log_config_summary' do
    let(:hash_config) do
      {
        owner: 'sous-chefs',
        topics: %w[chef cookbook],
        branch_name: 'cookstyle-fixes',
        pr_title: 'Cookstyle Fixes',
        cache_max_age: 7
      }
    end
    let(:typed_config) { instance_double(CookstyleRunner::Configuration, log_summary: nil) }

    context 'when given a Hash configuration' do
      it 'logs the legacy configuration summary' do
        expect(logger).to receive(:info).with(/--- Configuration ---/)
        expect(logger).to receive(:info).with(/Destination Repo Owner: sous-chefs/)
        described_class.log_config_summary(hash_config, logger)
      end
    end

    context 'when given a Configuration object' do
      it 'delegates to the Configuration object log_summary method' do
        expect(typed_config).to receive(:log_summary).with(logger)
        described_class.log_config_summary(typed_config, logger)
      end
    end
  end

  # TODO: Add tests for .setup_logger
end
