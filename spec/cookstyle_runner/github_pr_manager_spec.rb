# frozen_string_literal: true

require 'spec_helper'
require 'cookstyle_runner/github_pr_manager'
require 'cookstyle_runner/git_operations'
require 'cookstyle_runner/github_api'
require 'logger'
require 'ostruct'

RSpec.describe CookstyleRunner::GitHubPRManager do
  let(:config) do
    {
      owner: 'test-owner',
      branch_name: 'test-branch',
      pr_title: 'Test PR Title',
      pr_body: 'Test PR Body',
      git_name: 'Test User',
      git_email: 'test@example.com',
      manage_changelog: false, # Default to false for simplicity first
      changelog_location: 'CHANGELOG.md',
      changelog_marker: '<!-- marker -->',
      log_level: 'info'
    }
  end
  let(:logger) { instance_double(Logger, info: nil, warn: nil, error: nil, debug: nil) }
  let(:github_token) { 'mock-gh-token' }
  let(:repo_name) { 'test-owner/test-repo' }
  let(:repo_dir) { '/tmp/test-repo' }
  let(:cookstyle_output) { "Some cookstyle output\nWith offenses" }
  let(:octokit_client) { instance_double(Octokit::Client) }
  let(:mock_pr_details) { { html_url: 'https://github.com/test-owner/test-repo/pull/1' } }

  # Subject under test
  let(:manager) { described_class.new(config, logger, github_token) }

  before do
    # Mock the GitHub API client retrieval
    allow(CookstyleRunner::GitHubAPI).to receive(:client).with(github_token).and_return(octokit_client)

    # Stub Dir.exist? and Dir.chdir by default
    allow(Dir).to receive(:exist?).and_return(true) # Assume dir exists unless specified
    allow(Dir).to receive(:chdir).with(repo_dir).and_yield # Allow chdir to work

    # Stub GitOperations class methods by default
    allow(CookstyleRunner::GitOperations).to receive(:changes_to_commit?).and_return(true)
    allow(CookstyleRunner::GitOperations).to receive(:create_branch).and_return(true)
    allow(CookstyleRunner::GitOperations).to receive(:update_changelog).and_return(true)
    allow(CookstyleRunner::GitOperations).to receive(:commit_and_push_changes).and_return(true)
    allow(CookstyleRunner::GitOperations).to receive(:create_empty_commit).and_return(true) # Stub even if not used in scenario

    # Stub the Octokit client's PR creation
    allow(octokit_client).to receive(:create_pull_request).and_return(mock_pr_details)
  end

  describe '#create_pull_request' do
    context 'when creating an auto-fix pull request successfully' do
      let(:expected_commit_message) do
        "#{config[:pr_title]}\n\nSigned-off-by: #{config[:git_name]} <#{config[:git_email]}>"
      end

      it 'checks for changes, creates branch, commits, pushes, and creates PR' do
        # Expectations
        expect(Dir).to receive(:exist?).with(repo_dir).and_return(true)
        expect(Dir).to receive(:chdir).with(repo_dir).and_yield
        expect(CookstyleRunner::GitOperations).to receive(:changes_to_commit?)
          .with(logger).and_return(true)
        expect(manager).to receive(:create_branch).with(repo_name).and_call_original # Assuming create_branch is a private method we want to test indirectly or mock GitOps directly
        expect(CookstyleRunner::GitOperations).to receive(:create_branch)
          .with(repo_name, config[:branch_name], github_token, config[:owner], logger)
          .and_return(true)
        expect(CookstyleRunner::GitOperations).not_to receive(:update_changelog) # Since manage_changelog is false
        expect(CookstyleRunner::GitOperations).to receive(:commit_and_push_changes)
          .with(repo_name, config[:branch_name], expected_commit_message, github_token, config[:owner], logger)
          .and_return(true)
        expect(octokit_client).to receive(:create_pull_request)
          .with(repo_name, 'main', config[:branch_name], config[:pr_title], config[:pr_body]) # Assuming 'main' is default - need to check if this is fetched
          .and_return(mock_pr_details)

        # Execute
        success, pr_details = manager.create_pull_request(repo_name, repo_dir, cookstyle_output, false) # manual_fix = false

        # Verify
        expect(success).to be true
        expect(pr_details).to eq(mock_pr_details)
        expect(logger).to have_received(:info).with("Attempting to create pull request for #{repo_name}")
        expect(logger).to have_received(:info).with(/Pull request created successfully/) # Match partial message
      end

      # Add test for when manage_changelog: true later
    end

    # Add context for 'manual-fix' scenario
    # Add context for 'no changes' scenario
    # Add context for 'directory does not exist' scenario
    # Add context for 'Git operation failures' scenario
    # Add context for 'API failure' scenario
  end

  # Add describe block for private methods like create_branch if needed,
  # although testing via the public interface is often preferred.
end
