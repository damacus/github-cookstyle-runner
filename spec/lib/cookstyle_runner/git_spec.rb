# frozen_string_literal: true

require 'spec_helper'
require 'cookstyle_runner/git'
require 'logger'
require 'stringio'
require 'git'

RSpec.describe CookstyleRunner::Git do
  let(:logger) { Logger.new(StringIO.new) }
  let(:context) do
    CookstyleRunner::Git::RepoContext.new(
      repo_name: 'test-cookbook',
      owner: 'test-org',
      logger: logger,
      repo_dir: '/tmp/test-repo',
      repo_url: 'https://github.com/test-org/test-cookbook.git'
    )
  end

  describe 'CookstyleRunner::Git::RepoContext' do
    it 'initializes with required parameters' do
      expect(context.repo_name).to eq('test-cookbook')
      expect(context.owner).to eq('test-org')
      expect(context.logger).to eq(logger)
      expect(context.repo_dir).to eq('/tmp/test-repo')
      expect(context.repo_url).to eq('https://github.com/test-org/test-cookbook.git')
    end

    it 'generates default repo_url from owner and repo_name' do
      ctx = CookstyleRunner::Git::RepoContext.new(
        repo_name: 'my-repo',
        owner: 'my-org',
        logger: logger
      )
      expect(ctx.repo_url).to eq('https://github.com/my-org/my-repo.git')
    end

    it 'generates default repo_dir from base_dir, owner and repo_name' do
      Dir.mktmpdir do |tmpdir|
        ctx = CookstyleRunner::Git::RepoContext.new(
          repo_name: 'my-repo',
          owner: 'my-org',
          logger: logger,
          base_dir: tmpdir
        )
        expect(ctx.repo_dir).to eq(File.join(tmpdir, 'my-org', 'my-repo'))
      end
    end

    it 'accepts optional authentication parameters' do
      ctx = CookstyleRunner::Git::RepoContext.new(
        repo_name: 'test',
        owner: 'org',
        logger: logger,
        github_token: 'token123',
        app_id: 'app456',
        installation_id: 789,
        private_key: 'key-content'
      )
      expect(ctx.github_token).to eq('token123')
      expect(ctx.app_id).to eq('app456')
      expect(ctx.installation_id).to eq(789)
      expect(ctx.private_key).to eq('key-content')
    end
  end

  describe '.repo_exists?' do
    it 'returns true when repository exists' do
      repo = instance_double(Git::Base)
      allow(Git).to receive(:open).with(context.repo_dir).and_return(repo)
      expect(described_class.repo_exists?(context)).to be true
    end

    it 'returns false when repository does not exist' do
      allow(Git).to receive(:open).with(context.repo_dir).and_raise(StandardError)
      expect(described_class.repo_exists?(context)).to be false
    end
  end

  describe '.changes?' do
    let(:repo) { instance_double(Git::Base) }
    let(:status) { instance_double(Git::Status) }

    it 'returns true when there are changed files' do
      allow(status).to receive_messages(changed: ['file.rb'], added: [], deleted: [])
      allow(repo).to receive(:status).and_return(status)

      expect(described_class.changes?(repo)).to be true
    end

    it 'returns true when there are added files' do
      allow(status).to receive_messages(changed: [], added: ['new_file.rb'], deleted: [])
      allow(repo).to receive(:status).and_return(status)

      expect(described_class.changes?(repo)).to be true
    end

    it 'returns true when there are deleted files' do
      allow(status).to receive_messages(changed: [], added: [], deleted: ['old_file.rb'])
      allow(repo).to receive(:status).and_return(status)

      expect(described_class.changes?(repo)).to be true
    end

    it 'returns false when there are no changes' do
      allow(status).to receive_messages(changed: [], added: [], deleted: [])
      allow(repo).to receive(:status).and_return(status)

      expect(described_class.changes?(repo)).to be false
    end
  end

  describe '.changes_to_commit?' do
    let(:repo) { instance_double(Git::Base) }
    let(:status) { instance_double(Git::Status) }

    before do
      allow(Git).to receive(:open).with(context.repo_dir).and_return(repo)
      allow(repo).to receive(:status).and_return(status)
    end

    it 'returns true when changes exist' do
      allow(status).to receive_messages(changed: ['file.rb'], added: [], deleted: [])

      expect(described_class.changes_to_commit?(context)).to be true
    end

    it 'returns false when no changes exist' do
      allow(status).to receive_messages(changed: [], added: [], deleted: [])

      expect(described_class.changes_to_commit?(context)).to be false
    end

    it 'returns false on error' do
      allow(Git).to receive(:open).and_raise(Git::Error.new('test error'))
      expect(described_class.changes_to_commit?(context)).to be false
    end
  end

  describe '.current_commit_sha' do
    let(:repo) { instance_double(Git::Base) }
    let(:head_object) { instance_double(Git::Object::Commit, sha: 'abc123def456') }

    it 'returns the current commit SHA' do
      allow(Git).to receive(:open).with(context.repo_dir).and_return(repo)
      allow(repo).to receive(:object).with('HEAD').and_return(head_object)

      expect(described_class.current_commit_sha(context)).to eq('abc123def456')
    end

    it 'returns nil on error' do
      allow(Git).to receive(:open).and_raise(StandardError.new('test error'))
      expect(described_class.current_commit_sha(context)).to be_nil
    end
  end

  describe '.latest_commit_sha' do
    let(:repo) { instance_double(Git::Base) }
    let(:head_object) { instance_double(Git::Object::Commit, sha: 'xyz789abc123') }

    it 'returns the latest commit SHA' do
      allow(Git).to receive(:open).with('/tmp/repo').and_return(repo)
      allow(repo).to receive(:object).with('HEAD').and_return(head_object)

      expect(described_class.latest_commit_sha('/tmp/repo', logger)).to eq('xyz789abc123')
    end

    it 'returns nil on error' do
      allow(Git).to receive(:open).and_raise(StandardError.new('test error'))
      expect(described_class.latest_commit_sha('/tmp/repo', logger)).to be_nil
    end
  end

  describe '.setup_git_config' do
    it 'configures git user name and email' do
      allow(Git).to receive(:global_config)

      result = described_class.setup_git_config(
        user_name: 'Test User',
        user_email: 'test@example.com',
        logger: logger
      )
      expect(result).to be true
      expect(Git).to have_received(:global_config).with('user.name', 'Test User')
      expect(Git).to have_received(:global_config).with('user.email', 'test@example.com')
    end

    it 'returns false on error' do
      allow(Git).to receive(:global_config).and_raise(StandardError.new('config error'))

      result = described_class.setup_git_config(
        user_name: 'Test User',
        user_email: 'test@example.com',
        logger: logger
      )
      expect(result).to be false
    end
  end

  describe '.authenticated_url' do
    it 'delegates to Authentication module' do
      allow(CookstyleRunner::Authentication).to receive(:authenticated_url)
        .with('test-org', 'test-cookbook', logger)
        .and_return('https://token@github.com/test-org/test-cookbook.git')

      result = described_class.authenticated_url(context)
      expect(result).to eq('https://token@github.com/test-org/test-cookbook.git')
      expect(CookstyleRunner::Authentication).to have_received(:authenticated_url)
        .with('test-org', 'test-cookbook', logger)
    end

    it 'exits on authentication failure' do
      allow(CookstyleRunner::Authentication).to receive(:authenticated_url)
        .and_raise(StandardError.new('auth failed'))

      expect { described_class.authenticated_url(context) }.to raise_error(SystemExit)
    end
  end

  describe '.remove_origin_remote_if_exists' do
    let(:repo) { instance_double(Git::Base) }
    let(:remote) { instance_double(Git::Remote, name: 'origin') }

    it 'removes existing remote' do
      remote_obj = instance_double(Git::Remote, remove: true)
      allow(repo).to receive(:remotes).and_return([remote])
      allow(repo).to receive(:remote).with('origin').and_return(remote_obj)

      described_class.remove_origin_remote_if_exists(repo, 'origin', context)
      expect(repo).to have_received(:remote).with('origin')
    end

    it 'does nothing when remote does not exist' do
      allow(repo).to receive(:remotes).and_return([])
      allow(repo).to receive(:remote)

      described_class.remove_origin_remote_if_exists(repo, 'origin', context)
      expect(repo).not_to have_received(:remote)
    end
  end

  describe '.add_and_commit_changes' do
    let(:repo) { instance_double(Git::Base) }
    let(:status) { instance_double(Git::Status) }

    before do
      allow(Git).to receive(:open).with(context.repo_dir).and_return(repo)
      allow(repo).to receive(:status).and_return(status)
    end

    it 'returns false when no changes to commit' do
      allow(status).to receive_messages(changed: [], added: [], deleted: [])

      result = described_class.add_and_commit_changes(context, 'test commit')
      expect(result).to be false
    end

    it 'adds and commits changes when changes exist' do
      allow(status).to receive_messages(changed: ['file.rb'], added: [], deleted: [])
      allow(repo).to receive(:add).with(all: true)
      commit_result = 'commit_sha_abc123'
      allow(repo).to receive(:commit).with('test commit').and_return(commit_result)

      result = described_class.add_and_commit_changes(context, 'test commit')
      expect(result).to eq(commit_result)
      expect(repo).to have_received(:add).with(all: true)
      expect(repo).to have_received(:commit).with('test commit')
    end

    it 'returns false on error' do
      allow(status).to receive_messages(changed: ['file.rb'], added: [], deleted: [])
      allow(repo).to receive(:add).and_raise(StandardError.new('add failed'))

      result = described_class.add_and_commit_changes(context, 'test commit')
      expect(result).to be false
    end
  end

  describe '.create_branch' do
    let(:repo) { instance_double(Git::Base) }
    let(:config) do
      {
        branch_name: 'feature-branch',
        git_user_name: 'Test User',
        git_user_email: 'test@example.com'
      }
    end

    it 'creates and checks out a new branch' do
      allow(Git).to receive(:global_config)
      allow(Git).to receive(:open).with(context.repo_dir).and_return(repo)
      allow(repo).to receive(:branches).and_return([])
      branch = instance_double(Git::Branch)
      allow(repo).to receive(:branch).with('feature-branch').and_return(branch)
      allow(branch).to receive(:create)
      allow(branch).to receive(:checkout)

      result = described_class.create_branch(context, config, logger)
      expect(result).to be true
      expect(branch).to have_received(:create)
      expect(branch).to have_received(:checkout)
    end

    it 'returns false on error' do
      allow(Git).to receive(:global_config)
      allow(Git).to receive(:open).and_raise(Git::Error.new('branch error'))

      result = described_class.create_branch(context, config, logger)
      expect(result).to be false
    end
  end

  describe '.checkout_branch' do
    let(:repo) { instance_double(Git::Base) }

    before do
      allow(Git).to receive(:open).with(context.repo_dir).and_return(repo)
    end

    it 'checks out existing branch' do
      allow(repo).to receive(:checkout).with('existing-branch')

      result = described_class.checkout_branch(context, 'existing-branch')
      expect(result).to be true
      expect(repo).to have_received(:checkout).with('existing-branch')
    end

    it 'creates and checks out new branch when branch does not exist' do
      allow(repo).to receive(:checkout).and_raise(Git::Error.new('branch not found'))
      branch = instance_double(Git::Branch)
      allow(repo).to receive(:branch).with('new-branch').and_return(branch)
      allow(branch).to receive(:checkout)

      result = described_class.checkout_branch(context, 'new-branch')
      expect(result).to be true
      expect(branch).to have_received(:checkout)
    end

    it 'returns false on error' do
      allow(repo).to receive(:checkout).and_raise(StandardError.new('checkout error'))

      result = described_class.checkout_branch(context, 'branch')
      expect(result).to be false
    end
  end

  describe '.clone_or_update_repo' do
    let(:config) { { branch_name: 'main' } }

    it 'updates repo when it exists' do
      allow(described_class).to receive(:repo_exists?).with(context).and_return(true)
      allow(described_class).to receive(:update_repo).with(context, 'main')

      described_class.clone_or_update_repo(context, config)
      expect(described_class).to have_received(:update_repo).with(context, 'main')
    end

    it 'clones repo when it does not exist' do
      allow(described_class).to receive(:repo_exists?).with(context).and_return(false)
      allow(described_class).to receive(:authenticated_url).with(context).and_return('https://auth-url')
      allow(described_class).to receive(:clone_repo).with(context, 'https://auth-url', 'main')

      described_class.clone_or_update_repo(context, config)
      expect(described_class).to have_received(:clone_repo).with(context, 'https://auth-url', 'main')
    end

    it 'returns nil on error' do
      allow(described_class).to receive(:repo_exists?).and_raise(StandardError.new('error'))

      result = described_class.clone_or_update_repo(context, config)
      expect(result).to be_nil
    end

    it 'reraises SystemExit for authentication failures' do
      allow(described_class).to receive(:repo_exists?).and_raise(SystemExit.new(1))

      expect { described_class.clone_or_update_repo(context, config) }.to raise_error(SystemExit)
    end
  end
end
