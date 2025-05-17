# frozen_string_literal: true

require 'spec_helper'
require 'tempfile'
require 'fileutils'

# This is the class under test. Using a let block for easier reference.
# The actual class is CookstyleRunner::Configuration but the top RSpec.describe is 'Configuration'
# which means described_class might not resolve as expected in all contexts.
# Using an explicit reference is safer.

# Mock for the logger
# Mock for ConfigurationValidator
# Mock for ConfigurationFormatter (though largely deprecated, some old tests might reference it before cleanup)
# Paths to fixture files

RSpec.describe 'Configuration' do
  let(:configuration_class) { CookstyleRunner::Configuration }
  let(:logger) { instance_double(Logger, info: nil, warn: nil, error: nil, debug: nil) }
  let(:validator) do
    instance_double(CookstyleRunner::ConfigurationValidator, validate_required_env_vars: nil, validate: {})
  end
  let(:formatter) { instance_double(CookstyleRunner::ConfigurationFormatter, log_summary: nil) } # For existing tests if any

  let(:default_config_path) { File.expand_path('../../fixtures/_default_configuration.yml', __dir__) }
  let(:override_config_path) { File.expand_path('../../fixtures/override-1.yml', __dir__) }

  describe 'default settings' do
    it 'loads default settings correctly' do
      # Test that key settings are loaded with correct default values
      # Access Settings constant safely
      settings = Object.const_get('Settings')
      expect(settings.owner).to eq('sous-chefs')
      expect(settings.topics).to eq(%w[chef cookbook])
      expect(settings.branch_name).to eq('cookstyle-fixes')
      expect(settings.pr_title).to eq('Automated PR: Cookstyle Changes')
      expect(settings.cache_max_age).to eq(7)
      expect(settings.create_manual_fix_issues).to eq(true)
    end
  end

  describe 'environment variable overrides' do
    around do |example|
      # Store original environment variables
      original_values = {
        'GCR_CACHE_MAX_AGE' => ENV.fetch('GCR_CACHE_MAX_AGE', nil),
        'GCR_OWNER' => ENV.fetch('GCR_OWNER', nil)
      }

      # Set test values
      ENV['GCR_CACHE_MAX_AGE'] = '14'
      ENV['GCR_OWNER'] = 'custom-owner'

      # Reload config to pick up new ENV values
      ConfigGem.reload!

      # Run the test
      example.run

      # Restore original values
      original_values.each do |key, value|
        ENV[key] = value
      end

      # Reload config to restore original settings
      ConfigGem.reload!
    end

    it 'overrides default settings with environment variables' do
      # Access Settings constant safely
      settings = Object.const_get('Settings')
      expect(settings.cache_max_age).to eq(14)
      expect(settings.owner).to eq('custom-owner')

      # Verify other settings remain unchanged
      expect(settings.branch_name).to eq('cookstyle-fixes')
    end
  end

  describe 'YAML config loading and merging' do
    it 'loads all default values from _default_configuration.yml' do
      config = configuration_class.new(logger, validator, config_files: [default_config_path])
      expect(config.cache_max_age).to eq(7)
      expect(config.owner).to eq('')
      expect(config.git_email).to eq('cookstylerunner@noreply.com')
      expect(config.use_cache).to be(true)
      expect(config.pr_title).to eq('Automated PR: Cookstyle Changes')
      expect(config.issue_labels).to eq(['Skip: Announcements', 'Release: Patch', 'Cookstyle'])
    end

    it 'overrides a value from the override YAML' do
      config = configuration_class.new(logger, validator, config_files: [default_config_path, override_config_path])
      expect(config.cache_max_age).to eq(3)
      expect(config.owner).to eq('sous-chefs') # still default value
    end

    it 'uses only the override YAML if no default supplied' do
      config = configuration_class.new(logger, validator, config_files: [override_config_path])
      expect(config.cache_max_age).to eq(3)
      expect(config.owner).to be_nil
    end

    context 'when a YAML file is malformed' do
      let(:malformed_yaml_path) do
        Tempfile.create(['malformed', '.yml']) do |f|
          f.write("owner: test-owner\ncache_max_age: seven: twelve\nbranch_name: malformed-branch")
          f.path
        end
      end

      after do
        FileUtils.rm_f(malformed_yaml_path)
      end

      it 'logs an error and continues loading other valid files or defaults' do
        # Load with a valid default and the malformed one
        # The malformed one should be skipped, and defaults should apply where not overridden by good files.
        config = configuration_class.new(logger, validator, config_files: [default_config_path, malformed_yaml_path])
        expect(logger).to have_received(:error).with(/Error loading configuration from #{Regexp.escape(malformed_yaml_path)}:.*Psych::SyntaxError/)

        # Check that a value from the valid default_config_path is loaded
        expect(config.git_email).to eq('cookstylerunner@noreply.com')
        # owner is '' in default_config_path, so that should be the value, not from malformed
        expect(config.owner).to eq('')
        # cache_max_age from default_config_path
        expect(config.cache_max_age).to eq(7)
        # branch_name from default_config_path, not the malformed one
        expect(config.branch_name).to eq('cookstyle-fixes')
      end

      it 'logs an error and uses defaults if only malformed file is provided' do
        # No valid files, so defaults from the class itself should be used.
        # The Configuration class sets defaults directly if no YAML provides them.
        config = configuration_class.new(logger, validator, config_files: [malformed_yaml_path])
        expect(logger).to have_received(:error).with(/Error loading configuration from #{Regexp.escape(malformed_yaml_path)}:.*Psych::SyntaxError/)

        # Check some default values defined in CookstyleRunner::Configuration initialize method or apply_config
        # These might be nil or specific defaults if the malformed file fails to load any values.
        expect(config.owner).to be_nil # No YAML, so default (nil before env vars)
        expect(config.cache_max_age).to eq(7) # Default from apply_config
        expect(config.branch_name).to eq('cookstyle-fixes') # Default from apply_config
      end
    end
  end

  describe '#log_summary 2' do
    it 'delegates to the formatter' do
      config = described_class.new(logger, validator, config_files: [default_config_path])
      allow(CookstyleRunner::ConfigurationFormatter).to receive(:new).and_return(formatter)
      expect(formatter).to have_received(:log_summary).with(logger)
      config.log_summary(logger)
    end
  end

  describe 'configuration sections 1' do
    it 'returns auth configuration hash' do
      config = described_class.new(logger, validator, config_files: [default_config_path])
      auth = config.auth_config
      expect(auth).to be_a(Hash)
      expect(auth[:github_token]).to be_nil
    end

    it 'returns repository configuration hash' do
      config = described_class.new(logger, validator, config_files: [default_config_path])
      repo = config.repository_config
      expect(repo).to be_a(Hash)
      expect(repo[:owner]).to eq('sous-chefs')
      expect(repo[:filter_repos]).to eq([])
    end

    it 'returns branch/PR configuration hash' do
      config = described_class.new(logger, validator, config_files: [default_config_path])
      branch_pr = config.branch_pr_config
      expect(branch_pr).to be_a(Hash)
      expect(branch_pr[:branch_name]).to eq('cookstyle-fixes')
      expect(branch_pr[:pr_title]).to eq('Automated PR: Cookstyle Changes')
      expect(branch_pr[:issue_labels]).to eq(['Skip: Announcements', 'Release: Patch', 'Cookstyle'])
      expect(branch_pr[:default_branch]).to eq('main')
    end

    it 'returns cache configuration hash' do
      config = described_class.new(logger, validator, config_files: [default_config_path])
      cache = config.cache_config
      expect(cache).to be_a(Hash)
      expect(cache[:cache_dir]).to eq('/tmp/cookstyle-runner')
      expect(cache[:use_cache]).to be(true)
      expect(cache[:cache_max_age]).to eq(7)
      expect(cache[:force_refresh]).to be(false)
    end

    it 'returns git configuration hash' do
      config = described_class.new(logger, validator, config_files: [default_config_path])
      git = config.git_config
      expect(git).to be_a(Hash)
      expect(git[:git_name]).to eq('GitHub Cookstyle Runner')
      expect(git[:git_email]).to eq('cookstylerunner@noreply.com')
    end

    it 'returns changelog configuration hash' do
      config = described_class.new(logger, validator, config_files: [File.expand_path('../fixtures/changelog.yml', __dir__)])
      changelog = config.changelog_config
      expect(changelog).to be_a(Hash)
      expect(changelog[:manage_changelog]).to be(true)
      expect(changelog[:changelog_location]).to eq('CHANGELOG.md')
      expect(changelog[:changelog_marker]).to eq('## Unreleased')
    end

    it 'returns processing configuration hash' do
      config = described_class.new(logger, validator, config_files: [File.expand_path('../fixtures/processing.yml', __dir__)])
      processing = config.processing_config
      expect(processing).to be_a(Hash)
      expect(processing[:retry_count]).to eq(3)
      expect(processing[:thread_count]).to eq(4)
      expect(processing[:create_manual_fix_issues]).to be(true)
      expect(processing[:create_manual_fix_issues]).to be(true)
    end
  end

  describe '#initialize' do
    it 'initializes with a logger' do
      expect(config).to be_a(described_class)
    end

    it 'creates a validator' do
      expect(CookstyleRunner::ConfigurationValidator).to have_received(:new).with(logger)
      described_class.new(logger)
    end

    it 'validates required environment variables' do
      expect(validator).to have_received(:validate_required_env_vars)
      described_class.new(logger)
    end

    it 'initializes the formatter' do
      expect(CookstyleRunner::ConfigurationFormatter).to have_received(:new)
      described_class.new(logger)
    end
  end

  describe '#to_hash' do
    it 'returns a hash with all configuration values' do
      hash = config.to_hash

      # Basic validation
      expect(hash).to be_a(Hash)
      expect(hash[:github_token]).to be_nil

      # Repository configuration
      expect(hash).to include(owner: 'sous-chefs', topics: %w[chef cookbook], filter_repos: %w[repo1 repo2])

      # Branch/PR configuration
      expect(hash).to include(
        branch_name: 'cookstyle-fixes',
        pr_title: 'Automated PR: Cookstyle Changes',
        issue_labels: ['Skip: Announcements', 'Release: Patch', 'Cookstyle'],
        default_branch: 'main'
      )

      # Git configuration
      expect(hash).to include(git_name: 'Test User', git_email: 'test@example.com')

      # Cache configuration
      expect(hash).to include(cache_dir: '/tmp/cookstyle-runner', use_cache: true, cache_max_age: 7, force_refresh: false)

      # Processing configuration
      expect(hash).to include(retry_count: 3, thread_count: 4, create_manual_fix_issues: true)
    end
  end

  describe '#log_summary' do
    it 'delegates to the formatter' do
      expect(formatter).to have_received(:log_summary).with(logger)
      config.log_summary(logger)
    end
  end

  describe 'initialization with default values' do
    context 'when no environment variables are set' do
      before do
        # Reset all environment variables to use defaults
        allow(ENV).to receive(:fetch).with('GITHUB_TOKEN', nil).and_return(nil)
        allow(ENV).to receive(:fetch).with('GITHUB_APP_ID', nil).and_return('app_id')
        allow(ENV).to receive(:fetch).with('GITHUB_APP_INSTALLATION_ID', nil).and_return('install_id')
        allow(ENV).to receive(:fetch).with('GITHUB_APP_PRIVATE_KEY', nil).and_return('private_key')
        allow(ENV).to receive(:fetch).with('GCR_DESTINATION_REPO_OWNER', nil).and_return('default-owner')
      end

      it 'uses default values' do
        config = described_class.new(logger, validator)
        expect(config.github_token).to be_nil
        expect(config.github_app_id).to be_nil
        expect(config.github_app_installation_id).to be_nil
        expect(config.github_app_private_key).to be_nil
        expect(config.branch_name).to eq('cookstyle-fixes')
        expect(config.pr_title).to eq('Automated PR: Cookstyle Changes')
        expect(config.cache_max_age).to eq(7)
      end
    end
  end

  describe 'configuration sections' do
    it 'returns auth configuration hash' do
      auth = config.auth_config
      expect(auth).to be_a(Hash)
      expect(auth[:github_token]).to be_nil
      expect(auth[:github_app_id]).to be_nil
      expect(auth[:github_app_installation_id]).to be_nil
      expect(auth[:github_app_private_key]).to be_nil
      expect(auth[:github_api_endpoint]).to eq('https://api.github.com')
    end

    it 'returns repository configuration hash' do
      repo = config.repository_config
      expect(repo).to be_a(Hash)
      expect(repo[:owner]).to eq('test-owner')
      expect(repo[:topics]).to eq(%w[chef cookbook])
      expect(repo[:filter_repos]).to eq(%w[repo1 repo2])
    end

    it 'returns branch/PR configuration hash' do
      branch_pr = config.branch_pr_config
      expect(branch_pr).to be_a(Hash)
      expect(branch_pr[:branch_name]).to eq('cookstyle-fixes')
      expect(branch_pr[:pr_title]).to eq('Automated PR: Cookstyle Changes')
      expect(branch_pr[:issue_labels]).to eq(%w[cookstyle automated])
      expect(branch_pr[:default_branch]).to eq('main')
    end

    it 'returns git configuration hash' do
      git = config.git_config
      expect(git).to be_a(Hash)
      expect(git[:git_name]).to eq('Test User')
      expect(git[:git_email]).to eq('test@example.com')
    end

    it 'returns cache configuration hash' do
      cache = config.cache_config
      expect(cache).to be_a(Hash)
      expect(cache[:cache_dir]).to eq('/tmp/cache')
      expect(cache[:use_cache]).to be(true)
      expect(cache[:cache_max_age]).to eq(7)
      expect(cache[:force_refresh]).to be(false)
    end

    it 'returns changelog configuration hash' do
      changelog = config.changelog_config
      expect(changelog).to be_a(Hash)
      expect(changelog[:manage_changelog]).to be(true)
      expect(changelog[:changelog_location]).to eq('CHANGELOG.md')
      expect(changelog[:changelog_marker]).to eq('## Unreleased')
    end

    it 'returns processing configuration hash' do
      processing = config.processing_config
      expect(processing).to be_a(Hash)
      expect(processing[:retry_count]).to eq(3)
      expect(processing[:thread_count]).to eq(4)
      expect(processing[:create_manual_fix_issues]).to be(true)
    end
  end

  describe 'environment variable validation' do
    context 'when GCR_CACHE_MAX_AGE is set to an invalid (non-integer) string' do
      around do |example|
        original_cache_max_age = ENV.fetch('GCR_CACHE_MAX_AGE', nil)
        ENV['GCR_CACHE_MAX_AGE'] = 'not-an-integer'

        # The validator will be called by ConfigGem.reload!
        # We expect it to catch the type error from dry-schema and handle it gracefully.
        # For this test, we're focusing on the outcome: the setting falls back to default.
        allow(validator).to receive(:validate).and_call_original # Allow other validations to proceed
        # Mocking logger for potential error messages from ConfigGem or validator
        allow(logger).to receive(:error)

        ConfigGem.reload!
        example.run
      ensure
        ENV['GCR_CACHE_MAX_AGE'] = original_cache_max_age
        ConfigGem.reload! # Reload to restore original settings
      end

      it 'falls back to the default cache_max_age and logs an error' do
        # Access Settings constant safely, it's reloaded in the around block
        settings = Object.const_get('Settings')
        expect(settings.cache_max_age).to eq(7) # Default value

        # Check that an error related to the invalid GCR_CACHE_MAX_AGE was logged.
        # This can be tricky as the exact message comes from deep within ConfigGem/Dry-Schema.
        # A more robust test might involve a custom validator mock that records calls,
        # but for now, checking the fallback behavior is a good start.
        # We expect our validator to log something, or for ConfigGem's machinery to log.
        # Let's assume our validator (or the underlying mechanism it uses) would log.
        # The `SettingsValidator` should log via the logger passed to Configuration.
        # This check assumes the logger passed to Configuration is used by the validator when errors occur.
        expect(logger).to have_received(:error).with(/GCR_CACHE_MAX_AGE/i).at_least(:once)
      end
    end
  end
end
