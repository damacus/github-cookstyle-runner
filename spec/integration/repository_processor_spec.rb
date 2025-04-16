# frozen_string_literal: true

# spec/integration/repository_processor_spec.rb
require 'spec_helper'
require 'cookstyle_runner/repository_processor'
require 'cookstyle_runner/git_operations'
require 'cookstyle_runner/github_pr_manager'
require 'cookstyle_runner/authentication'
require 'octokit'
require 'logger'
require 'tmpdir'

# Mark these as integration tests
# rubocop:disable Metrics/BlockLength
RSpec.describe CookstyleRunner::RepositoryProcessor, :integration do
  let(:logger) { instance_double(Logger, info: nil, warn: nil, error: nil, debug: nil) }
  # Assume valid credentials/token generation for now
  let(:github_token) { 'mock_gh_token' }
  let(:default_branch) { 'main' } # Or 'master', depending on the repo
  let(:branch_name) { "cookstyle-fixes-#{Time.now.strftime('%Y%m%d%H%M%S')}" } # Example branch name
  let(:commit_message) { 'chore: Auto-apply cookstyle fixes' }
  let(:pr_title) { commit_message }
  let(:pr_body) { 'Automated Cookstyle fixes applied by the Cookstyle Runner bot.' }
  let(:tmp_dir) { Dir.mktmpdir } # Create a temporary directory for cloning

  # Mock Octokit client
  let(:octokit_client) { instance_double(Octokit::Client) }

  before do
    # Stub authentication methods to return our mock client and token
    allow(CookstyleRunner::Authentication).to receive(:authenticate_app).and_return(octokit_client)
    allow(CookstyleRunner::Authentication).to receive(:authenticate_installation).and_return(octokit_client)
    # Stub the PRManager's client retrieval
    allow_any_instance_of(CookstyleRunner::PRManager).to receive(:client).and_return(octokit_client)
    # Stub GitOperations to prevent actual cloning for now, just return the tmp path
    allow(CookstyleRunner::GitOperations).to receive(:clone_repo).and_return(true)
    allow(CookstyleRunner::GitOperations).to receive(:get_default_branch).and_return(default_branch)

    # Prevent actual file operations in tests unless specifically allowed
    allow(FileUtils).to receive(:remove_entry_secure).with(any_args)
  end

  after do
    # Clean up the temporary directory
    FileUtils.remove_entry_secure(tmp_dir) if Dir.exist?(tmp_dir)
  end

  context 'when processing a repository that needs fixes (e.g., sous-chefs/apt)' do
    let(:repo_owner) { 'sous-chefs' }
    let(:repo_name) { 'apt' }
    let(:repo_context) do
      CookstyleRunner::RepoContext.new(
        repo_name: repo_name,
        github_token: github_token,
        base_dir: tmp_dir, # Use tmp dir for repo path
        logger: logger
      )
    end
    let(:processor) { described_class.new(repo_context) }

    it 'runs cookstyle, commits changes, and attempts to create a pull request' do
      # 1. Mock CookstyleRunner to indicate fixes were made
      expect(CookstyleRunner::CookstyleRunner).to receive(:run_cookstyle)
        .with(repo_context.repo_dir, true) # Expect autocorrect to be true
        .and_return(true) # Simulate fixes applied

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
