# frozen_string_literal: true
# typed: false

require 'spec_helper'
require 'cookstyle_runner/configuration_validator'

RSpec.describe CookstyleRunner::ConfigurationValidator do
  let(:logger) { instance_double(Logger, info: nil, warn: nil, error: nil) }
  let(:validator) { described_class.new(logger) }

  describe '#initialize' do
    it 'initializes with a logger' do
      expect(validator).to be_a(described_class)
    end
  end

  describe '#validate_required_env_vars' do
    context 'when required environment variables are present' do
      before do
        # Set up environment variables for testing
        allow(ENV).to receive(:fetch).with('GITHUB_TOKEN', nil).and_return('dummy_token')
        # For GitHub App auth
        allow(ENV).to receive(:fetch).with('GITHUB_APP_ID', nil).and_return(nil)
        allow(ENV).to receive(:fetch).with('GITHUB_APP_INSTALLATION_ID', nil).and_return(nil)
        allow(ENV).to receive(:fetch).with('GITHUB_APP_PRIVATE_KEY', nil).and_return(nil)
        # For repository owner
        allow(ENV).to receive(:fetch).with('GCR_DESTINATION_REPO_OWNER', nil).and_return('dummy_owner')
      end

      it 'does not raise an error' do
        expect { validator.validate_required_env_vars }.not_to raise_error
      end

      it 'logs success message' do
        expect(logger).to receive(:info).with('All required environment variables are present')
        validator.validate_required_env_vars
      end
    end

    context 'when GitHub token is missing but GitHub App credentials are present' do
      before do
        allow(ENV).to receive(:fetch).with('GITHUB_TOKEN', nil).and_return(nil)
        allow(ENV).to receive(:fetch).with('GITHUB_APP_ID', nil).and_return('12345')
        allow(ENV).to receive(:fetch).with('GITHUB_APP_INSTALLATION_ID', nil).and_return('67890')
        allow(ENV).to receive(:fetch).with('GITHUB_APP_PRIVATE_KEY', nil).and_return('dummy_key')
        allow(ENV).to receive(:fetch).with('GCR_DESTINATION_REPO_OWNER', nil).and_return('dummy_owner')
      end

      it 'does not raise an error' do
        expect { validator.validate_required_env_vars }.not_to raise_error
      end
    end

    context 'when all GitHub auth methods are missing' do
      before do
        allow(ENV).to receive(:fetch).with('GITHUB_TOKEN', nil).and_return(nil)
        allow(ENV).to receive(:fetch).with('GITHUB_APP_ID', nil).and_return(nil)
        allow(ENV).to receive(:fetch).with('GITHUB_APP_INSTALLATION_ID', nil).and_return(nil)
        allow(ENV).to receive(:fetch).with('GITHUB_APP_PRIVATE_KEY', nil).and_return(nil)
        allow(ENV).to receive(:fetch).with('GCR_DESTINATION_REPO_OWNER', nil).and_return('dummy_owner')
      end

      it 'raises ArgumentError' do
        expect { validator.validate_required_env_vars }.to raise_error(ArgumentError, /Either GITHUB_TOKEN or all GitHub App credentials/)
      end
    end

    context 'when only some GitHub App credentials are missing' do
      before do
        allow(ENV).to receive(:fetch).with('GITHUB_TOKEN', nil).and_return(nil)
        allow(ENV).to receive(:fetch).with('GITHUB_APP_ID', nil).and_return('12345')
        allow(ENV).to receive(:fetch).with('GITHUB_APP_INSTALLATION_ID', nil).and_return(nil) # Missing
        allow(ENV).to receive(:fetch).with('GITHUB_APP_PRIVATE_KEY', nil).and_return('dummy_key')
        allow(ENV).to receive(:fetch).with('GCR_DESTINATION_REPO_OWNER', nil).and_return('dummy_owner')
      end

      it 'raises ArgumentError' do
        expect { validator.validate_required_env_vars }.to raise_error(ArgumentError, /All three GitHub App credentials/)
      end
    end

    context 'when repository owner is missing' do
      before do
        allow(ENV).to receive(:fetch).with('GITHUB_TOKEN', nil).and_return('dummy_token')
        allow(ENV).to receive(:fetch).with('GITHUB_APP_ID', nil).and_return(nil)
        allow(ENV).to receive(:fetch).with('GITHUB_APP_INSTALLATION_ID', nil).and_return(nil)
        allow(ENV).to receive(:fetch).with('GITHUB_APP_PRIVATE_KEY', nil).and_return(nil)
        allow(ENV).to receive(:fetch).with('GCR_DESTINATION_REPO_OWNER', nil).and_return(nil)
      end

      it 'raises ArgumentError' do
        expect { validator.validate_required_env_vars }.to raise_error(ArgumentError, /GCR_DESTINATION_REPO_OWNER/)
      end
    end
  end

  describe '#validate_boolean_env_var' do
    it 'validates a boolean env var correctly' do
      expect(validator.validate_boolean_env_var('1')).to be true
      expect(validator.validate_boolean_env_var('0')).to be false
      expect(validator.validate_boolean_env_var('true')).to be true
      expect(validator.validate_boolean_env_var('false')).to be false
      expect(validator.validate_boolean_env_var('yes')).to be true
      expect(validator.validate_boolean_env_var('no')).to be false
    end

    it 'returns false for invalid values' do
      expect(validator.validate_boolean_env_var('invalid')).to be false
      expect(validator.validate_boolean_env_var('')).to be false
      expect(validator.validate_boolean_env_var(nil)).to be false
    end
  end

  describe '#validate_integer_env_var' do
    it 'validates an integer env var correctly' do
      expect(validator.validate_integer_env_var('123')).to eq(123)
      expect(validator.validate_integer_env_var('0')).to eq(0)
      expect(validator.validate_integer_env_var('-10')).to eq(-10)
    end

    it 'returns the default for invalid values' do
      expect(validator.validate_integer_env_var('invalid', 42)).to eq(42)
      expect(validator.validate_integer_env_var('', 42)).to eq(42)
      expect(validator.validate_integer_env_var(nil, 42)).to eq(42)
    end
  end
end
