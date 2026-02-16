# frozen_string_literal: true
# typed: true

require 'spec_helper'

RSpec.describe CookstyleRunner::Metrics do
  before do
    # Reset metrics before each test
    described_class.reset_metrics!
  end

  after do
    # Clean up after each test
    described_class.reset_metrics!
  end

  describe '.ensure_metrics_initialized' do
    it 'initializes all metrics' do
      described_class.ensure_metrics_initialized

      expect(described_class.instance_variable_get(:@repos_processed_total)).to be_a(PrometheusExporter::Metric::Counter)
      expect(described_class.instance_variable_get(:@processing_duration_seconds)).to be_a(PrometheusExporter::Metric::Histogram)
      expect(described_class.instance_variable_get(:@cache_hit_rate)).to be_a(PrometheusExporter::Metric::Gauge)
      expect(described_class.instance_variable_get(:@api_requests_total)).to be_a(PrometheusExporter::Metric::Counter)
      expect(described_class.instance_variable_get(:@errors_total)).to be_a(PrometheusExporter::Metric::Counter)
    end

    it 'does not reinitialize metrics if already initialized' do
      described_class.ensure_metrics_initialized
      original_counter = described_class.instance_variable_get(:@repos_processed_total)

      described_class.ensure_metrics_initialized

      expect(described_class.instance_variable_get(:@repos_processed_total)).to be(original_counter)
    end
  end

  describe '.increment_repos_processed' do
    it 'increments the repository processing counter' do
      described_class.increment_repos_processed(repo_name: 'test-repo', status: 'success')

      metrics_text = described_class.current_metrics
      expect(metrics_text).to include('cookstyle_repos_processed_total')
      expect(metrics_text).to include('repo="test-repo"')
      expect(metrics_text).to include('status="success"')
    end

    it 'handles different statuses' do
      described_class.increment_repos_processed(repo_name: 'test-repo', status: 'failed')
      described_class.increment_repos_processed(repo_name: 'test-repo', status: 'skipped')

      metrics_text = described_class.current_metrics
      expect(metrics_text).to include('status="failed"')
      expect(metrics_text).to include('status="skipped"')
    end
  end

  describe '.record_processing_duration' do
    it 'records processing duration' do
      described_class.record_processing_duration(duration: 2.5, repo_name: 'test-repo')

      metrics_text = described_class.current_metrics
      expect(metrics_text).to include('cookstyle_processing_duration_seconds')
      expect(metrics_text).to include('repo="test-repo"')
    end

    it 'handles different duration values' do
      described_class.record_processing_duration(duration: 0.1, repo_name: 'fast-repo')
      described_class.record_processing_duration(duration: 120.0, repo_name: 'slow-repo')

      metrics_text = described_class.current_metrics
      expect(metrics_text).to include('repo="fast-repo"')
      expect(metrics_text).to include('repo="slow-repo"')
    end
  end

  describe '.set_cache_hit_rate' do
    it 'sets cache hit rate gauge' do
      described_class.set_cache_hit_rate(hit_rate: 85.5)

      metrics_text = described_class.current_metrics
      expect(metrics_text).to include('cookstyle_cache_hit_rate')
      expect(metrics_text).to include('85.5')
    end

    it 'handles edge cases' do
      described_class.set_cache_hit_rate(hit_rate: 0.0)
      described_class.set_cache_hit_rate(hit_rate: 100.0)

      metrics_text = described_class.current_metrics
      expect(metrics_text).to include('0.0')
      expect(metrics_text).to include('100.0')
    end
  end

  describe '.increment_api_requests' do
    it 'increments API request counter' do
      described_class.increment_api_requests(endpoint: 'search_repositories', status: '200')

      metrics_text = described_class.current_metrics
      expect(metrics_text).to include('cookstyle_api_requests_total')
      expect(metrics_text).to include('endpoint="search_repositories"')
      expect(metrics_text).to include('status="200"')
    end

    it 'handles different endpoints and statuses' do
      described_class.increment_api_requests(endpoint: 'search_repositories', status: '429')
      described_class.increment_api_requests(endpoint: 'create_pull_request', status: '201')

      metrics_text = described_class.current_metrics
      expect(metrics_text).to include('status="429"')
      expect(metrics_text).to include('endpoint="create_pull_request"')
    end
  end

  describe '.increment_errors' do
    it 'increments error counter' do
      described_class.increment_errors(error_type: 'RateLimit', component: 'GitHubAPI')

      metrics_text = described_class.current_metrics
      expect(metrics_text).to include('cookstyle_errors_total')
      expect(metrics_text).to include('error_type="RateLimit"')
      expect(metrics_text).to include('component="GitHubAPI"')
    end

    it 'handles different error types and components' do
      described_class.increment_errors(error_type: 'ServerError', component: 'GitHubAPI')
      described_class.increment_errors(error_type: 'StandardError', component: 'RepositoryProcessor')

      metrics_text = described_class.current_metrics
      expect(metrics_text).to include('error_type="ServerError"')
      expect(metrics_text).to include('component="RepositoryProcessor"')
    end
  end

  describe '.current_metrics' do
    it 'returns metrics in Prometheus format' do
      described_class.increment_repos_processed(repo_name: 'test-repo', status: 'success')
      metrics_text = described_class.current_metrics

      expect(metrics_text).to be_a(String)
      expect(metrics_text).to include('# HELP')
      expect(metrics_text).to include('# TYPE')
    end

    it 'returns empty string when no metrics are initialized' do
      metrics_text = described_class.current_metrics
      expect(metrics_text).to eq('')
    end
  end

  describe '.reset_metrics!' do
    it 'resets all metrics' do
      # Add some metrics data
      described_class.increment_repos_processed(repo_name: 'test-repo', status: 'success')
      described_class.set_cache_hit_rate(hit_rate: 85.5)

      # Verify metrics exist
      expect(described_class.current_metrics).not_to be_empty

      # Reset metrics
      described_class.reset_metrics!

      # Verify metrics are reset
      expect(described_class.current_metrics).to eq('')
    end
  end

  describe 'metrics server functionality' do
    describe '.start_server' do
      it 'handles server startup gracefully' do
        expect { described_class.start_server(port: 9395) }.not_to raise_error
      end
    end

    describe '.stop_server' do
      it 'handles server shutdown gracefully' do
        expect { described_class.stop_server }.not_to raise_error
      end
    end
  end
end
