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
  # Removed describe '.load_config' block as it tests legacy hash-based configuration

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
    let(:typed_config) { instance_double(CookstyleRunner::Configuration, log_summary: nil) }
    # Removed hash_config let block and context for Hash configuration as it's legacy

    context 'when given a Configuration object' do
      it 'delegates to the Configuration object log_summary method' do
        expect(typed_config).to have_received(:log_summary).with(logger)
        described_class.log_config_summary(typed_config, logger)
      end
    end
  end

  # TODO: Add tests for .setup_logger
end
