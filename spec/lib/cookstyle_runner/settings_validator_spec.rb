# frozen_string_literal: true

require 'spec_helper'
require 'cookstyle_runner/settings_validator'
require 'logger'

RSpec.describe CookstyleRunner::SettingsValidator do
  let(:logger) { instance_double(Logger, error: nil, warn: nil, info: nil, debug: nil) }
  let(:validator) { described_class.new(logger) }

  let(:default_valid_data) do
    {
      owner: 'test-org',
      destination_repo_owner: 'dest-org',
      github_app_id: '12345',
      github_app_installation_id: '67890',
      github_app_private_key: "-----BEGIN RSA PRIVATE KEY-----\nMIIEogIBAAKCAQEAl...\n-----END RSA PRIVATE KEY-----",
      cache_max_age: 7,
      use_cache: true,
      force_refresh: false,
      create_manual_fix_issues: true,
      branch_name: 'cookstyle-fixes',
      pr_title: 'Automated Cookstyle Fixes',
      default_branch: 'main',
      git_name: 'Cookstyle Runner',
      git_email: 'runner@example.com',
      github_api_endpoint: 'https://api.github.com',
      cache_dir: '/tmp/cache',
      log_level: 'info'
      # Optional fields can be added here for specific tests
    }
  end

  describe '#validate' do
    context 'with valid data' do
      it 'returns an empty error hash when all required fields are present and correct' do
        result = validator.validate(default_valid_data)
        expect(result.errors.to_h).to be_empty
      end

      it 'passes when github_token is provided instead of app auth' do
        data = default_valid_data.dup
        data.delete(:github_app_id)
        data.delete(:github_app_installation_id)
        data.delete(:github_app_private_key)
        data[:github_token] = 'a-valid-token'
        result = validator.validate(data)
        expect(result.errors.to_h).to be_empty
      end

      it 'passes with valid optional fields' do
        data = default_valid_data.merge(
          topics: %w[chef cookbook],
          issue_labels: %w[bug cookstyle],
          processing_retry_count: 5
        )
        result = validator.validate(data)
        expect(result.errors.to_h).to be_empty
      end
    end

    context 'with missing required fields' do
      it 'returns an error if owner is missing' do
        data = default_valid_data.except(:owner)
        result = validator.validate(data)
        expect(result.errors.to_h).to have_key(:owner)
        expect(result.errors.to_h[:owner]).to include('is missing')
      end

      it 'returns an error if destination_repo_owner is missing' do
        data = default_valid_data.except(:destination_repo_owner)
        result = validator.validate(data)
        expect(result.errors.to_h).to have_key(:destination_repo_owner)
        expect(result.errors.to_h[:destination_repo_owner]).to include('is missing')
      end

      it 'returns an error if github_app_id is missing and no github_token' do
        data = default_valid_data.except(:github_app_id)
        result = validator.validate(data)
        expect(result.errors.to_h).to have_key(:github_app_id)
        expect(result.errors.to_h[:github_app_id]).to include('is missing (and github_token is not set)')
      end
    end

    context 'with incorrect types or constraints' do
      it 'returns an error if cache_max_age is not an integer' do
        data = default_valid_data.merge(cache_max_age: 'seven')
        result = validator.validate(data)
        expect(result.errors.to_h).to have_key(:cache_max_age)
        expect(result.errors.to_h[:cache_max_age]).to include('must be an integer')
      end

      it 'returns an error if cache_max_age is less than 1' do
        data = default_valid_data.merge(cache_max_age: 0)
        result = validator.validate(data)
        expect(result.errors.to_h).to have_key(:cache_max_age)
        expect(result.errors.to_h[:cache_max_age]).to include('must be greater than 0')
      end

      it 'returns an error if use_cache is not a boolean' do
        data = default_valid_data.merge(use_cache: 'yes')
        result = validator.validate(data)
        expect(result.errors.to_h).to have_key(:use_cache)
        expect(result.errors.to_h[:use_cache]).to include('must be boolean')
      end

      it 'returns an error if topics is not an array of strings' do
        data = default_valid_data.merge(topics: 'chef,cookbook') # string instead of array
        result = validator.validate(data)
        expect(result.errors.to_h).to have_key(:topics)
        expect(result.errors.to_h[:topics]).to include('must be an array') # Or specific element error
      end

      it 'returns an error if an element in topics is not a string' do
        data = default_valid_data.merge(topics: ['chef', 123]) # integer in array
        result = validator.validate(data)
        expect(result.errors.to_h).to have_key(:topics)
        # This might be reported as `topics[1] must be a string` or a general message
        expect(result.errors.to_h[:topics].join).to match(/must be a string/i).or match(/violates constraints/)
      end

      it 'returns an error for invalid log_level' do
        data = default_valid_data.merge(log_level: 'trace')
        result = validator.validate(data)
        expect(result.errors.to_h).to have_key(:log_level)
        expect(result.errors.to_h[:log_level]).to include('must be one of: debug, info, warn, error, fatal, unknown')
      end
    end

    context 'with logging behavior' do
      it 'logs errors when validation fails' do
        data = default_valid_data.except(:owner) # Make it invalid
        validator.validate(data)
        expect(logger).to have_received(:error).with(/Validation failed:/)
        expect(logger).to have_received(:error).with(/- owner: is missing/)
      end

      it 'does not log errors when validation passes' do
        validator.validate(default_valid_data)
        expect(logger).not_to have_received(:error)
      end
    end
  end
end
