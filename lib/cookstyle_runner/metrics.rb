# frozen_string_literal: true
# typed: strict

require 'prometheus_exporter'
require 'sorbet-runtime'

module CookstyleRunner
  # =============================================================================
  # GitHub Cookstyle Runner - Metrics Collection
  # =============================================================================
  #
  # This module provides Prometheus metrics collection for observability.
  # It tracks key performance indicators and operational metrics.
  #
  module Metrics
    extend T::Sig

    # Metrics server instance
    @registry = T.let(nil, T.anything)

    # Metrics instances (initialized lazily)
    @repos_processed_total = T.let(nil, T.anything)
    @processing_duration_seconds = T.let(nil, T.anything)
    @cache_hit_rate = T.let(nil, T.anything)
    @api_requests_total = T.let(nil, T.anything)
    @errors_total = T.let(nil, T.anything)

    class << self
      extend T::Sig

      # Initialize metrics if not already initialized
      # @return [void]
      sig { void }
      def ensure_metrics_initialized
        return if @repos_processed_total

        require 'prometheus_exporter/metric'
        require 'prometheus_exporter/metric/counter'
        require 'prometheus_exporter/metric/histogram'
        require 'prometheus_exporter/metric/gauge'

        @repos_processed_total = PrometheusExporter::Metric::Counter.new(
          :cookstyle_repos_processed_total,
          docstring: 'Total number of repositories processed'
        )

        @processing_duration_seconds = PrometheusExporter::Metric::Histogram.new(
          :cookstyle_processing_duration_seconds,
          docstring: 'Time spent processing repositories in seconds',
          buckets: [0.1, 0.5, 1.0, 2.5, 5.0, 10.0, 30.0, 60.0, 120.0, 300.0]
        )

        @cache_hit_rate = PrometheusExporter::Metric::Gauge.new(
          :cookstyle_cache_hit_rate,
          docstring: 'Cache hit rate percentage (0-100)'
        )

        @api_requests_total = PrometheusExporter::Metric::Counter.new(
          :cookstyle_api_requests_total,
          docstring: 'Total number of GitHub API requests',
          labels: [:endpoint, :status]
        )

        @errors_total = PrometheusExporter::Metric::Counter.new(
          :cookstyle_errors_total,
          docstring: 'Total number of errors encountered',
          labels: [:error_type, :component]
        )
      end

      # Start the metrics server
      # @param port [Integer] Port to run the metrics server on
      # @return [void]
      sig { params(port: Integer).void }
      def start_server(port: 9394)
        require 'prometheus_exporter/server'
        @registry = PrometheusExporter::Server.new(port: port)
        @registry.start
      rescue LoadError => e
        # Server not available, just log and continue
        puts "Warning: Prometheus server not available: #{e.message}"
      end

      # Stop the metrics server
      # @return [void]
      sig { void }
      def stop_server
        @registry.stop if @registry
      rescue StandardError => e
        # Server not available, just log and continue
        puts "Warning: Could not stop metrics server: #{e.message}"
      end

      # Increment repository processing counter
      # @param repo_name [String] Name of the repository
      # @param status [String] Processing status (success, failed, skipped)
      # @return [void]
      sig { params(repo_name: String, status: String).void }
      def increment_repos_processed(repo_name:, status:)
        ensure_metrics_initialized
        @repos_processed_total.increment({ repo: repo_name, status: status })
      end

      # Record processing duration
      # @param duration [Float] Duration in seconds
      # @param repo_name [String] Name of the repository
      # @return [void]
      sig { params(duration: Float, repo_name: String).void }
      def record_processing_duration(duration:, repo_name:)
        ensure_metrics_initialized
        @processing_duration_seconds.observe(duration, { repo: repo_name })
      end

      # Set cache hit rate gauge
      # @param hit_rate [Float] Cache hit rate percentage (0-100)
      # @return [void]
      sig { params(hit_rate: Float).void }
      def set_cache_hit_rate(hit_rate:)
        ensure_metrics_initialized
        @cache_hit_rate.set(hit_rate)
      end

      # Increment API request counter
      # @param endpoint [String] API endpoint name
      # @param status [String] HTTP status code
      # @return [void]
      sig { params(endpoint: String, status: String).void }
      def increment_api_requests(endpoint:, status:)
        ensure_metrics_initialized
        @api_requests_total.increment({ endpoint: endpoint, status: status })
      end

      # Increment error counter
      # @param error_type [String] Type of error
      # @param component [String] Component where error occurred
      # @return [void]
      sig { params(error_type: String, component: String).void }
      def increment_errors(error_type:, component:)
        ensure_metrics_initialized
        @errors_total.increment({ error_type: error_type, component: component })
      end

      # Get current metrics for debugging
      # @return [String] Current metrics in Prometheus format
      sig { returns(String) }
      def current_metrics
        return '' unless @repos_processed_total

        metrics = []

        # Format repos processed counter
        if @repos_processed_total
          name_str = @repos_processed_total.name.to_s
          help_str = @repos_processed_total.help.to_s
          type_str = @repos_processed_total.type.to_s
          prefix_str = @repos_processed_total.prefix(name_str).to_s
          metric_text_str = @repos_processed_total.metric_text.to_s

          metrics << "# HELP #{prefix_str} #{help_str}"
          metrics << "# TYPE #{prefix_str} #{type_str}"
          metrics << metric_text_str
        end

        metrics.join("\n")
      end

      # Reset all metrics (useful for testing)
      # @return [void]
      sig { void }
      def reset_metrics!
        @repos_processed_total.reset! if @repos_processed_total
        @processing_duration_seconds.reset! if @processing_duration_seconds
        @cache_hit_rate.reset! if @cache_hit_rate
        @api_requests_total.reset! if @api_requests_total
        @errors_total.reset! if @errors_total
      end
    end
  end
end
