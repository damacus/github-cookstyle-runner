# frozen_string_literal: true

require 'spec_helper'
require 'cookstyle_runner/cookstyle_operations'
require 'json'
require 'tty-command'

# Mock Logger
class MockLogger
  def debug(msg); end

  def info(msg); end

  def warn(msg); end

  def error(msg); end
end

RSpec.describe CookstyleRunner::CookstyleOperations do
  let(:logger) { MockLogger.new }
  let(:cmd_double) { instance_double(TTY::Command) }
  let(:repo_dir) { '/tmp/fake_repo' }

  # Raw JSON output from Cookstyle runs (captured from fixtures)
  let(:apt_json_output) do
    <<~JSON
      {"metadata":{"rubocop_version":"1.25.1","ruby_engine":"ruby","ruby_version":"3.4.1","ruby_patchlevel":"0","ruby_platform":"arm64-darwin24"},"files":[{"path":"Berksfile","offenses":[]},{"path":"Dangerfile","offenses":[]},{"path":"attributes/default.rb","offenses":[]},{"path":"libraries/helpers.rb","offenses":[]},{"path":"metadata.rb","offenses":[]},{"path":"recipes/cacher-client.rb","offenses":[{"severity":"convention","message":"Layout/EmptyLines: Extra blank line detected. (https://rubystyle.guide#two-or-more-empty-lines)","cop_name":"Layout/EmptyLines","corrected":false,"correctable":true,"location":{"start_line":27,"start_column":1,"last_line":28,"last_column":1,"length":1,"line":27,"column":1}}]},{"path":"recipes/cacher-ng.rb","offenses":[]},{"path":"recipes/default.rb","offenses":[]},{"path":"recipes/unattended-upgrades.rb","offenses":[]},{"path":"spec/spec_helper.rb","offenses":[]},{"path":"spec/unit/recipes/cacher-client_spec.rb","offenses":[]},{"path":"spec/unit/recipes/cacher-ng_spec.rb","offenses":[]},{"path":"spec/unit/recipes/default_spec.rb","offenses":[]},{"path":"spec/unit/recipes/unattended-upgrades_spec.rb","offenses":[]},{"path":"test/fixtures/cookbooks/test/metadata.rb","offenses":[]},{"path":"test/fixtures/cookbooks/test/recipes/base.rb","offenses":[]},{"path":"test/fixtures/cookbooks/test/recipes/cacher.rb","offenses":[]},{"path":"test/fixtures/cookbooks/test/recipes/unattended-upgrades.rb","offenses":[]},{"path":"test/integration/cacher/cacher-ng-client_spec.rb","offenses":[]},{"path":"test/integration/compile-time/default_spec.rb","offenses":[]},{"path":"test/integration/default/default_spec.rb","offenses":[]},{"path":"test/integration/resources/resources_spec.rb","offenses":[{"severity":"refactor","message":"Chef/Deprecations/ResourceWithoutUnifiedTrue: Set `unified_mode true` in Chef Infra Client 15.3+ custom resources to ensure they work correctly in Chef Infra Client 18 (April 2022) when Unified Mode becomes the default. (https://docs.chef.io/workstation/cookstyle/chef_deprecations_resourcewithoutunifiedtrue)","cop_name":"Chef/Deprecations/ResourceWithoutUnifiedTrue","corrected":false,"correctable":false,"location":{"start_line":1,"start_column":1,"last_line":1,"last_column":1,"length":1,"line":1,"column":1}}]},{"path":"test/integration/resources/unattended_upgrades_spec.rb","offenses":[{"severity":"refactor","message":"Chef/Deprecations/ResourceWithoutUnifiedTrue: Set `unified_mode true` in Chef Infra Client 15.3+ custom resources to ensure they work correctly in Chef Infra Client 18 (April 2022) when Unified Mode becomes the default. (https://docs.chef.io/workstation/cookstyle/chef_deprecations_resourcewithoutunifiedtrue)","cop_name":"Chef/Deprecations/ResourceWithoutUnifiedTrue","corrected":false,"correctable":false,"location":{"start_line":1,"start_column":1,"last_line":1,"last_column":1,"length":1,"line":1,"column":1}}]}],"summary":{"offense_count":3,"target_file_count":23,"inspected_file_count":23}}
    JSON
  end

  let(:haproxy_json_output) do
    <<~JSON
      {"metadata":{"rubocop_version":"1.25.1","ruby_engine":"ruby","ruby_version":"3.4.1","ruby_patchlevel":"0","ruby_platform":"arm64-darwin24"},"files":[{"path":"Berksfile","offenses":[]},{"path":"Dangerfile","offenses":[]},{"path":"libraries/helpers.rb","offenses":[]},{"path":"libraries/resource.rb","offenses":[]},{"path":"libraries/template.rb","offenses":[]},{"path":"metadata.rb","offenses":[]},{"path":"resources/acl.rb","offenses":[]},{"path":"resources/backend.rb","offenses":[]},{"path":"resources/cache.rb","offenses":[]},{"path":"resources/config_defaults.rb","offenses":[]},{"path":"resources/config_global.rb","offenses":[]},{"path":"resources/fastcgi.rb","offenses":[]},{"path":"resources/frontend.rb","offenses":[]},{"path":"resources/install.rb","offenses":[]},{"path":"resources/listen.rb","offenses":[]},{"path":"resources/mailer.rb","offenses":[]},{"path":"resources/partial/_config_file.rb","offenses":[]},{"path":"resources/partial/_extra_options.rb","offenses":[]},{"path":"resources/peer.rb","offenses":[]},{"path":"resources/resolver.rb","offenses":[]},{"path":"resources/service.rb","offenses":[]},{"path":"resources/use_backend.rb","offenses":[]},{"path":"resources/userlist.rb","offenses":[]},{"path":"spec/spec_helper.rb","offenses":[]},{"path":"spec/unit/recipes/cache_spec.rb","offenses":[]},{"path":"spec/unit/recipes/defaults_spec.rb","offenses":[]},{"path":"spec/unit/recipes/fastcgi_spec.rb","offenses":[]},{"path":"spec/unit/recipes/frontend_backend_spec.rb","offenses":[]},{"path":"spec/unit/recipes/global_spec.rb","offenses":[]},{"path":"spec/unit/recipes/install_spec.rb","offenses":[]},{"path":"spec/unit/recipes/listen_spec.rb","offenses":[]},{"path":"spec/unit/recipes/mailer_spec.rb","offenses":[]},{"path":"spec/unit/recipes/peer_spec.rb","offenses":[]},{"path":"test/cookbooks/test/metadata.rb","offenses":[]},{"path":"test/cookbooks/test/recipes/config_2.rb","offenses":[]},{"path":"test/cookbooks/test/recipes/config_3.rb","offenses":[]},{"path":"test/cookbooks/test/recipes/config_acl.rb","offenses":[]},{"path":"test/cookbooks/test/recipes/config_array.rb","offenses":[]},{"path":"test/cookbooks/test/recipes/config_backend_search.rb","offenses":[]},{"path":"test/cookbooks/test/recipes/config_custom_template.rb","offenses":[]},{"path":"test/cookbooks/test/recipes/config_fastcgi.rb","offenses":[]},{"path":"test/cookbooks/test/recipes/config_resolver.rb","offenses":[]},{"path":"test/cookbooks/test/recipes/config_ssl_redirect.rb","offenses":[]},{"path":"test/cookbooks/test/recipes/package.rb","offenses":[]},{"path":"test/cookbooks/test/recipes/source.rb","offenses":[]},{"path":"test/cookbooks/test/recipes/source_24.rb","offenses":[]},{"path":"test/cookbooks/test/recipes/source_26.rb","offenses":[]},{"path":"test/cookbooks/test/recipes/source_28.rb","offenses":[]},{"path":"test/cookbooks/test/recipes/source_29.rb","offenses":[]},{"path":"test/cookbooks/test/recipes/source_lua.rb","offenses":[]},{"path":"test/cookbooks/test/recipes/source_openssl.rb","offenses":[]},{"path":"test/integration/common/controls/common_spec.rb","offenses":[]},{"path":"test/integration/config_2/controls/config_spec.rb","offenses":[]},{"path":"test/integration/config_3/controls/config_spec.rb","offenses":[]},{"path":"test/integration/config_acl/controls/config_spec.rb","offenses":[]},{"path":"test/integration/config_array/controls/config_spec.rb","offenses":[]},{"path":"test/integration/config_backend_search/controls/config_backend_search_spec.rb","offenses":[]},{"path":"test/integration/config_custom_template/controls/template_spec.rb","offenses":[]},{"path":"test/integration/config_fastcgi/controls/fast_cgi_spec.rb","offenses":[]},{"path":"test/integration/config_resolver/controls/resolver_spec.rb","offenses":[]},{"path":"test/integration/config_ssl_redirect/controls/ssl_redirect_spec.rb","offenses":[]},{"path":"test/integration/package/controls/package_spec.rb","offenses":[]},{"path":"test/integration/source-default/controls/source_spec.rb","offenses":[]},{"path":"test/integration/source_2.4/controls/source_spec.rb","offenses":[]},{"path":"test/integration/source_2.6/controls/source_spec.rb","offenses":[]},{"path":"test/integration/source_2.8/controls/source_spec.rb","offenses":[]},{"path":"test/integration/source_2.9/controls/source_spec.rb","offenses":[]},{"path":"test/integration/source_lua/controls/lua_spec.rb","offenses":[]},{"path":"test/integration/source_openssl/controls/openssl_spec.rb","offenses":[]}],"summary":{"offense_count":0,"target_file_count":69,"inspected_file_count":69}}
    JSON
  end

  # Parsed versions of the JSON
  let(:apt_parsed) { JSON.parse(apt_json_output) }
  let(:haproxy_parsed) { JSON.parse(haproxy_json_output) }

  # Mock TTY::Command results
  let(:apt_result_double) { instance_double(TTY::Command::Result, out: apt_json_output, exit_status: 0) }
  let(:haproxy_result_double) { instance_double(TTY::Command::Result, out: haproxy_json_output, exit_status: 0) }
  let(:autocorrect_result_double) { instance_double(TTY::Command::Result, out: '', exit_status: 0) } # Mock auto-correct run

  before do
    # Stub TTY::Command.new to return our double
    allow(TTY::Command).to receive(:new).and_return(cmd_double)
  end

  describe '.run_cookstyle' do
    context 'when there are mixed (auto and manual) offenses (APT fixture)' do
      before do
        # Mock the initial cookstyle run
        allow(cmd_double).to receive(:run!)
          .with('cookstyle --display-cop-names --format json', chdir: repo_dir, timeout: 300)
          .and_return(apt_result_double)

        # Mock the auto-correct run (since apt has correctable offenses)
        allow(cmd_double).to receive(:run!)
          .with('cookstyle --auto-correct-all', chdir: repo_dir, timeout: 300)
          .and_return(autocorrect_result_double)
      end

      #   - Parsed JSON output from the initial run
      #   - Number of auto-correctable offenses found
      #   - Number of manually correctable (uncorrectable) offenses found
      #   - Formatted PR description (if applicable)
      #   - Formatted Issue description (if applicable)
      it 'returns the correct counts of manual and auto correctable offenses' do
        _, num_auto, num_manual = described_class.run_cookstyle(repo_dir, logger)

        expect(num_auto).to eq(1)
        expect(num_manual).to eq(2)
      end

      it 'returns the correct PR description' do
        _, _, _, pr_desc = described_class.run_cookstyle(repo_dir, logger)

        expect(pr_desc).to include('**Total Offenses Detected:** 3')
        expect(pr_desc).to include('**Auto-corrected:** 1')
        expect(pr_desc).to include('**Manual Review Needed:** 2')
        expect(pr_desc).to include('Chef/Deprecations/ResourceWithoutUnifiedTrue')
        expect(pr_desc).to include('test/integration/resources/unattended_upgrades_spec.rb')
      end

      it 'returns the correct issue description' do
        _, _, _, _, issue_desc = described_class.run_cookstyle(repo_dir, logger)

        # Check for Issue Summary parts
        expect(issue_desc).to include('### Cookstyle Manual Review Summary')
        expect(issue_desc).to include('- **Total Offenses Detected:** 3')
        expect(issue_desc).to include('- **Manual Review Needed:** 2')
        # Check for Issue Description header
        expect(issue_desc).to include('### Manual Intervention Required')
        # Check for *only* manually correctable offenses
        expect(issue_desc).to include('`test/integration/resources/resources_spec.rb`: Chef/Deprecations/ResourceWithoutUnifiedTrue')
        expect(issue_desc).to include('`test/integration/resources/unattended_upgrades_spec.rb`: Chef/Deprecations/ResourceWithoutUnifiedTrue')
        expect(issue_desc).not_to include('cacher-client.rb') # Auto-correctable should NOT be listed

        # Verify auto-correct command was called
        expect(cmd_double).to have_received(:run!).with('cookstyle --auto-correct-all', chdir: repo_dir, timeout: 300)
      end
    end

    context 'when there are no offenses (HAProxy fixture)' do
      before do
        # Mock the initial cookstyle run (only this one is needed)
        allow(cmd_double).to receive(:run!)
          .with('cookstyle --display-cop-names --format json', chdir: repo_dir, timeout: 300)
          .and_return(haproxy_result_double)

        # Explicitly expect auto-correct NOT to be called
        allow(cmd_double).to receive(:run!).with('cookstyle --auto-correct-all', any_args) { raise 'Auto-correct should not be called' }
      end

      it 'returns zero counts and appropriate descriptions' do
        parsed_json, num_auto, num_manual, pr_desc, issue_desc = described_class.run_cookstyle(repo_dir, logger)

        expect(parsed_json).to eq(haproxy_parsed)
        expect(num_auto).to eq(0)
        expect(num_manual).to eq(0)

        expect(pr_desc).to include('**Total Offenses Detected:** 0')
        expect(issue_desc).not_to include('**Total Offenses Detected:** 0')

        # Ensure auto-correct was NOT called
        expect(cmd_double).not_to have_received(:run!).with('cookstyle --auto-correct-all', any_args)
      end
    end

    context 'when cookstyle output is invalid JSON' do
      let(:invalid_json_output) { 'This is not JSON' }
      let(:invalid_json_result_double) { instance_double(TTY::Command::Result, out: invalid_json_output, exit_status: 1) }

      before do
        allow(cmd_double).to receive(:run!)
          .with('cookstyle --display-cop-names --format json', chdir: repo_dir, timeout: 300)
          .and_return(invalid_json_result_double)

        # Expect logger error message
        allow(logger).to receive(:error)
      end

      it 'logs an error and returns default values' do
        parsed_json, num_auto, num_manual, pr_desc, issue_desc = described_class.run_cookstyle(repo_dir, logger)

        expect(logger).to have_received(:error).with(/Failed to parse Cookstyle JSON output:/).at_least(:once)
        expect(logger).to have_received(:error).with(/Raw output:/).at_least(:once)

        expect(parsed_json).to eq({})
        expect(num_auto).to eq(0)
        expect(num_manual).to eq(0)
        expect(pr_desc).not_to include('**Total Offenses Detected:** 0')
        expect(issue_desc).not_to include('**Total Offenses Detected:** 0')
      end
    end
  end

  describe '.count_correctable_offences' do
    it 'counts correctable offenses correctly for APT fixture' do
      expect(described_class.send(:count_correctable_offences, apt_parsed)).to eq(1)
    end

    it 'counts zero correctable offenses for HAProxy fixture' do
      expect(described_class.send(:count_correctable_offences, haproxy_parsed)).to eq(0)
    end
  end

  describe '.count_uncorrectable_offences' do
    it 'counts uncorrectable offenses correctly for APT fixture' do
      expect(described_class.send(:count_uncorrectable_offences, apt_parsed)).to eq(2)
    end

    it 'counts zero uncorrectable offenses for HAProxy fixture' do
      expect(described_class.send(:count_uncorrectable_offences, haproxy_parsed)).to eq(0)
    end
  end

  describe '.format_pr_summary' do
    it 'formats correctly for mixed offenses (APT)' do
      desc = described_class.format_pr_summary(3, 1)
      expect(desc).to include('**Total Offenses Detected:** 3')
      expect(desc).to include('**Auto-corrected:** 1')
      expect(desc).to include('**Manual Review Needed:** 2')
    end

    it 'formats correctly for no offenses (HAProxy)' do
      desc = described_class.format_pr_summary(0, 0)
      expect(desc).to include('- **Total Offenses Detected:** 0')
      expect(desc).to include('**Auto-corrected:** 0')
      expect(desc).to include('**Manual Review Needed:** 0')
    end
  end

  describe '.format_issue_description' do
    it 'formats correctly when manual offenses exist (APT)' do
      desc = described_class.format_issue_description(apt_parsed, 2)
      expect(desc).to include('test/integration/resources/resources_spec.rb')
      expect(desc).to include('test/integration/resources/unattended_upgrades_spec.rb')
      expect(desc).not_to include('cacher-client.rb') # This file is correctable so don't tell the user about it.
    end

    it 'formats correctly when no manual offenses exist (HAProxy)' do
      desc = described_class.format_issue_description(haproxy_parsed, 0)
      expect(desc).not_to include('**0** offense(s) that could not be automatically corrected.')
    end
  end
end
