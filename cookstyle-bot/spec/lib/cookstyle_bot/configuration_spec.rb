# typed: false
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Settings' do
  subject(:settings) { Settings }

  let(:original_app_env) { ENV.fetch('APP_ENV', nil) }

  # Helper method to properly reload settings with a specific environment
  # This forces the config gem to look for environment-specific files
  def reload_settings_with_env(env)
    ENV['APP_ENV'] = env
    config_root = File.expand_path('../../../config', __dir__)
    Config.load_and_set_settings(Config.setting_files(config_root, env))
  end

  after do
    reload_settings_with_env(original_app_env)
  end

  it 'is defined' do
    expect(defined?(Settings)).to be_truthy
  end

  context 'with default settings file' do
    before do
      reload_settings_with_env(nil)
    end

    it 'loads default settings from settings.yml' do
      expect(settings.github.api_root).to eq('api.github.com')
    end

    it 'loads default logging level' do
      expect(settings.logging.level).to eq('INFO')
    end
  end

  context 'when APP_ENV is set to test' do
    before do
      reload_settings_with_env('test')
    end

    it 'overrides logging level' do
      expect(settings.logging.level).to eq('test!')
    end

    it 'overrides destination_repo_owner' do
      expect(settings.github.destination_repo_owner).to eq('env-test-owner')
    end
  end

  context 'when APP_ENV is set for environment-specific files' do
    before do
      reload_settings_with_env('test')
    end

    it 'loads settings from test.yml (e.g., logging level)' do
      expect(settings.logging.level).to eq('test!')
    end

    it 'loads settings from test.yml (e.g., destination_repo_owner)' do
      expect(settings.github.destination_repo_owner).to eq('env-test-owner')
    end
  end
end
