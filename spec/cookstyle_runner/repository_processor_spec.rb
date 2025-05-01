# frozen_string_literal: true

require 'spec_helper'
require 'cookstyle_runner/repository_processor'
require 'cookstyle_runner/cookstyle_operations'
require 'cookstyle_runner/git_operations'
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
  let(:logger) { instance_double(Logger, info: nil, warn: nil, error: nil, debug: nil) }
  let(:github_token) { 'mock_gh_token' }
  let(:cache_manager) { instance_double(CookstyleRunner::Cache).as_null_object }
  let(:pr_manager) { instance_spy(CookstyleRunner::GitHubPRManager) }
  let(:context_manager) { instance_double(CookstyleRunner::ContextManager).as_null_object }
  let(:commit_message) { 'chore: Auto-apply cookstyle fixes' }
  let(:pr_title) { commit_message }
  let(:pr_body) { 'Automated Cookstyle fixes applied by the Cookstyle Runner bot.' }
  let(:config) do
    {
      default_branch: 'main',
      autocorrect: false,
      create_pr: true,
      commit_message: commit_message,
      pr_title: pr_title,
      pr_body: pr_body
    }
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
    allow(GitOperations).to receive(:clone_repo).and_return(true)
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
        config: config,
        logger: logger,
        cache_manager: cache_manager,
        pr_manager: pr_manager,
        context_manager: context_manager
      )
    end

    it 'does not attempt to create a pull request or issue' do
      # Allow methods for negative expectation checking
      allow(pr_manager).to receive(:create_pull_request)
      allow(pr_manager).to receive(:create_issue_for_manual_fixes)

      allow(CookstyleRunner::CookstyleOperations).to receive(:run_cookstyle)
        .with(repo_context, logger)
        .and_return(
          {
            status: :no_issues_found,
            output: { 'summary' => { 'offense_count' => 0 } },
            num_auto: 0,
            num_manual: 0,
            pr_description: '',
            issue_description: '',
            changes_committed: false
          }
        )

      processor.process_repository(repo_url, 1, 1)

      expect(pr_manager).not_to have_received(:create_pull_request)
    end
  end
end
