# typed: false
# frozen_string_literal: true

require 'spec_helper'
require 'cookstyle_runner/reporter'
require 'semantic_logger'

RSpec.describe CookstyleRunner::Reporter do
  # Default reporter uses real logger
  subject(:reporter) { described_class.new }

  let(:capture_logger) { SemanticLogger::Test::CaptureLogEvents.new }
  let(:format) { 'json' }

  # Stub SemanticLogger to return capture logger for this class
  before do
    allow(SemanticLogger).to receive(:[]).with(described_class).and_return(capture_logger)
  end

  describe '#initialize' do
    it 'creates a reporter instance' do
      expect(reporter).to be_a(described_class)
    end
  end

  describe '#aggregate_results' do
    let(:results) do
      [
        { status: :no_issues, repo_name: 'repo1' },
        { status: :issues_found, repo_name: 'repo2' },
        { status: :skipped, repo_name: 'repo3' },
        { status: :error, repo_name: 'repo4', error_message: 'Test error' }
      ]
    end

    it 'aggregates results correctly' do
      processed, issues, skipped, errors = reporter.aggregate_results(results)

      expect(processed).to eq(2)  # no_issues + issues_found
      expect(issues).to eq(1)     # issues_found
      expect(skipped).to eq(1)    # skipped
      expect(errors).to eq(1)     # error
    end

    context 'with unknown status' do
      let(:results) do
        [{ status: :unknown, repo_name: 'repo1' }]
      end

      it 'treats unknown status as error' do
        _processed, _issues, _skipped, errors = reporter.aggregate_results(results)
        expect(errors).to eq(1)
      end
    end

    context 'with multiple repositories' do
      let(:results) do
        [
          { status: :no_issues, repo_name: 'repo1' },
          { status: :no_issues, repo_name: 'repo2' },
          { status: :issues_found, repo_name: 'repo3' },
          { status: :issues_found, repo_name: 'repo4' },
          { status: :issues_found, repo_name: 'repo5' },
          { status: :skipped, repo_name: 'repo6' },
          { status: :error, repo_name: 'repo7', error_message: 'Error 1' },
          { status: :error, repo_name: 'repo8', error_message: 'Error 2' }
        ]
      end

      it 'correctly counts all statuses' do
        processed, issues, skipped, errors = reporter.aggregate_results(results)

        expect(processed).to eq(5)  # 2 no_issues + 3 issues_found
        expect(issues).to eq(3)     # 3 issues_found
        expect(skipped).to eq(1)    # 1 skipped
        expect(errors).to eq(2)     # 2 errors
      end
    end
  end

  describe '#summary' do
    before do
      allow(SemanticLogger).to receive(:[]).with('Reporter').and_return(capture_logger)
    end

    let(:summary_params) do
      {
        total_repos: 10, processed_count: 8, issues_count: 3, skipped_count: 1,
        error_count: 1, issues_created: 2, prs_created: 3, issue_errors: 0, pr_errors: 0
      }
    end

    it 'logs summary message at info level' do
      reporter.summary(**summary_params)
      event = capture_logger.events.first
      expect(event.message).to eq('Run summary')
      expect(event.level).to eq(:info)
    end

    it 'includes repository statistics in payload' do
      reporter.summary(**summary_params)
      expect(capture_logger.events.first.payload[:summary]).to include(
        total_repositories: 10, successfully_processed: 8, found_issues_in: 3, skipped: 1, errors: 1
      )
    end

    it 'includes artifact statistics in payload' do
      reporter.summary(**summary_params)
      expect(capture_logger.events.first.payload[:artifacts]).to include(
        issues_created: 2, pull_requests_created: 3, issue_creation_errors: 0, pr_creation_errors: 0
      )
    end
  end

  describe '#cache_stats' do
    let(:stats_hash) do
      {
        'cache_hits' => 5,
        'cache_misses' => 3,
        'cache_updates' => 2,
        'cache_hit_rate' => 62.5,
        'estimated_time_saved' => 150,
        'runtime' => 300
      }
    end

    before do
      allow(SemanticLogger).to receive(:[]).with('Reporter').and_return(capture_logger)
    end

    it 'logs cache stats with structured payload' do
      reporter.cache_stats(stats_hash)

      event = capture_logger.events.first
      expect(event.message).to eq('Cache statistics')
      expect(event.level).to eq(:info)
      expect(event.payload).to include(
        cache_hits: stats_hash['cache_hits'],
        cache_misses: stats_hash['cache_misses'],
        cache_updates: stats_hash['cache_updates'],
        cache_hit_rate: stats_hash['cache_hit_rate'],
        estimated_time_saved: stats_hash['estimated_time_saved'],
        runtime: stats_hash['runtime']
      )
    end

    it 'logs when no stats' do
      reporter.cache_stats({})

      event = capture_logger.events.first
      expect(event.message).to eq('Cache statistics')
      expect(event.level).to eq(:info)
      # When no stats, all values should be 0
      expect(event.payload[:cache_hits]).to eq(0)
      expect(event.payload[:cache_misses]).to eq(0)
    end
  end

  describe '#created_artifacts' do
    let(:artifacts) do
      [
        { repo: 'test/repo1', number: 123, title: 'Fix issues', type: 'pull', url: 'https://github.com/test/repo1/pull/123' },
        { repo: 'test/repo2', number: 456, title: 'Manual fixes needed', type: 'issue', url: 'https://github.com/test/repo2/issues/456' }
      ]
    end

    before do
      allow(SemanticLogger).to receive(:[]).with('Reporter').and_return(capture_logger)
    end

    it 'logs artifacts with structured payload' do
      reporter.created_artifacts(created_artifacts: artifacts)

      event = capture_logger.events.first
      expect(event.message).to eq('Artifacts created')
      expect(event.payload[:count]).to eq(2)
      expect(event.payload[:artifacts]).to eq(artifacts)
    end

    it 'logs when no artifacts' do
      reporter.created_artifacts(created_artifacts: [])

      event = capture_logger.events.first
      expect(event.message).to eq('No artifacts created')
    end
  end

  describe '#artifact_creation_errors' do
    let(:errors) do
      [
        { repo: 'test/repo1', message: 'API error', type: 'pull' }
      ]
    end

    before do
      allow(SemanticLogger).to receive(:[]).with('Reporter').and_return(capture_logger)
    end

    it 'logs errors with structured payload' do
      reporter.artifact_creation_errors(errors)

      event = capture_logger.events.first
      expect(event.message).to eq('Artifact creation errors')
      expect(event.level).to eq(:error)
      expect(event.payload[:count]).to eq(1)
      expect(event.payload[:errors]).to eq(errors)
    end

    it 'logs when no errors' do
      reporter.artifact_creation_errors([])

      event = capture_logger.events.first
      expect(event.message).to eq('No artifact creation errors')
      expect(event.level).to eq(:info)
    end
  end
end
