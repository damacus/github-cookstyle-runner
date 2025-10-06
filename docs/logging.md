# Logging Configuration

The Cookstyle Runner includes an enhanced logging system with support for structured logging, log rotation, and component-level debug filtering.

## Features

### 1. **Structured Logging (JSON Format)**

Enable JSON-formatted logs for easier parsing by log aggregation tools:

```bash
export GCR_LOG_FORMAT=json
```

Example JSON output:

```json
{"timestamp":"2025-10-06T15:44:35+01:00","level":"INFO","message":"Processing repository 1/5: my-repo"}
{"timestamp":"2025-10-06T15:44:36+01:00","level":"DEBUG","message":"Cache hit","component":"cache","repo":"my-repo"}
```

### 2. **Component-Level Debug Logging**

Enable debug logging for specific components without flooding logs:

```bash
# Enable debug for git and cache components only
export GCR_LOG_DEBUG_COMPONENTS=git,cache
```

Or in configuration:

```yaml
log_debug_components:
  - git
  - cache
  - api
```

Available components:

- `git` - Git operations (clone, commit, push)
- `cache` - Cache operations (hits, misses, updates)
- `api` - GitHub API calls
- `cookstyle` - Cookstyle execution
- `processor` - Repository processing

## Configuration

### Environment Variables

| Variable | Description | Default | Example |
|----------|-------------|---------|---------|
| `GCR_LOG_LEVEL` | Log level (DEBUG, INFO, WARN, ERROR, FATAL) | `INFO` | `DEBUG` |
| `GCR_LOG_FORMAT` | Log format (text or json) | `text` | `json` |
| `GCR_LOG_DEBUG_COMPONENTS` | Comma-separated list of components for debug logging | `[]` | `git,cache` |

### Configuration File

In `config/settings/default.yml`:

```yaml
# Logging configuration
log_level: INFO
log_format: text # text or json
log_debug_components: [] # List of components to enable debug logging for
```

## Usage Examples

### Basic Text Logging

```bash
# Default text format with INFO level
cookstyle-runner run
```

### JSON Logging for Production

```bash
# JSON format for log aggregation
export GCR_LOG_FORMAT=json
export GCR_LOG_LEVEL=WARN
cookstyle-runner run
```

### Debug Specific Components

```bash
# Debug only git operations
export GCR_LOG_LEVEL=DEBUG
export GCR_LOG_DEBUG_COMPONENTS=git
cookstyle-runner run
```

### Full Debug Mode

```bash
# Enable all debug logging
export GCR_LOG_LEVEL=DEBUG
cookstyle-runner run
```

## Programmatic Usage

The logger supports contextual metadata:

```ruby
logger.info('Processing repository', repo: 'my-repo', status: 'started')
logger.debug('Cache operation', component: 'cache', action: 'hit')
logger.error('Operation failed', repo: 'my-repo', error: 'timeout')
```

### Context Blocks

Add context that applies to all log messages within a block:

```ruby
logger.with_context(repo: 'my-repo') do
  logger.info('Starting processing')  # Includes repo: 'my-repo'
  logger.debug('Checking cache')      # Includes repo: 'my-repo'
end
```

## Best Practices

1. **Use appropriate log levels**:
   - `DEBUG`: Detailed diagnostic information
   - `INFO`: General informational messages
   - `WARN`: Warning messages for potentially harmful situations
   - `ERROR`: Error messages for failures
   - `FATAL`: Critical errors that may cause termination

2. **Use component filtering in production**:
   - Enable debug logging only for components you're troubleshooting
   - Reduces log volume and improves performance

3. **Use JSON format for production**:
   - Easier to parse and aggregate
   - Better for log management tools (ELK, Splunk, etc.)

## Troubleshooting

### Logs are too verbose

Increase the log level:

```bash
export GCR_LOG_LEVEL=WARN
```

### Need more detail for specific operations

Enable component-specific debug logging:

```bash
export GCR_LOG_LEVEL=DEBUG
export GCR_LOG_DEBUG_COMPONENTS=git,cache
```
