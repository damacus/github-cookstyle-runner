# typed: false
# frozen_string_literal: true

require 'spec_helper'
require 'cookstyle_runner/settings_validator'
require 'logger'

RSpec.describe CookstyleRunner::SettingsValidator do
  let(:validator) { described_class.new }

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
      auto_assign_manual_fixes: true,
      copilot_assignee: 'copilot',
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

      it 'allows either github_app_id or github_token to be used for auth' do
        # App auth is provided by default
        result = validator.validate(default_valid_data)
        expect(result.success?).to be true

        # Token auth works too
        token_data = default_valid_data.dup
        token_data.delete(:github_app_id)
        token_data.delete(:github_app_installation_id)
        token_data.delete(:github_app_private_key)
        token_data[:github_token] = 'some-token'
        result = validator.validate(token_data)
        expect(result.success?).to be true
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

      it 'validates that use_cache is coercible to a boolean' do
        # Dry::Schema's Params processor coerces certain strings to booleans
        # 'yes', 'true', '1', etc. are coerced to true
        # Let's use a value that won't be coerced to test validation
        data = default_valid_data.merge(use_cache: 'not-a-boolean-value')
        result = validator.validate(data)
        expect(result.success?).to be false
        # Check that there is an error related to use_cache
        expect(result.errors.to_h.keys).to include(:use_cache)
      end

      it 'returns an error if topics is not an array of strings' do
        data = default_valid_data.merge(topics: 'chef,cookbook') # string instead of array
        result = validator.validate(data)
        expect(result.errors.to_h).to have_key(:topics)
        expect(result.errors.to_h[:topics]).to include('must be an array') # Or specific element error
      end

      it 'validates that topics array elements are strings' do
        data = default_valid_data.merge(topics: ['chef', 123]) # integer in array
        result = validator.validate(data)
        expect(result.success?).to be false
        # Just check that there's an error without expecting a specific format
        expect(result.errors.to_h.to_s).to match(/topics/i)
      end

      it 'returns an error for invalid log_level' do
        data = default_valid_data.merge(log_level: 'trace')
        result = validator.validate(data)
        expect(result.errors.to_h).to have_key(:log_level)
        expect(result.errors.to_h[:log_level]).to include('must be one of: debug, info, warn, error, fatal, unknown')
      end
    end

    # context 'with logging behavior' do
    #   it 'logs errors when validation fails' do
    #     data = default_valid_data.except(:owner) # Make it invalid
    #     validator.validate(data)
    #     expect(logger).to have_received(:error).with(/Validation failed:/)
    #     expect(logger).to have_received(:error).with(/- owner: is missing/)
    #   end

    #   it 'does not log errors when validation passes' do
    #     validator.validate(default_valid_data)
    #     expect(logger).not_to have_received(:error)
    #   end
    # end
  end
end
