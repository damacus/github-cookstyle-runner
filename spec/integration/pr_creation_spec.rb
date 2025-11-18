# typed: false
# frozen_string_literal: true

require 'spec_helper'
require_relative 'support/integration_helpers'

# rubocop:disable RSpec/DescribeClass, RSpec/PendingWithoutReason
RSpec.describe 'PR and Issue Creation', :integration do
  include IntegrationHelpers

  let(:test_repo) { 'test-owner/test-repo' }

  describe 'creating pull requests for auto-correctable fixes' do
    # TODO: Record VCR cassette for this test
    # To record: Set GITHUB_TOKEN and run with VCR_RECORD_MODE=all
    xit 'creates a PR when auto-correctable offenses are found (requires VCR cassette)',
        vcr: { cassette_name: 'pr_creation/auto_correct' } do
      result = run_cookstyle_runner(
        command: 'run',
        repos: [test_repo],
        force: true,
        no_cache: true
      )

      aggregate_failures do
        expect(result.exit_code).to eq(0).or eq(1)
        expect(result.output).to include('Creating PR').or include('auto-correct')
      end
    end
  end

  describe 'creating issues for manual fixes' do
    # TODO: Record VCR cassette for this test
    # To record: Set GITHUB_TOKEN and run with VCR_RECORD_MODE=all
    xit 'creates an issue when manual fixes are required (requires VCR cassette)',
        vcr: { cassette_name: 'pr_creation/manual_fixes' } do
      result = run_cookstyle_runner(
        command: 'run',
        repos: [test_repo],
        force: true,
        no_cache: true
      )

      aggregate_failures do
        expect(result.exit_code).to eq(0).or eq(1)
        expect(result.output).to include('Creating issue').or include('manual')
      end
    end
  end

  describe 'GitHubPRManager' do
    let(:settings) { Object.const_get('Settings') }
    let(:github_client) { instance_double(Octokit::Client) }
    let(:pr_manager) { CookstyleRunner::GitHubPRManager.new(settings, github_client) }
    let(:labels) { settings.issue_labels }

    describe '#create_pull_request' do
      let(:pull_request_response) { Struct.new(:number).new(123) }
      let(:create_args) { [test_repo, 'main', 'cookstyle-fixes', 'Test PR', 'Test body'] }

      before do
        allow(github_client).to receive_messages(
          pull_requests: [],
          create_pull_request: pull_request_response,
          labels_for_issue: [],
          add_labels_to_an_issue: nil
        )
      end

      it 'creates the pull request and applies labels' do
        expect(pr_manager.create_pull_request(*create_args)).to be true

        aggregate_failures do
          expect(github_client).to have_received(:create_pull_request).with(*create_args)
          expect(github_client).to have_received(:add_labels_to_an_issue).with(
            test_repo,
            pull_request_response.number,
            labels
          )
        end
      end
    end

    describe '#create_issue' do
      let(:issue_response) { Struct.new(:number).new(456) }
      let(:issue_args) { [test_repo, 'Test Issue', 'Test body'] }

      before do
        allow(github_client).to receive(:create_issue).and_return(issue_response)
        allow(github_client).to receive(:labels_for_issue).and_return([])
        allow(github_client).to receive(:add_labels_to_an_issue)
        allow(github_client).to receive(:update_issue)
      end

      it 'creates the issue and applies labels' do
        expect(pr_manager.create_issue(*issue_args)).to be true

        aggregate_failures do
          expect(github_client).to have_received(:create_issue).with(*issue_args)
          expect(github_client).to have_received(:add_labels_to_an_issue).with(
            test_repo,
            issue_response.number,
            labels
          )
        end
      end
    end
  end

  private

  def vcr_cassette_path(name)
    File.join(__dir__, '..', 'fixtures', 'vcr_cassettes', "#{name}.yml")
  end
end
# rubocop:enable RSpec/DescribeClass, RSpec/PendingWithoutReason
