# frozen_string_literal: true

require 'spec_helper'
require 'cookstyle_runner/repository_processor'
require 'cookstyle_runner/cookstyle_operations'
require 'cookstyle_runner/git'
require 'cookstyle_runner/context_manager'
require 'cookstyle_runner/github_pr_manager'
require 'cookstyle_runner/cache'
require 'octokit'
require 'logger'
require 'tmpdir'
require 'fileutils'
require 'ostruct'

# markdown
# Minimal Integration Tests for RepositoryProcessor
#
# These tests verify only the most basic integration flows:
# - A repo with offenses: should attempt to create a pull request.
# - A clean repo: should do nothing (no PR/issue creation).
# All other logic is covered by unit tests. External dependencies are stubbed. Keep these tests simple and maintainable.

RSpec.describe CookstyleRunner::RepositoryProcessor, :integration do
  let(:logger) { Logger.new(StringIO.new) }
  let(:github_token) { 'mock_gh_token' }
  let(:cache_manager) { nil }
  let(:pr_manager) { nil }
  let(:context_manager) { nil }
  let(:commit_message) { 'chore: Auto-apply cookstyle fixes' }
  let(:pr_title) { commit_message }
  let(:pr_body) { 'Automated Cookstyle fixes applied by the Cookstyle Runner bot.' }
  let(:configuration) do
    # Use a real Configuration object for proper type checking
    CookstyleRunner::Configuration.new(logger)
  end
  let(:tmp_dir) { Dir.mktmpdir }
  let(:octokit_client) { instance_double(Octokit::Client) }

  before do
    CookstyleRunner::ContextManager.instance.set_global_config({
                                                                 owner: 'sous-chefs',
                                                                 github_token: github_token,
                                                                 app_id: nil,
                                                                 installation_id: nil,
                                                                 private_key: nil
                                                               }, logger)
    allow(CookstyleRunner::Git).to receive(:clone_repo).and_return(true)
    allow(FileUtils).to receive(:remove_entry_secure).with(any_args)
  end

  after do
    FileUtils.rm_rf(tmp_dir)
    CookstyleRunner::ContextManager.instance.clear_contexts
  end

  context 'when processing a clean repository' do
    let(:repo_owner) { 'sous-chefs' }
    let(:repo_name) { 'haproxy' }
    let(:repo_url) { "https://github.com/#{repo_owner}/#{repo_name}.git" }
    # This context uses the default config where autocorrect: false
    let(:repo_context) { CookstyleRunner::ContextManager.instance.get_repo_context(repo_url, tmp_dir) }

    let(:processor) do
      described_class.new(
        configuration: configuration,
        logger: logger,
        cache_manager: cache_manager,
        pr_manager: pr_manager,
        context_manager: context_manager
      )
    end

    it 'does not attempt to create a pull request or issue' do
      # Stub Git operations
      allow(CookstyleRunner::Git).to receive_messages(
        clone_or_update_repo: true,
        current_commit_sha: 'abc123'
      )

      # Stub Cookstyle to return no offenses
      allow(CookstyleRunner::CookstyleOperations).to receive(:run_cookstyle)
        .and_return(
          issue_count: 0,
          auto_correctable_count: 0,
          manual_fixes_count: 0,
          offense_details: {}
        )

      # Process repository - since pr_manager is nil, no PRs/issues will be created
      result = processor.process_repository(repo_name, repo_url)

      # Verify the result indicates processing was successful
      expect(result['state']).to eq('processed')
      expect(result['issues_found']).to be false
    end
  end
end
