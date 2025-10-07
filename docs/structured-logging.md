# Structured Logging

## Overview

GitHub Cookstyle Runner uses structured logging with JSON as the default format, following best practices for cloud-native applications running in Docker/Kubernetes environments.

## Log Format

### JSON Format (Default)

All log entries follow this structure:

```json
{
  "timestamp": "2025-10-06T22:43:52Z",
  "level": "INFO",
  "message": "Configuration loaded and validated successfully",
  "component": "configuration",
  "user_id": "12345"
}
```

### Fields

- **timestamp**: ISO 8601 formatted timestamp in UTC
- **level**: Log level (DEBUG, INFO, WARN, ERROR, FATAL)
- **message**: Human-readable log message
- **component**: (optional) Component that generated the log (e.g., 'git', 'cache', 'github')
- **Additional metadata**: Any context-specific fields

### Text Format

For development environments, a human-readable text format is available:

```
[2025-10-06 22:43:52] INFO  -- Configuration loaded and validated successfully (component=configuration)
```

## Configuration

### Default Settings

```yaml
# config/settings/default.yml
log_format: json  # json or text
output_format: json  # json, text, or table
```

### Development Override

```yaml
# config/settings/development.yml
log_format: text
output_format: text
```

### Environment Variables

Override at runtime:

```bash
export GCR_LOG_FORMAT=json
export GCR_OUTPUT_FORMAT=json
```

### CLI Options

```bash
# Use JSON format for output
./bin/cookstyle-runner list --format json

# Use text format for output  
./bin/cookstyle-runner list --format text

# Use table format for output
./bin/cookstyle-runner list --format table
```

## Output Formats

### Repository Lists

**JSON:**

```json
{
  "repositories": [
    "https://github.com/org/repo1.git",
    "https://github.com/org/repo2.git"
  ]
}
```

**Text:**

```
Found 2 repositories:
  1. repo1
  2. repo2
```

**Table:**

```
╭─────────────────╮
│ Found 2 reposi… │
├────┬────────────┤
│  # │ Repository │
├────┼────────────┤
│  1 │ repo1      │
│  2 │ repo2      │
╰────┴────────────╯
```

### Configuration

**JSON:**

```json
{
  "configuration": {
    "repo_owner": "sous-chefs",
    "topics": "chef-cookbook",
    "branch_name": "cookstyle/fixes",
    "git_author": {
      "name": "Cookstyle Runner",
      "email": "cookstyle-runner@example.com"
    },
    "cache_enabled": true,
    "cache_max_age_days": 7
  }
}
```

**Text:**

```
--- Configuration ---
Destination Repo Owner: sous-chefs
Destination Repo Topics: chef-cookbook
Branch Name: cookstyle/fixes
...
```

**Table:**

```
╭───────────────────┬─────────────────────────────────────────────╮
│ Metric            │ Value                                       │
├───────────────────┼─────────────────────────────────────────────┤
│ Repo Owner        │ sous-chefs                                  │
│ Topics            │ chef-cookbook                               │
...
```

### Summary Reports

**JSON:**

```json
{
  "summary": {
    "total_repositories": 10,
    "successfully_processed": 8,
    "found_issues_in": 3,
    "skipped": 1,
    "errors": 1
  },
  "artifacts": {
    "issues_created": 2,
    "pull_requests_created": 3,
    "issue_creation_errors": 0,
    "pr_creation_errors": 0
  }
}
```

### Cache Statistics

**JSON:**

```json
{
  "cache_stats": {
    "cache_hits": 5,
    "cache_misses": 3,
    "cache_updates": 2,
    "cache_hit_rate": 62.5,
    "estimated_time_saved": 45.2,
    "runtime": 120.5
  }
}
```

## Best Practices

### For Production/K8s Deployments

1. Use JSON format for logs and output
2. Configure log aggregation tools (e.g., Fluentd, Logstash) to parse JSON
3. Use structured metadata for filtering and searching
4. Set appropriate log levels (INFO or WARN for production)

### For Development

1. Use text format for better readability
2. Use table format for visual inspection
3. Enable DEBUG logging for specific components:

   ```yaml
   log_debug_components: ['git', 'cache']
   ```

### Adding Metadata to Logs

```ruby
# With component
logger.info('Repository cloned', component: 'git', repo: 'sous-chefs/ruby_rbenv')

# With context
logger.with_context(repo: 'sous-chefs/ruby_rbenv') do
  logger.info('Starting Cookstyle run')
  logger.info('Cookstyle completed')
end
```

## Integration Examples

### Kubernetes

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: cookstyle-runner-config
data:
  log_format: "json"
  output_format: "json"
```

### Docker Compose

```yaml
services:
  cookstyle-runner:
    environment:
      - GCR_LOG_FORMAT=json
      - GCR_OUTPUT_FORMAT=json
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
```

### Fluentd Configuration

```
<source>
  @type tail
  path /var/log/cookstyle-runner/*.log
  pos_file /var/log/cookstyle-runner.pos
  tag cookstyle.runner
  <parse>
    @type json
    time_key timestamp
    time_format %Y-%m-%dT%H:%M:%S%z
  </parse>
</source>
```

## References

- [Structured Logging Best Practices](https://sematext.com/glossary/structured-logging/)
- [The Twelve-Factor App: Logs](https://12factor.net/logs)
- [JSON Lines Format](https://jsonlines.org/)
