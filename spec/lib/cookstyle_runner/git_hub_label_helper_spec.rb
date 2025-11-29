# frozen_string_literal: true
# typed: false

require 'spec_helper'
require 'cookstyle_runner/github_label_helper'

RSpec.describe CookstyleRunner::GitHubLabelHelper do
  let(:client) { instance_double(Octokit::Client) }
  let(:repo_name) { 'test-org/test-repo' }
  let(:issue_number) { 123 }
  let(:labels) { %w[bug enhancement] }
  let(:logger) { instance_double(SemanticLogger::Logger) }

  before do
    allow(logger).to receive(:info)
    allow(logger).to receive(:debug)
    allow(logger).to receive(:error)
  end

  describe '.add_labels_safely' do
    context 'when labels array is empty' do
      before do
        allow(client).to receive(:labels_for_issue)
      end

      it 'returns true without calling the API' do
        result = described_class.add_labels_safely(client, repo_name, issue_number, [], logger)

        expect(result).to be true
        expect(client).not_to have_received(:labels_for_issue)
      end
    end

    context 'when labels need to be added' do
      before do
        allow(client).to receive(:labels_for_issue).and_return([])
        allow(client).to receive(:add_labels_to_an_issue)
      end

      it 'adds new labels successfully' do
        result = described_class.add_labels_safely(client, repo_name, issue_number, labels, logger)

        expect(result).to be true
        expect(client).to have_received(:labels_for_issue).with(repo_name, issue_number)
        expect(client).to have_received(:add_labels_to_an_issue).with(repo_name, issue_number, labels)
      end
    end

    context 'when some labels already exist' do
      let(:existing_label) { Struct.new(:name).new('bug') }

      before do
        allow(client).to receive(:labels_for_issue).and_return([existing_label])
        allow(client).to receive(:add_labels_to_an_issue)
      end

      it 'only adds new labels' do
        result = described_class.add_labels_safely(client, repo_name, issue_number, labels, logger)

        expect(result).to be true
        expect(client).to have_received(:add_labels_to_an_issue).with(repo_name, issue_number, ['enhancement'])
      end
    end

    context 'when API call fails' do
      before do
        allow(client).to receive(:labels_for_issue).and_raise(StandardError.new('API error'))
      end

      it 'returns false and logs error' do
        result = described_class.add_labels_safely(client, repo_name, issue_number, labels, logger)

        expect(result).to be false
        expect(logger).to have_received(:error)
      end
    end
  end

  describe '.update_pr_labels' do
    it 'delegates to add_labels_safely' do
      allow(client).to receive(:labels_for_issue).and_return([])
      allow(client).to receive(:add_labels_to_an_issue)

      result = described_class.update_pr_labels(client, repo_name, issue_number, labels, logger)

      expect(result).to be true
    end
  end
end
