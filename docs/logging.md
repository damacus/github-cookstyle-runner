# Logging

GitHub Cookstyle Runner uses structured JSON logging by default for cloud-native deployments.

## Key Features

### Component-Level Debug Filtering

Enable debug logging for specific components without flooding logs:

```bash
export GCR_LOG_DEBUG_COMPONENTS=git,cache
```

Available components: `git`, `cache`, `api`, `cookstyle`, `processor`

### Dual Format Support

- **JSON** (default): For production/Kubernetes deployments
- **Text**: For local development

## Configuration

### Environment Variables

| Variable | Default | Values |
|----------|---------|--------|
| `GCR_LOG_FORMAT` | `json` | `json`, `text` |
| `GCR_OUTPUT_FORMAT` | `json` | `json`, `text`, `table` |
| `GCR_LOG_LEVEL` | `INFO` | `DEBUG`, `INFO`, `WARN`, `ERROR`, `FATAL` |
| `GCR_LOG_DEBUG_COMPONENTS` | `[]` | Comma-separated component names |

### Configuration File

```yaml
# config/settings/default.yml
log_format: json
output_format: json
log_debug_components: []
```

### CLI Override

```bash
# Output format only (doesn't affect log format)
./bin/cookstyle-runner list --format table
```

## Output Formats

The `--format` flag controls **command output** (repository lists, configuration display), not log entries.

### JSON (Default)

```json
{
  "repositories": ["https://github.com/org/repo1.git"],
  "summary": {
    "total_repositories": 10,
    "successfully_processed": 8
  }
}
```

### Table

```text
╭────┬────────────╮
│  # │ Repository │
├────┼────────────┤
│  1 │ repo1      │
╰────┴────────────╯
```

### Text

```text
Found 1 repositories:
  1. repo1
```

## Production Setup

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
      - GCR_LOG_LEVEL=WARN
```

## Development Tips

```bash
# Human-readable logs and output
export GCR_LOG_FORMAT=text
export GCR_OUTPUT_FORMAT=table

# Debug specific components
export GCR_LOG_LEVEL=DEBUG
export GCR_LOG_DEBUG_COMPONENTS=git,cache
```
