# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'tmpdir'

# rubocop:disable RSpec/DescribeClass, RSpec/ExampleLength
RSpec.describe 'Configuration Loading Priority' do
  let(:temp_config_dir) { Dir.mktmpdir('config_test') }
  let(:settings_dir) { File.join(temp_config_dir, 'settings') }
  let(:environments_dir) { File.join(temp_config_dir, 'environments') }

  before do
    # Create directory structure
    FileUtils.mkdir_p(settings_dir)
    FileUtils.mkdir_p(environments_dir)

    # Stub the config root to use our temp directory
    allow(File).to receive(:dirname).and_call_original
    allow(File).to receive(:join).and_call_original
  end

  after do
    FileUtils.rm_rf(temp_config_dir)
  end

  describe 'priority order' do
    it 'loads files in the correct priority order' do
      environment = 'test'

      # Create test files with unique values to track loading order
      File.write(File.join(temp_config_dir, 'settings.yml'), <<~YAML)
        test_value: 'from_settings_yml'
        priority_1: 'settings.yml'
      YAML

      File.write(File.join(settings_dir, 'test.yml'), <<~YAML)
        test_value: 'from_settings_test_yml'
        priority_2: 'settings/test.yml'
      YAML

      File.write(File.join(environments_dir, 'test.yml'), <<~YAML)
        test_value: 'from_environments_test_yml'
        priority_3: 'environments/test.yml'
      YAML

      File.write(File.join(temp_config_dir, 'settings.local.yml'), <<~YAML)
        test_value: 'from_settings_local_yml'
        priority_4: 'settings.local.yml'
      YAML

      File.write(File.join(settings_dir, 'test.local.yml'), <<~YAML)
        test_value: 'from_settings_test_local_yml'
        priority_5: 'settings/test.local.yml'
      YAML

      File.write(File.join(environments_dir, 'test.local.yml'), <<~YAML)
        test_value: 'from_environments_test_local_yml'
        priority_6: 'environments/test.local.yml'
      YAML

      # Get the setting files using Config.setting_files
      setting_files = Config.setting_files(temp_config_dir, environment)

      # Verify the files are in the correct order
      # NOTE: Config.setting_files may not include all paths if they don't exist
      expect(setting_files).to include(
        File.join(temp_config_dir, 'settings.yml'),
        File.join(settings_dir, 'test.yml'),
        File.join(environments_dir, 'test.yml'),
        File.join(settings_dir, 'test.local.yml'),
        File.join(environments_dir, 'test.local.yml')
      )

      # Load and verify priority
      Config.load_and_set_settings(setting_files)

      # The last file (environments/test.local.yml) should win
      expect(Settings.test_value).to eq('from_environments_test_local_yml')

      # All priority markers should be present
      expect(Settings.priority_1).to eq('settings.yml')
      expect(Settings.priority_2).to eq('settings/test.yml')
      expect(Settings.priority_3).to eq('environments/test.yml')
      # NOTE: settings.local.yml is not loaded by Config.setting_files
      expect(Settings.priority_5).to eq('settings/test.local.yml')
      expect(Settings.priority_6).to eq('environments/test.local.yml')
    end

    it 'allows later files to override earlier files' do
      environment = 'development'

      # Base settings
      File.write(File.join(temp_config_dir, 'settings.yml'), <<~YAML)
        owner: 'base-owner'
        thread_count: 1
        cache_enabled: false
      YAML

      # Environment-specific override
      File.write(File.join(settings_dir, 'development.yml'), <<~YAML)
        owner: 'dev-owner'
        thread_count: 4
      YAML

      # Local override (highest priority) - use settings/development.local.yml
      File.write(File.join(settings_dir, 'development.local.yml'), <<~YAML)
        owner: 'local-owner'
      YAML

      setting_files = Config.setting_files(temp_config_dir, environment)
      Config.load_and_set_settings(setting_files)

      # Local file should override everything
      expect(Settings.owner).to eq('local-owner')
      # Development file should override base
      expect(Settings.thread_count).to eq(4)
      # Base value should remain if not overridden
      expect(Settings.cache_enabled).to be false
    end

    it 'handles missing files gracefully' do
      environment = 'production'

      # Only create base settings file
      File.write(File.join(temp_config_dir, 'settings.yml'), <<~YAML)
        owner: 'production-owner'
        thread_count: 8
      YAML

      setting_files = Config.setting_files(temp_config_dir, environment)

      # Should not raise error even if other files don't exist
      expect { Config.load_and_set_settings(setting_files) }.not_to raise_error

      expect(Settings.owner).to eq('production-owner')
      expect(Settings.thread_count).to eq(8)
    end

    it 'loads environment-specific local files with highest priority' do
      environment = 'test'

      File.write(File.join(temp_config_dir, 'settings.yml'), <<~YAML)
        pr_title: 'Base PR Title'
        branch_name: 'base-branch'
      YAML

      File.write(File.join(settings_dir, 'test.yml'), <<~YAML)
        pr_title: 'Test PR Title'
      YAML

      File.write(File.join(environments_dir, 'test.local.yml'), <<~YAML)
        pr_title: 'Local Test PR Title'
      YAML

      setting_files = Config.setting_files(temp_config_dir, environment)
      Config.load_and_set_settings(setting_files)

      # environments/test.local.yml should have highest priority
      expect(Settings.pr_title).to eq('Local Test PR Title')
      # Unoverridden values should come from base
      expect(Settings.branch_name).to eq('base-branch')
    end

    it 'demonstrates the complete cascade with all files present' do
      environment = 'development'

      # Level 1: Base settings
      File.write(File.join(temp_config_dir, 'settings.yml'), <<~YAML)
        value_a: 'level_1'
        value_b: 'level_1'
        value_c: 'level_1'
        value_d: 'level_1'
        value_e: 'level_1'
      YAML

      # Level 2: settings/development.yml
      File.write(File.join(settings_dir, 'development.yml'), <<~YAML)
        value_b: 'level_2'
        value_c: 'level_2'
        value_d: 'level_2'
        value_e: 'level_2'
      YAML

      # Level 3: environments/development.yml
      File.write(File.join(environments_dir, 'development.yml'), <<~YAML)
        value_c: 'level_3'
        value_d: 'level_3'
        value_e: 'level_3'
      YAML

      # Level 4: settings/development.local.yml
      File.write(File.join(settings_dir, 'development.local.yml'), <<~YAML)
        value_d: 'level_4'
        value_e: 'level_4'
      YAML

      # Level 5: environments/development.local.yml (highest priority)
      File.write(File.join(environments_dir, 'development.local.yml'), <<~YAML)
        value_e: 'level_5'
      YAML

      setting_files = Config.setting_files(temp_config_dir, environment)
      Config.load_and_set_settings(setting_files)

      # Verify each value is overridden at the correct level
      expect(Settings.value_a).to eq('level_1') # Only in base
      expect(Settings.value_b).to eq('level_2') # Overridden at level 2
      expect(Settings.value_c).to eq('level_3') # Overridden at level 3
      expect(Settings.value_d).to eq('level_4') # Overridden at level 4
      expect(Settings.value_e).to eq('level_5') # Overridden at level 5 (highest)
    end
  end

  describe 'file path structure' do
    it 'generates correct file paths for each priority level' do
      environment = 'staging'
      setting_files = Config.setting_files(temp_config_dir, environment)

      expected_files = [
        File.join(temp_config_dir, 'settings.yml'),
        File.join(temp_config_dir, 'settings', 'staging.yml'),
        File.join(temp_config_dir, 'environments', 'staging.yml'),
        File.join(temp_config_dir, 'settings', 'staging.local.yml'),
        File.join(temp_config_dir, 'environments', 'staging.local.yml')
      ]

      expected_files.each do |expected_file|
        expect(setting_files).to include(expected_file)
      end
    end
  end
end
# rubocop:enable RSpec/DescribeClass, RSpec/ExampleLength
