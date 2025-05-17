# frozen_string_literal: true

require 'spec_helper'
require 'cookstyle_runner/github_pr_manager'
require 'cookstyle_runner/git'
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
    allow(CookstyleRunner::GitHubAPI).to receive(:create_app_client).and_return(octokit_client)

    # Stub Dir.exist? and Dir.chdir by default
    allow(Dir).to receive(:exist?).and_return(true) # Assume dir exists unless specified
    allow(Dir).to receive(:chdir).with(repo_dir).and_yield # Allow chdir to work

    # Stub Git class methods by default
    # Use a context double for new API
    repo_context = instance_double(
      CookstyleRunner::Git::RepoContext,
      repo_name: repo_name,
      owner: config[:owner],
      logger: logger,
      repo_url: "https://github.com/#{config[:owner]}/#{repo_name}.git",
      repo_dir: repo_dir,
      github_token: github_token,
      app_id: nil,
      installation_id: nil,
      private_key: nil
    )
    allow(Git).to receive(:changes_to_commit?).with(repo_context).and_return(true)
    allow(Git).to receive(:update_changelog).with(repo_context, config[:changelog_location],
                                                  config[:changelog_marker]).and_return(true)
    allow(Git).to receive(:commit_and_push_changes).with(repo_context, config[:branch_name],
                                                         kind_of(String)).and_return(true)
    allow(Git).to receive(:create_empty_commit).with(repo_context, config[:branch_name],
                                                     kind_of(String)).and_return(true)
    allow(Dir).to receive(:exist?).with(repo_dir).and_return(true)
    allow(Dir).to receive(:chdir).with(repo_dir).and_yield
    allow(Git).to receive_messages(create_branch: true, checkout_branch: true, current_commit_sha: 'sha123', repo_exists?: true,
                                   clone_or_update_repo: true, setup_git_config: true, add_and_commit_changes: true, push_to_remote: true, setup_remote: true, get_authenticated_url: "https://github.com/#{config[:owner]}/#{repo_name}.git")

    # Stub the Octokit client's PR creation
    allow(octokit_client).to receive(:create_pull_request).and_return(mock_pr_details)
  end

  describe '#create_pull_request' do
    context 'when creating an auto-fix pull request successfully' do
      let(:expected_commit_message) do
        "#{config[:pr_title]}\n\nSigned-off-by: #{config[:git_name]} <#{config[:git_email]}>"
      end

      it 'checks for changes, creates branch, commits, pushes, and creates PR' do
        # Use the context double for all Git calls
        repo_context = instance_double(
          Git::RepoContext,
          repo_name: repo_name,
          owner: config[:owner],
          logger: logger,
          repo_url: "https://github.com/#{config[:owner]}/#{repo_name}.git",
          repo_dir: repo_dir,
          github_token: github_token,
          app_id: nil,
          installation_id: nil,
          private_key: nil
        )
        allow(Git).to receive(:changes_to_commit?).with(repo_context).and_return(true)
        allow(Git).to receive(:update_changelog).with(repo_context, config[:changelog_location],
                                                      config[:changelog_marker]).and_return(true)
        allow(Git).to receive(:commit_and_push_changes).with(repo_context, config[:branch_name],
                                                             kind_of(String)).and_return(true)
        allow(Git).to receive(:create_empty_commit).with(repo_context, config[:branch_name],
                                                         kind_of(String)).and_return(true)
        allow(Dir).to receive(:exist?).with(repo_dir).and_return(true)
        allow(Dir).to receive(:chdir).with(repo_dir).and_yield
        allow(Git).to receive_messages(create_branch: true, checkout_branch: true, current_commit_sha: 'sha123', repo_exists?: true,
                                       clone_or_update_repo: true, setup_git_config: true, add_and_commit_changes: true, push_to_remote: true, setup_remote: true, get_authenticated_url: "https://github.com/#{config[:owner]}/#{repo_name}.git")

        # Expectations
        expect(Dir).to receive(:exist?).with(repo_dir).and_return(true)
        expect(Dir).to receive(:chdir).with(repo_dir).and_yield
        expect(Git).to receive(:changes_to_commit?)
          .with(logger).and_return(true)
        expect(manager).to receive(:create_branch).with(repo_name).and_call_original # Assuming create_branch is a private method we want to test indirectly or mock GitOps directly
        expect(Git).to receive(:create_branch)
          .with(repo_name, config[:branch_name], github_token, config[:owner], logger)
          .and_return(true)
        expect(Git).not_to receive(:update_changelog) # Since manage_changelog is false
        expect(Git).to receive(:commit_and_push_changes)
          .with(repo_name, config[:branch_name], expected_commit_message, github_token, config[:owner], logger)
          .and_return(true)
        expect(octokit_client).to receive(:create_pull_request)
          .with(repo_name, 'main', config[:branch_name], config[:pr_title], config[:pr_body]) # Assuming 'main' is default - need to check if this is fetched
          .and_return(mock_pr_details)

        # Execute with context object instead of just repo_name/repo_dir
        success, pr_details = manager.create_pull_request(repo_context, cookstyle_output, false) # manual_fix = false

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
