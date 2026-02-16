# Prometheus Metrics

The GitHub Cookstyle Runner provides comprehensive Prometheus metrics for observability and monitoring.

## Overview

The application tracks key performance indicators and operational metrics to help you monitor:

- Repository processing performance
- Cache efficiency
- GitHub API usage
- Error rates and types
- Processing duration distribution

## Metrics Available

### Repository Processing Metrics

#### `cookstyle_repos_processed_total`

- **Type:** Counter
- **Description:** Total number of repositories processed
- **Labels:** `repo`, `status` (success, failed, skipped)
- **Example:** `cookstyle_repos_processed_total{repo="my-cookbook",status="success"} 42`

#### `cookstyle_processing_duration_seconds`

- **Type:** Histogram
- **Description:** Time spent processing repositories in seconds
- **Labels:** `repo`
- **Buckets:** 0.1, 0.5, 1.0, 2.5, 5.0, 10.0, 30.0, 60.0, 120.0, 300.0
- **Example:** `cookstyle_processing_duration_seconds_bucket{repo="my-cookbook",le="5.0"} 25`

### Cache Metrics

#### `cookstyle_cache_hit_rate`

- **Type:** Gauge
- **Description:** Cache hit rate percentage (0-100)
- **Labels:** None
- **Example:** `cookstyle_cache_hit_rate 85.5`

### GitHub API Metrics

#### `cookstyle_api_requests_total`

- **Type:** Counter
- **Description:** Total number of GitHub API requests
- **Labels:** `endpoint`, `status`
- **Example:** `cookstyle_api_requests_total{endpoint="search_repositories",status="200"} 15`

#### `cookstyle_errors_total`

- **Type:** Counter
- **Description:** Total number of errors encountered
- **Labels:** `error_type`, `component`
- **Example:** `cookstyle_errors_total{error_type="RateLimit",component="GitHubAPI"} 3`

## Configuration

### Enable Metrics

Add to your configuration file:

```yaml
# Enable metrics collection
enable_metrics: true
metrics_port: 9394
```

### Environment Variables

You can also use environment variables:

```bash
export GCR_ENABLE_METRICS=true
export GCR_METRICS_PORT=9394
```

## Accessing Metrics

### HTTP Endpoint

When metrics are enabled, you can access them at:

```text
http://localhost:9394/metrics
```

### Example Output

```text
# HELP cookstyle_repos_processed_total Total number of repositories processed
# TYPE cookstyle_repos_processed_total counter
cookstyle_repos_processed_total{repo="my-cookbook",status="success"} 42
cookstyle_repos_processed_total{repo="other-cookbook",status="failed"} 1

# HELP cookstyle_processing_duration_seconds Time spent processing repositories in seconds
# TYPE cookstyle_processing_duration_seconds histogram
cookstyle_processing_duration_seconds_bucket{repo="my-cookbook",le="0.1"} 0
cookstyle_processing_duration_seconds_bucket{repo="my-cookbook",le="0.5"} 5
cookstyle_processing_duration_seconds_bucket{repo="my-cookbook",le="1.0"} 12
cookstyle_processing_duration_seconds_bucket{repo="my-cookbook",le="2.5"} 25
cookstyle_processing_duration_seconds_bucket{repo="my-cookbook",le="5.0"} 38
cookstyle_processing_duration_seconds_bucket{repo="my-cookbook",le="10.0"} 42
cookstyle_processing_duration_seconds_bucket{repo="my-cookbook",le="+Inf"} 42
cookstyle_processing_duration_seconds_sum{repo="my-cookbook"} 156.7
cookstyle_processing_duration_seconds_count{repo="my-cookbook"} 42

# HELP cookstyle_cache_hit_rate Cache hit rate percentage (0-100)
# TYPE cookstyle_cache_hit_rate gauge
cookstyle_cache_hit_rate 85.5

# HELP cookstyle_api_requests_total Total number of GitHub API requests
# TYPE cookstyle_api_requests_total counter
cookstyle_api_requests_total{endpoint="search_repositories",status="200"} 15
cookstyle_api_requests_total{endpoint="search_repositories",status="429"} 2

# HELP cookstyle_errors_total Total number of errors encountered
# TYPE cookstyle_errors_total counter
cookstyle_errors_total{error_type="RateLimit",component="GitHubAPI"} 2
cookstyle_errors_total{error_type="ServerError",component="GitHubAPI"} 1
cookstyle_errors_total{error_type="StandardError",component="RepositoryProcessor"} 1
```

## Prometheus Configuration

Add to your `prometheus.yml`:

```yaml
scrape_configs:
  - job_name: 'cookstyle-runner'
    static_configs:
      - targets: ['localhost:9394']
    scrape_interval: 15s
    metrics_path: '/metrics'
```

## Grafana Dashboard

See `docs/grafana-dashboard.json` for an example Grafana dashboard that visualizes these metrics.

## Alerting Examples

### High Error Rate

```yaml
groups:
  - name: cookstyle-runner
    rules:
      - alert: CookstyleRunnerHighErrorRate
        expr: rate(cookstyle_errors_total[5m]) > 0.1
        for: 2m
        labels:
          severity: warning
        annotations:
          summary: "High error rate in Cookstyle Runner"
          description: "Error rate is {{ $value }} errors per second"
```

### Slow Processing

```yaml
      - alert: CookstyleRunnerSlowProcessing
        expr: histogram_quantile(0.95, rate(cookstyle_processing_duration_seconds_bucket[5m])) > 60
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Slow repository processing"
          description: "95th percentile processing time is {{ $value }} seconds"
```

### Low Cache Hit Rate

```yaml
      - alert: CookstyleRunnerLowCacheHitRate
        expr: cookstyle_cache_hit_rate < 50
        for: 10m
        labels:
          severity: info
        annotations:
          summary: "Low cache hit rate"
          description: "Cache hit rate is {{ $value }}%"
```

## Troubleshooting

### Metrics Not Available

1. Check if metrics are enabled: `enable_metrics: true`
2. Verify the port is not in use
3. Check application logs for metrics server startup messages

### Missing Metrics

1. Ensure the application has processed at least one repository
2. Check for errors in the application logs
3. Verify the metrics endpoint is accessible

### High Memory Usage

1. Consider reducing metric retention in Prometheus
2. Monitor metric cardinality (too many label combinations)
3. Use appropriate label values (avoid high-cardinality labels like timestamps)
