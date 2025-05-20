# typed: false
# frozen_string_literal: true

require 'spec_helper'
require 'cookstyle_bot/configuration_validator'

RSpec.describe CookstyleBot::ConfigurationValidator do
  let(:validator) { described_class.new }
  let(:settings_double) { instance_double(Config::Options) }

  before do
    # Create a minimal valid configuration for testing
    allow(Settings).to receive(:to_hash).and_return(
      {
        logging: {
          level: 'INFO',
          output: 'stdout'
        },
        github: {
          api_root: 'api.github.com',
          token: 'test_token',
          destination_repo_owner: 'test_owner',
          destination_repo_topics_csv: 'chef,cookbook',
          branch_name: 'cookstyle-updates',
          default_git_branch: 'main',
          pull_request: {
            title: 'Cookstyle Automated Fixes',
            labels: 'cookstyle,automated',
            body_header: 'Test header',
            body_topic_template: 'Test template %<topics>s'
          }
        },
        git: {
          name: 'Cookstyle Bot',
          email: 'cookstyle-bot@example.com'
        },
        changelog: {
          location: 'CHANGELOG.md',
          marker: '## Unreleased',
          manage: false
        },
        cookstyle: {
          version_check_regex: 'cookstyle.*'
        }
      }
    )

    # rubocop:disable RSpec/MessageChain
    # Mock Settings object for specific checks
    allow(Settings).to receive_message_chain(:changelog, :manage).and_return(false)
    allow(Settings).to receive_message_chain(:changelog, :location).and_return('CHANGELOG.md')
    allow(Settings).to receive_message_chain(:changelog, :marker).and_return('## Unreleased')
    # rubocop:enable RSpec/MessageChain
  end

  describe '#valid?' do
    it 'returns true when configuration is valid' do
      expect(validator.valid?).to be true
    end
  end

  describe 'when configuration is invalid' do
    # rubocop:disable RSpec/ExampleLength
    it 'returns a correct error message when a required section is missing' do
      allow(Settings).to receive(:to_hash).and_return(
        {
          logging: {
            level: 'INFO'
            # output is missing
          }
          # Missing required github section
        }
      )
      expect(validator.errors).to include('Missing or invalid section: github')
    end
  end

  describe 'an incorrect logging level' do
    it 'returns a correct error message when field has incorrect type' do
      allow(Settings).to receive(:to_hash).and_return(
        {
          logging: {
            level: 123, # Should be a string
            output: 'stdout'
          }
        }
      )
      expect(validator.errors).to include(/logging\.level must be a string/)
    end

    it 'returns a correct error message when field has invalid value' do
      allow(Settings).to receive(:to_hash).and_return(
        {
          logging: {
            level: 'INVALID_LEVEL', # Not in allowed values
            output: 'stdout'
          }
        }
      )
      expect(validator.errors).to include(/logging\.level must be one of: DEBUG, INFO, WARN, ERROR, FATAL/)
    end
    # rubocop:enable RSpec/ExampleLength
  end

  describe '#validate!' do
    it 'does not raise error when configuration is valid' do
      expect { validator.validate! }.not_to raise_error
    end

    it 'raises ConfigurationError when configuration is invalid' do
      allow(Settings).to receive(:to_hash).and_return({ logging: {} })
      expect { validator.validate! }.to raise_error(CookstyleBot::ConfigurationError)
    end
  end

  describe 'combination validations' do
    it 'validates changelog combinations' do
      # When changelog.manage is true, location and marker must be set
      # rubocop:disable RSpec/MessageChain
      allow(Settings).to receive_message_chain(:changelog, :manage).and_return(true)
      allow(Settings).to receive_message_chain(:changelog, :location).and_return('')
      # rubocop:enable RSpec/MessageChain

      expect(validator.errors).to include(/When changelog\.manage is true/)
    end
  end
end
