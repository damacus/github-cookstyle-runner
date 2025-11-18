# frozen_string_literal: true
# typed: false

require 'spec_helper'
require 'cookstyle_runner/github_pr_helper'

RSpec.describe CookstyleRunner::GitHubPRHelper do
  let(:client) { instance_double(Octokit::Client) }
  let(:repo_name) { 'test-org/test-repo' }
  let(:branch_name) { 'feature-branch' }
  let(:logger) { instance_double(SemanticLogger::Logger) }

  before do
    allow(logger).to receive(:error)
  end

  describe '.find_existing_pr' do
    let(:pr_head_struct) { Struct.new(:ref) }
    let(:pr_struct) { Struct.new(:head) }
    let(:main_branch_pr) { pr_struct.new(pr_head_struct.new('main-branch')) }
    let(:feature_branch_pr) { pr_struct.new(pr_head_struct.new('feature-branch')) }
    let(:another_branch_pr) { pr_struct.new(pr_head_struct.new('another-branch')) }

    context 'when a matching PR exists' do
      before do
        allow(client).to receive(:pull_requests).and_return([main_branch_pr, feature_branch_pr, another_branch_pr])
      end

      it 'returns the matching PR' do
        result = described_class.find_existing_pr(client, repo_name, branch_name, logger)

        expect(result).to eq(feature_branch_pr)
        expect(client).to have_received(:pull_requests).with(repo_name, state: 'open')
      end
    end

    context 'when no matching PR exists' do
      before do
        allow(client).to receive(:pull_requests).and_return([main_branch_pr, another_branch_pr])
      end

      it 'returns nil' do
        result = described_class.find_existing_pr(client, repo_name, branch_name, logger)

        expect(result).to be_nil
      end
    end

    context 'when there are no open PRs' do
      before do
        allow(client).to receive(:pull_requests).and_return([])
      end

      it 'returns nil' do
        result = described_class.find_existing_pr(client, repo_name, branch_name, logger)

        expect(result).to be_nil
      end
    end

    context 'when API call fails' do
      before do
        allow(client).to receive(:pull_requests).and_raise(StandardError.new('API error'))
      end

      it 'returns nil and logs error' do
        result = described_class.find_existing_pr(client, repo_name, branch_name, logger)

        expect(result).to be_nil
        expect(logger).to have_received(:error).with('Error finding existing pull request', payload: {
                                                       repo: repo_name,
                                                       branch: branch_name,
                                                       error: 'API error'
                                                     })
      end
    end

    context 'when logger is not provided' do
      before do
        allow(client).to receive(:pull_requests).and_raise(StandardError.new('API error'))
      end

      it 'handles error gracefully without logger' do
        result = described_class.find_existing_pr(client, repo_name, branch_name, nil)

        expect(result).to be_nil
      end
    end
  end
end
