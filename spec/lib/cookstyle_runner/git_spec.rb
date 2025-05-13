# frozen_string_literal: true

require 'spec_helper'
require 'cookstyle_runner/git'
require 'cookstyle_runner/authentication'
require 'logger'
require 'fileutils'
require 'tmpdir'

# rubocop:disable Metrics/BlockLength
RSpec.describe CookstyleRunner::Git do
  let(:repo_name) { 'test-repo' }
  let(:owner) { 'test-owner' }
  let(:repo_dir) { File.join(Dir.pwd, 'tmp', 'spec', repo_name) }
  # Use a real Logger instance to satisfy Sorbet type checking
  let(:logger) { Logger.new(StringIO.new) }
  # Use a real RepoContext instance but with the exact repo_dir expected by tests
  let(:context) do
    CookstyleRunner::Git::RepoContext.new(
      repo_name: repo_name,
      owner: owner,
      logger: logger,
      repo_dir: repo_dir # Override the default path construction
    )
  end
  let(:branch) { 'main' }
  let(:app_id) { 'app123' }
  let(:installation_id) { 'install456' }
  let(:private_key) { 'fake_key_content_or_path' }
  let(:fake_token) { 'ghs_faketoken123' }
  let(:authed_url) { "https://x-access-token:#{fake_token}@github.com/#{owner}/#{repo_name}.git" }
  let(:mock_git_repo) { instance_double(Git::Base) }

  before do
    FileUtils.rm_rf(repo_dir)
    FileUtils.mkdir_p(File.dirname(repo_dir))
  end

  after do
    FileUtils.rm_rf(repo_dir)
  end

  describe '.clone_or_update_repo' do
    before do
      # Mock the Authentication module's authenticated_url method
      allow(CookstyleRunner::Authentication).to receive(:authenticated_url)
        .with(any_args)
        .and_return(authed_url)

      allow(Git).to receive_messages(clone: mock_git_repo, open: mock_git_repo)

      allow(mock_git_repo).to receive_messages(fetch: nil, checkout: nil, pull: nil, clean: nil)
    end

    context 'when repo directory does not exist' do
      before do
        allow(Dir).to receive(:exist?).and_call_original
        allow(Dir).to receive(:exist?).with(File.join(repo_dir, '.git')).and_return(false)
      end

      it 'clones the repository using the authenticated URL' do
        # The expected URL format should come from the Authentication module
        allow(Git).to receive(:clone).with(authed_url, repo_dir).and_return(mock_git_repo)
        expect(described_class).not_to have_received(:update_repo)
        expect(mock_git_repo).to have_received(:checkout).with(branch)

        result = described_class.clone_or_update_repo(context, { branch_name: branch })
        expect(result).to eq(mock_git_repo)
      end

      it 'handles Git::Error during checkout after clone' do
        allow(Git).to receive(:clone).with(authed_url, repo_dir).and_return(mock_git_repo)
        allow(mock_git_repo).to receive(:checkout).with(branch).and_raise(Git::Error, 'branch not found')

        expect(logger).to have_received(:warn).with(/Branch #{branch} does not exist yet/)
        result = described_class.clone_or_update_repo(context, { branch_name: branch })
        expect(result).to eq(mock_git_repo)
      end
    end

    context 'when repo directory exists' do
      before do
        allow(Dir).to receive(:exist?).and_call_original
        allow(Dir).to receive(:exist?).with(File.join(repo_dir, '.git')).and_return(true)
        allow(Git).to receive(:open).with(repo_dir).and_return(mock_git_repo)
      end

      it 'updates the existing repository' do
        allow(Git).not_to receive(:clone)
        allow(Git).to receive(:open).with(repo_dir).and_return(mock_git_repo)
        allow(mock_git_repo).to receive(:fetch).with('origin')
        allow(mock_git_repo).to receive(:checkout).with(branch)
        allow(mock_git_repo).to receive(:pull).with('origin', branch)
        allow(mock_git_repo).to receive(:clean).with(force: true, d: true, f: true)

        result = described_class.clone_or_update_repo(context, { branch_name: branch })
        expect(result).to eq(mock_git_repo)
      end
    end

    context 'when authentication fails' do
      it 'logs an error and exits if Authentication fails' do
        allow(CookstyleRunner::Authentication).to receive(:authenticated_url)
          .with(any_args)
          .and_raise(StandardError.new('Auth error'))
        expect(logger).to have_received(:error).with(/Authentication failed/)
        expect do
          described_class.clone_or_update_repo(context, { branch_name: branch })
        end.to raise_error(SystemExit)
      end

      it 'logs an error and returns nil if clone fails' do
        allow(Dir).to receive(:exist?).with(File.join(repo_dir, '.git')).and_return(false)
        allow(Git).to receive(:clone).and_raise(StandardError, 'Clone failed')
        expect(logger).to have_received(:error).with('Error ensuring repo latest state: Clone failed')
        result = described_class.clone_or_update_repo(context, { branch_name: branch })
        expect(result).to be_nil
      end

      it 'logs an error and returns nil if update fails' do
        allow(Dir).to receive(:exist?).with(File.join(repo_dir, '.git')).and_return(true)
        allow(Git).to receive(:open).with(context.repo_dir).and_return(mock_git_repo)
        allow(mock_git_repo).to receive(:fetch).and_raise(StandardError, 'Fetch failed')
        expect(logger).to have_received(:error).with("Error updating repo #{repo_name}: Fetch failed")
        expect(logger).not_to have_received(:error).with(/Error ensuring repo latest state/)
        result = described_class.clone_or_update_repo(context, { branch_name: branch })
        expect(result).to be_nil
      end
    end
  end

  describe '.checkout_branch' do
    let(:branch_to_checkout) { 'feature-branch' }

    before do
      allow(Git).to receive(:open).with(repo_dir).and_return(mock_git_repo)
    end

    context 'when branch exists' do
      it 'checks out the existing branch successfully' do
        expect(mock_git_repo).to have_received(:checkout).with(branch_to_checkout)
        expect(mock_git_repo).not_to have_received(:branch)
        expect(logger).not_to have_received(:info)
        expect(described_class.checkout_branch(context, branch_to_checkout)).to be true
      end
    end

    context 'when branch does not exist' do
      let(:mock_new_branch) { instance_double(Git::Branch) }

      it 'creates and checks out the new branch' do
        allow(mock_git_repo).to receive(:checkout).with(branch_to_checkout).and_raise(Git::Error, 'branch not found')
        expect(logger).to have_received(:info).with("Branch #{branch_to_checkout} not found, creating new branch.")
        expect(mock_git_repo).to have_received(:branch).with(branch_to_checkout).and_return(mock_new_branch)
        expect(mock_new_branch).to have_received(:checkout)

        expect(described_class.checkout_branch(context, branch_to_checkout)).to be true
      end
    end

    context 'when there is an error' do
      it 'logs an error and returns false if Git.open fails' do
        allow(Git).to receive(:open).with(repo_dir).and_raise(StandardError, 'Cannot open repo')
        expect(logger).to have_received(:error).with("Git checkout failed for branch #{branch_to_checkout}: Cannot open repo")
        expect(described_class.checkout_branch(context, branch_to_checkout)).to be false
      end

      it 'logs an error and returns false if checkout fails unexpectedly' do
        allow(mock_git_repo).to receive(:checkout).with(branch_to_checkout).and_raise(StandardError,
                                                                                      'Unexpected checkout error')
        expect(logger).to have_received(:error)
          .with("Git checkout failed for branch #{branch_to_checkout}: Unexpected checkout error")
        expect(described_class.checkout_branch(context, branch_to_checkout)).to be false
      end

      it 'logs an error and returns false if branch creation fails' do
        allow(mock_git_repo).to receive(:checkout).with(branch_to_checkout).and_raise(Git::Error, 'branch not found')
        allow(mock_git_repo).to receive(:branch).with(branch_to_checkout).and_raise(StandardError,
                                                                                    'Cannot create branch')
        expect(logger).to have_received(:info).with("Branch #{branch_to_checkout} not found, creating new branch.")
        expect(logger).to have_received(:error)
          .with("Git checkout failed for branch #{branch_to_checkout}: Cannot create branch")
        expect(described_class.checkout_branch(context, branch_to_checkout)).to be false
      end
    end
  end

  describe '.current_commit_sha' do
    let(:expected_sha) { 'abcdef1234567890abcdef1234567890abcdef12' }
    let(:mock_git_object) { instance_double(Git::Object::Commit, sha: expected_sha) }

    before do
      allow(Git).to receive(:open).with(repo_dir).and_return(mock_git_repo)
    end

    it 'returns the current commit SHA successfully' do
      allow(mock_git_repo).to receive(:object).with('HEAD').and_return(mock_git_object)
      expect(described_class.current_commit_sha(context)).to eq(expected_sha)
    end

    it 'logs an error and returns nil if Git.open fails' do
      allow(Git).to receive(:open).with(repo_dir).and_raise(StandardError, 'Cannot open repo')
      expect(logger).to have_received(:error).with('Failed to get current commit SHA: Cannot open repo')
      expect(described_class.current_commit_sha(context)).to be_nil
    end

    it 'logs an error and returns nil if object call fails' do
      allow(mock_git_repo).to receive(:object).with('HEAD').and_raise(Git::Error, 'Failed object lookup')
      expect(logger).to have_received(:error).with('Failed to get current commit SHA: Failed object lookup')
      expect(described_class.current_commit_sha(context)).to be_nil
    end
  end

  describe '.changes_to_commit?' do
    let(:mock_status) { instance_double(Git::Status) }

    before do
      allow(Git).to receive(:open).with(repo_dir).and_return(mock_git_repo)
      allow(mock_git_repo).to receive(:status).and_return(mock_status)
      allow(mock_status).to receive(:deleted).and_return({})
    end

    context 'when there are changed files' do
      it 'returns true' do
        allow(mock_status).to receive_messages(changed: { 'file1.rb' => instance_double(Git::Status::StatusFile) }, added: {})
        expect(described_class.changes_to_commit?(context)).to be true
      end
    end

    context 'when there are added files' do
      it 'returns true' do
        allow(mock_status).to receive_messages(changed: {}, added: { 'new_file.rb' => instance_double(Git::Status::StatusFile) })
        expect(described_class.changes_to_commit?(context)).to be true
      end
    end

    context 'when there are deleted files' do
      it 'returns true' do
        deleted_file_status = instance_double(Git::Status::StatusFile)
        allow(mock_status).to receive_messages(changed: {}, added: {}, deleted: { 'deleted_file.rb' => deleted_file_status })
        expect(described_class.changes_to_commit?(context)).to be true
      end
    end

    context 'when there are no changed or added files' do
      it 'returns false' do
        allow(mock_status).to receive_messages(changed: {}, added: {})
        expect(described_class.changes_to_commit?(context)).to be false
      end
    end

    context 'when there is an error' do
      it 'logs an error and returns false if Git.open fails' do
        allow(Git).to receive(:open).with(repo_dir).and_raise(StandardError, 'Cannot open repo')
        expect(logger).to have_received(:error).with('Failed to check for changes to commit: Cannot open repo')
        expect(described_class.changes_to_commit?(context)).to be false
      end

      it 'logs an error and returns false if status check fails' do
        allow(mock_git_repo).to receive(:status).and_raise(Git::Error, 'Status fail')
        expect(logger).to have_received(:error).with('Failed to check for changes to commit: Status fail')
        expect(described_class.changes_to_commit?(context)).to be false
      end
    end
  end

  describe '.commit_and_push_changes' do
    let(:commit_message) { 'Test commit message' }
    let(:branch) { 'test-branch' }
    let(:remote) { 'origin' }
    let(:mock_github_token) { 'test-token-123' }
    let(:context) do
      instance_double(CookstyleRunner::Git::RepoContext,
                      repo_name: 'test-repo',
                      owner: 'test-owner',
                      repo_dir: repo_dir,
                      logger: logger,
                      github_token: mock_github_token)
    end
    let(:mock_remote_obj) { instance_double(Git::Remote, name: remote, remove: true) }

    before do
      allow(Git).to receive(:open).with(repo_dir).and_return(mock_git_repo)
      allow(context).to receive(:logger).and_return(logger)
      allow(mock_git_repo).to receive(:add).with(all: true)
      allow(mock_git_repo).to receive(:commit).with(commit_message)
      allow(mock_git_repo).to receive(:push).with(remote, branch, force: true)
    end

    it 'successfully commits and pushes changes' do
      mock_remote_obj = instance_double(Git::Remote, name: remote, remove: true)
      expect(mock_git_repo).to have_received(:add).with(all: true)
      expect(mock_git_repo).to have_received(:commit).with(commit_message)
      expect(mock_git_repo).to have_received(:remotes).and_return([mock_remote_obj])
      expect(mock_git_repo).to have_received(:remote).with(remote).and_return(mock_remote_obj)
      expect(mock_remote_obj).to have_received(:remove)
      expected_url = "https://x-access-token:#{context.github_token}" \
                     "@github.com/#{context.repo_name}.git"
      expect(mock_git_repo).to have_received(:add_remote).with(remote, expected_url)
      expect(mock_git_repo).to have_received(:fetch).with(remote)
      expect(mock_git_repo).to have_received(:push).with(remote, branch, force: true)

      expect(described_class.commit_and_push_changes(context, branch, commit_message)).to be true
    end

    it 'logs an error and returns false if commit fails' do
      allow(mock_git_repo).to receive(:commit).with(commit_message).and_raise(Git::Error, 'Commit fail')
      expect(logger).to have_received(:error).with("Error committing changes in #{repo_dir}: Commit fail")
      expect(mock_git_repo).not_to have_received(:remotes)
      expect(mock_git_repo).not_to have_received(:add_remote)
      expect(mock_git_repo).not_to have_received(:fetch)
      expect(mock_git_repo).not_to have_received(:push)
      expect(described_class.commit_and_push_changes(context, branch, commit_message)).to be false
    end

    it 'logs an error and returns false if push fails' do
      mock_remote_obj = instance_double(Git::Remote, name: remote, remove: true)
      allow(mock_git_repo).to receive(:remotes).and_return([mock_remote_obj])
      allow(mock_git_repo).to receive(:remote).with(remote).and_return(mock_remote_obj)
      allow(mock_git_repo).to receive(:add_remote).with(remote, anything)
      allow(mock_git_repo).to receive(:fetch).with(remote)

      allow(mock_git_repo).to receive(:push).with(remote, branch, force: true).and_raise(Git::Error, 'Push fail')
      expect(logger).to have_received(:error)
        .with("Error pushing to #{remote}/#{branch} for #{repo_name}: Push fail")
      expect(described_class.commit_and_push_changes(context, branch, commit_message)).to be false
    end

    it 'logs an error and returns false if Git.open fails' do
      allow(Git).to receive(:open).with(repo_dir).and_raise(StandardError, 'Open fail')
      expect(logger).to have_received(:error).with('Failed to commit and push changes: Open fail')
      expect(mock_git_repo).not_to have_received(:add)
      expect(mock_git_repo).not_to have_received(:commit)
      expect(mock_git_repo).not_to have_received(:remotes)
      expect(mock_git_repo).not_to have_received(:add_remote)
      expect(mock_git_repo).not_to have_received(:fetch)
      expect(mock_git_repo).not_to have_received(:push)
      expect(described_class.commit_and_push_changes(context, branch, commit_message)).to be false
    end
  end
end
# rubocop:enable Metrics/BlockLength
