# frozen_string_literal: true
# typed: false

require 'spec_helper'
require 'cookstyle_runner/github_pr_manager'
require 'octokit'
require 'stringio'

RSpec.describe CookstyleRunner::GitHubPRManager do
  subject(:pr_manager) { described_class.new(settings, github_client) }

  let(:github_client) { instance_double(Octokit::Client) }
  let(:settings) { Object.const_get('Settings') } # Use real Config::Options from test.yml

  describe '#initialize' do
    it 'initializes with settings and github_client' do
      expect(pr_manager.settings).to eq(settings)
      expect(pr_manager.github_client).to eq(github_client)
    end

    it 'sets instance variables from settings' do
      # Values from config/settings (default.yml or test.yml)
      expect(pr_manager.owner).to eq('sous-chefs')
      expect(pr_manager.branch_name).to eq('cookstyle/fixes')
      expect(pr_manager.pr_title).to eq('Cookstyle Fixes')
      expect(pr_manager.issue_labels).to eq(%w[cookstyle automated])
      expect(pr_manager.create_manual_fix_issues).to be true
    end
  end

  describe '#create_pull_request' do
    let(:repository) { 'test-org/test-cookbook' }
    let(:base_branch) { 'main' }
    let(:head_branch) { 'cookstyle-fixes' }
    let(:title) { 'Fix Cookstyle violations' }
    let(:body) { 'This PR fixes cookstyle violations' }
    let(:pr_response) { double('PR', number: 123) }

    before do
      allow(github_client).to receive_messages(
        pull_requests: [],
        create_pull_request: pr_response,
        add_labels_to_an_issue: nil
      )
    end

    it 'creates a pull request successfully' do
      result = pr_manager.create_pull_request(repository, base_branch, head_branch, title, body)

      expect(result).to be true
      expect(github_client).to have_received(:create_pull_request).with(
        'test-org/test-cookbook',
        'main',
        'cookstyle-fixes',
        'Fix Cookstyle violations',
        'This PR fixes cookstyle violations'
      )
    end

    it 'adds labels to the pull request' do
      pr_manager.create_pull_request(repository, base_branch, head_branch, title, body)

      expect(github_client).to have_received(:add_labels_to_an_issue).with(
        'test-org/test-cookbook',
        123,
        %w[cookstyle automated]
      )
    end

    context 'when PR creation fails' do
      before do
        allow(github_client).to receive(:create_pull_request)
          .and_raise(StandardError.new('API error'))
      end

      it 'returns false and logs error' do
        result = pr_manager.create_pull_request(repository, base_branch, head_branch, title, body)

        expect(result).to be false
      end
    end

    context 'with GitHub URL repository format' do
      let(:repository) { 'https://github.com/test-org/test-cookbook' }

      it 'extracts repo name from URL' do
        pr_manager.create_pull_request(repository, base_branch, head_branch, title, body)

        expect(github_client).to have_received(:create_pull_request).with(
          'test-org/test-cookbook',
          anything,
          anything,
          anything,
          anything
        )
      end
    end

    context 'with simple repo name' do
      let(:repository) { 'test-cookbook' }

      it 'prepends owner to repo name' do
        pr_manager.create_pull_request(repository, base_branch, head_branch, title, body)

        expect(github_client).to have_received(:create_pull_request).with(
          'sous-chefs/test-cookbook',
          anything,
          anything,
          anything,
          anything
        )
      end
    end
  end

  describe '#create_issue' do
    let(:repository) { 'test-org/test-cookbook' }
    let(:title) { 'Manual Cookstyle fixes needed' }
    let(:body) { 'These violations require manual intervention' }
    let(:issue_response) { double('Issue', number: 456) }

    before do
      allow(github_client).to receive(:create_issue).and_return(issue_response)
      allow(github_client).to receive(:add_labels_to_an_issue)
    end

    it 'creates an issue successfully' do
      result = pr_manager.create_issue(repository, title, body)

      expect(result).to be true
      expect(github_client).to have_received(:create_issue).with(
        'test-org/test-cookbook',
        'Manual Cookstyle fixes needed',
        'These violations require manual intervention'
      )
    end

    it 'adds labels to the issue' do
      pr_manager.create_issue(repository, title, body)

      expect(github_client).to have_received(:add_labels_to_an_issue).with(
        'test-org/test-cookbook',
        456,
        %w[cookstyle automated]
      )
    end

    context 'when issue creation fails' do
      before do
        allow(github_client).to receive(:create_issue)
          .and_raise(StandardError.new('API error'))
      end

      it 'returns false and logs error' do
        result = pr_manager.create_issue(repository, title, body)

        expect(result).to be false
      end
    end

    context 'with GitHub URL repository format' do
      let(:repository) { 'https://github.com/test-org/test-cookbook.git' }

      it 'extracts repo name from URL' do
        pr_manager.create_issue(repository, title, body)

        expect(github_client).to have_received(:create_issue).with(
          'test-org/test-cookbook.git',
          anything,
          anything
        )
      end
    end

    context 'with simple repo name' do
      let(:repository) { 'test-cookbook' }

      it 'prepends owner to repo name' do
        pr_manager.create_issue(repository, title, body)

        expect(github_client).to have_received(:create_issue).with(
          'sous-chefs/test-cookbook',
          anything,
          anything
        )
      end
    end
  end

  describe '#extract_repo_name (private method)' do
    # Testing private method through public interface
    let(:issue_response) { double('Issue', number: 1) }

    before do
      allow(github_client).to receive(:create_issue).and_return(issue_response)
      allow(github_client).to receive(:add_labels_to_an_issue)
    end

    context 'with GitHub HTTPS URL' do
      it 'extracts owner/repo from URL' do
        repository = 'https://github.com/sous-chefs/apache2'

        pr_manager.create_issue(repository, 'title', 'body')

        expect(github_client).to have_received(:create_issue).with(
          'sous-chefs/apache2',
          anything,
          anything
        )
      end
    end

    context 'with owner/repo format' do
      it 'uses the format as-is' do
        repository = 'sous-chefs/nginx'

        pr_manager.create_issue(repository, 'title', 'body')

        expect(github_client).to have_received(:create_issue).with(
          'sous-chefs/nginx',
          anything,
          anything
        )
      end
    end

    context 'with simple repo name' do
      it 'prepends the owner' do
        repository = 'mysql'

        pr_manager.create_issue(repository, 'title', 'body')

        expect(github_client).to have_received(:create_issue).with(
          'sous-chefs/mysql',
          anything,
          anything
        )
      end
    end
  end
end
