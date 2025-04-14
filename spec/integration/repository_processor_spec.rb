# frozen_string_literal: true

require 'spec_helper'
require 'cookstyle_runner/repository_processor'
require 'cookstyle_runner/git_operations'
require 'cookstyle_runner/context_manager' # NEW: For singleton context manager
require 'cookstyle_runner/github_pr_manager'
require 'cookstyle_runner/authentication'
require 'octokit'
require 'logger'
require 'tmpdir'
require 'fileutils'

# Mark these as integration tests
# rubocop:disable Metrics/BlockLength
RSpec.describe CookstyleRunner::RepositoryProcessor, :integration do
  let(:logger) { instance_double(Logger, info: nil, warn: nil, error: nil, debug: nil) }
  let(:github_token) { 'mock_gh_token' }
  let(:default_branch) { 'main' }
  let(:branch_name) { "cookstyle-fixes-#{Time.now.strftime('%Y%m%d%H%M%S')}" }
  let(:commit_message) { 'chore: Auto-apply cookstyle fixes' }
  let(:pr_title) { commit_message }
  let(:pr_body) { 'Automated Cookstyle fixes applied by the Cookstyle Runner bot.' }
  let(:tmp_dir) { Dir.mktmpdir }
  let(:octokit_client) { instance_double(Octokit::Client) }

  before do
    # Set up global config for ContextManager singleton
    CookstyleRunner::ContextManager.instance.set_global_config({
                                                                 owner: 'sous-chefs',
                                                                 github_token: github_token,
                                                                 app_id: nil,
                                                                 installation_id: nil,
                                                                 private_key: nil
                                                               }, logger)

    allow_any_instance_of(CookstyleRunner::GitHubPRManager).to receive(:github_client).and_return(octokit_client)
    allow(GitOperations).to receive(:clone_repo).and_return(true)
    allow(FileUtils).to receive(:remove_entry_secure).with(any_args)
  end

  after do
    FileUtils.remove_entry_secure(tmp_dir) if Dir.exist?(tmp_dir)
    # Clear singleton contexts after each test
    CookstyleRunner::ContextManager.instance.clear_contexts
  end

  context 'when processing a repository that needs fixes (e.g., sous-chefs/apt)' do
    let(:repo_owner) { 'sous-chefs' }
    let(:repo_name) { 'apt' }
    # NEW: Use ContextManager singleton to get repo context
    let(:repo_url) { "https://github.com/#{repo_owner}/#{repo_name}.git" }
    let(:repo_dir) { File.join(tmp_dir, repo_owner, repo_name) }
    let(:repo_context) do
      CookstyleRunner::ContextManager.instance.get_repo_context(repo_url, repo_dir)
    end
    let(:processor) { described_class.new(repo_context) }

    it 'runs cookstyle, commits changes, and attempts to create a pull request' do
      # 1. Mock CookstyleRunner to indicate fixes were made
      expect(CookstyleRunner::CookstyleRunner).to receive(:run_cookstyle)
        .with(repo_context.repo_dir, true)
        .and_return(true)

      # 2. Mock GitOperations for commit/push
      expect(GitOperations).to receive(:generate_branch_name).and_return(branch_name)
      expect(GitOperations).to receive(:commit_and_push_changes)
        .with(repo_context, branch_name, commit_message)
        .and_return(true)

      # 3. Expect PRManager (via Octokit client) to attempt PR creation
      expect(octokit_client).to receive(:create_pull_request)
        .with(
          repo_context.repo_name,
          default_branch,
          branch_name,
          pr_title,
          pr_body
        ).and_return({ html_url: 'http://example.com/pull/1' })

      # Run the processor
      processor.process_repository(
        autocorrect: true,
        create_pr: true,
        commit_message: commit_message,
        pr_title: pr_title,
        pr_body: pr_body
      )

      # Verify logging (optional but good)
      expect(logger).to have_received(:info).with("Processing repository: #{repo_context.repo_name}")
      expect(logger).to have_received(:info).with("Cookstyle run finished for #{repo_context.repo_name}. Fixes applied.")
      expect(logger).to have_received(:info).with('Pull request created successfully: http://example.com/pull/1')

      # 2. Mock GitOperations for commit/push
      expect(CookstyleRunner::GitOperations).to receive(:generate_branch_name).and_return(branch_name)
      expect(CookstyleRunner::GitOperations).to receive(:commit_and_push_changes)
        .with(repo_context, branch_name, commit_message)
        .and_return(true) # Simulate successful commit/push

      # 3. Expect PRManager (via Octokit client) to attempt PR creation
      expect(octokit_client).to receive(:create_pull_request)
        .with(
          repo_name,
          default_branch,
          branch_name,
          pr_title,
          pr_body
        ).and_return({ html_url: 'http://example.com/pull/1' }) # Mock response

      # Run the processor
      processor.process_repository(
        autocorrect: true,
        create_pr: true,
        commit_message: commit_message,
        pr_title: pr_title,
        pr_body: pr_body
      )

      # Verify logging (optional but good)
      expect(logger).to have_received(:info).with("Processing repository: #{repo_name}")
      expect(logger).to have_received(:info).with("Cookstyle run finished for #{repo_name}. Fixes applied.")
      expect(logger).to have_received(:info).with('Pull request created successfully: http://example.com/pull/1')
    end
  end

  # Add context for 'when processing a repository that is clean' later
end
# rubocop:enable Metrics/BlockLength
