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
  # rubocop:disable Metrics/ClassLength
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
      # rubocop:disable Metrics/MethodLength
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
          labels: %i[endpoint status]
        )

        @errors_total = PrometheusExporter::Metric::Counter.new(
          :cookstyle_errors_total,
          docstring: 'Total number of errors encountered',
          labels: %i[error_type component]
        )
      end
      # rubocop:enable Metrics/MethodLength

      # Start the metrics server
      # @param port [Integer] Port to run the metrics server on
      # @return [void]
      sig { params(port: Integer).void }
      def start_server(port: 9394)
        require 'prometheus_exporter/server'
        @registry = PrometheusExporter::Server.new(port: port)
        @registry.start
      rescue StandardError => e
        # Server not available or other error, just log and continue
        puts "Warning: Prometheus server not available: #{e.message}"
      end

      # Stop the metrics server
      # @return [void]
      sig { void }
      def stop_server
        @registry&.stop
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
      # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
      sig { returns(String) }
      def current_metrics
        metrics = []

        # Format repos processed counter
        if @repos_processed_total
          name_str = @repos_processed_total.name.to_s
          help_str = @repos_processed_total.help.to_s
          type_str = @repos_processed_total.type.to_s
          prefix_str = @repos_processed_total.prefix(name_str).to_s

          # Get metric data directly from the metric object
          metric_data = @repos_processed_total.instance_variable_get(:@data)
          metric_lines = []

          if metric_data && !metric_data.empty?
            metric_data.each do |labels, value|
              labels_str = labels.map { |k, v| "#{k}=\"#{v}\"" }.join(',') if labels.is_a?(Hash)
              labels_str ||= ''
              metric_lines << "#{prefix_str}#{labels_str} #{value}"
            end
          end

          metrics << "# HELP #{prefix_str} #{help_str}"
          metrics << "# TYPE #{prefix_str} #{type_str}"
          metrics.concat(metric_lines) if metric_lines.any?
        end

        # Format processing duration histogram
        if @processing_duration_seconds
          name_str = @processing_duration_seconds.name.to_s
          help_str = @processing_duration_seconds.help.to_s
          type_str = @processing_duration_seconds.type.to_s
          prefix_str = @processing_duration_seconds.prefix(name_str).to_s

          # Get histogram data - histograms store data differently
          sums = @processing_duration_seconds.instance_variable_get(:@sums)
          if sums && !sums.empty?
            sums.each do |labels, sum_value|
              labels_str = labels.map { |k, v| "#{k}=\"#{v}\"" }.join(',') if labels.is_a?(Hash)
              labels_str ||= ''
              metrics << "#{prefix_str}_sum#{labels_str} #{sum_value}"
            end
          end

          counts = @processing_duration_seconds.instance_variable_get(:@counts)
          if counts && !counts.empty?
            counts.each do |labels, count_value|
              labels_str = labels.map { |k, v| "#{k}=\"#{v}\"" }.join(',') if labels.is_a?(Hash)
              labels_str ||= ''
              metrics << "#{prefix_str}_count#{labels_str} #{count_value}"
            end
          end

          metrics << "# HELP #{prefix_str} #{help_str}"
          metrics << "# TYPE #{prefix_str} #{type_str}"
        end

        # Format cache hit rate gauge
        if @cache_hit_rate
          name_str = @cache_hit_rate.name.to_s
          help_str = @cache_hit_rate.help.to_s
          type_str = @cache_hit_rate.type.to_s
          prefix_str = @cache_hit_rate.prefix(name_str).to_s

          # Get metric data
          metric_data = @cache_hit_rate.instance_variable_get(:@data)
          if metric_data && !metric_data.empty?
            metric_data.each do |labels, value|
              labels_str = labels.map { |k, v| "#{k}=\"#{v}\"" }.join(',') if labels.is_a?(Hash)
              labels_str ||= ''
              metrics << "#{prefix_str}#{labels_str} #{value}"
            end
          end

          metrics << "# HELP #{prefix_str} #{help_str}"
          metrics << "# TYPE #{prefix_str} #{type_str}"
        end

        # Format API requests counter
        if @api_requests_total
          name_str = @api_requests_total.name.to_s
          help_str = @api_requests_total.help.to_s
          type_str = @api_requests_total.type.to_s
          prefix_str = @api_requests_total.prefix(name_str).to_s

          # Get metric data
          metric_data = @api_requests_total.instance_variable_get(:@data)
          if metric_data && !metric_data.empty?
            metric_data.each do |labels, value|
              labels_str = labels.map { |k, v| "#{k}=\"#{v}\"" }.join(',') if labels.is_a?(Hash)
              labels_str ||= ''
              metrics << "#{prefix_str}#{labels_str} #{value}"
            end
          end

          metrics << "# HELP #{prefix_str} #{help_str}"
          metrics << "# TYPE #{prefix_str} #{type_str}"
        end

        # Format errors counter
        if @errors_total
          name_str = @errors_total.name.to_s
          help_str = @errors_total.help.to_s
          type_str = @errors_total.type.to_s
          prefix_str = @errors_total.prefix(name_str).to_s

          # Get metric data
          metric_data = @errors_total.instance_variable_get(:@data)
          if metric_data && !metric_data.empty?
            metric_data.each do |labels, value|
              labels_str = labels.map { |k, v| "#{k}=\"#{v}\"" }.join(',') if labels.is_a?(Hash)
              labels_str ||= ''
              metrics << "#{prefix_str}#{labels_str} #{value}"
            end
          end

          metrics << "# HELP #{prefix_str} #{help_str}"
          metrics << "# TYPE #{prefix_str} #{type_str}"
        end

        metrics.join("\n")
      end
      # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity

      # Reset all metrics (useful for testing)
      # @return [void]
      sig { void }
      def reset_metrics!
        @repos_processed_total&.reset!
        @processing_duration_seconds&.reset!
        @cache_hit_rate&.reset!
        @api_requests_total&.reset!
        @errors_total&.reset!

        # Clear all metrics instances
        @repos_processed_total = nil
        @processing_duration_seconds = nil
        @cache_hit_rate = nil
        @api_requests_total = nil
        @errors_total = nil
      end
    end
  end
  # rubocop:enable Metrics/ClassLength
end
