# Advanced Usage

Advanced usage patterns and workflows for power users.

## Batch Processing

### Process Multiple Organizations

Deploy separate instances for each organization:

```bash
# Organization A
docker-compose -f docker-compose-org-a.yml up

# Organization B
docker-compose -f docker-compose-org-b.yml up
```

### Parallel Processing with Filtering

Process different repository groups in parallel:

```bash
# Terminal 1: Process group 1
docker-compose run -e GCR_FILTER_REPOS=repo1,repo2,repo3 cookstyle-runner

# Terminal 2: Process group 2
docker-compose run -e GCR_FILTER_REPOS=repo4,repo5,repo6 cookstyle-runner
```

## Custom Workflows

### Dry Run Mode

Test configuration without creating PRs (not yet implemented):

```bash
# Future feature
GCR_DRY_RUN=1 docker-compose up
```

### Selective Processing

#### Only Auto-Correctable Issues

```bash
GCR_CREATE_MANUAL_FIX_PRS=0 docker-compose up
```

#### Only Manual Issues

Process repos but only create issues for manual fixes:

```bash
# Requires custom scripting - not directly supported
```

## Integration Patterns

### CI/CD Integration

#### GitHub Actions

```yaml
name: Scheduled Cookstyle

on:
  schedule:
    - cron: '0 2 * * *'  # Daily at 2 AM
  workflow_dispatch:

jobs:
  cookstyle:
    runs-on: ubuntu-latest
    steps:
      - name: Run Cookstyle Runner
        run: |
          docker run --rm \
            -e GITHUB_APP_ID=${{ secrets.GITHUB_APP_ID }} \
            -e GITHUB_APP_INSTALLATION_ID=${{ secrets.GITHUB_APP_INSTALLATION_ID }} \
            -e GITHUB_APP_PRIVATE_KEY="${{ secrets.GITHUB_APP_PRIVATE_KEY }}" \
            -e GCR_DESTINATION_REPO_OWNER=my-org \
            -e GCR_DESTINATION_REPO_TOPICS=chef-cookbook \
            -e GCR_GIT_EMAIL=bot@example.com \
            -e GCR_GIT_NAME="Cookstyle Bot" \
            ghcr.io/damacus/github-cookstyle-runner:latest
```

#### Jenkins

```groovy
pipeline {
    agent any
    
    triggers {
        cron('0 2 * * *')
    }
    
    environment {
        GITHUB_APP_ID = credentials('github-app-id')
        GITHUB_APP_INSTALLATION_ID = credentials('github-app-installation-id')
        GITHUB_APP_PRIVATE_KEY = credentials('github-app-private-key')
    }
    
    stages {
        stage('Run Cookstyle') {
            steps {
                sh '''
                    docker run --rm \
                        -e GITHUB_APP_ID \
                        -e GITHUB_APP_INSTALLATION_ID \
                        -e GITHUB_APP_PRIVATE_KEY \
                        -e GCR_DESTINATION_REPO_OWNER=my-org \
                        -e GCR_DESTINATION_REPO_TOPICS=chef-cookbook \
                        -e GCR_GIT_EMAIL=bot@example.com \
                        -e GCR_GIT_NAME="Cookstyle Bot" \
                        ghcr.io/damacus/github-cookstyle-runner:latest
                '''
            }
        }
    }
}
```

### Webhook Integration

Trigger on repository events (requires custom wrapper):

```python
# webhook_handler.py
from flask import Flask, request
import subprocess

app = Flask(__name__)

@app.route('/webhook', methods=['POST'])
def handle_webhook():
    event = request.headers.get('X-GitHub-Event')
    payload = request.json
    
    if event == 'push':
        repo = payload['repository']['name']
        # Trigger Cookstyle Runner for specific repo
        subprocess.run([
            'docker', 'run', '--rm',
            '-e', f'GCR_FILTER_REPOS={repo}',
            # ... other env vars
            'ghcr.io/damacus/github-cookstyle-runner:latest'
        ])
    
    return '', 200
```

## Performance Optimization

### Memory-Constrained Environments

```bash
# Reduce thread count
GCR_THREAD_COUNT=2

# Process fewer repos at once
GCR_FILTER_REPOS=repo1,repo2

# Kubernetes: Set resource limits
resources:
  limits:
    memory: "512Mi"
```

### High-Throughput Environments

```bash
# Increase threads
GCR_THREAD_COUNT=16

# Aggressive caching
GCR_CACHE_MAX_AGE=30

# Kubernetes: Increase resources
resources:
  requests:
    memory: "1Gi"
    cpu: "1000m"
  limits:
    memory: "4Gi"
    cpu: "4000m"
```

## Monitoring and Observability

### Structured Logging

Parse logs for monitoring:

```bash
# Extract key metrics
docker-compose logs cookstyle-runner | grep "Summary:"

# Count PRs created
docker-compose logs cookstyle-runner | grep "Pull request created" | wc -l

# Find errors
docker-compose logs cookstyle-runner | grep "ERROR"
```

### Prometheus Metrics (Future)

```yaml
# Future feature - not yet implemented
metrics:
  - cookstyle_repos_processed_total
  - cookstyle_prs_created_total
  - cookstyle_offenses_found_total
  - cookstyle_processing_duration_seconds
```

### Alerting

Set up alerts for failures:

```bash
# Example: Send alert if exit code != 0
docker-compose up || curl -X POST https://alerts.example.com/webhook
```

## Cache Management

### Inspect Cache

```bash
# Docker Compose
docker-compose run --entrypoint cat cookstyle-runner /app/.cache/cache.json | jq

# Kubernetes
kubectl exec -it <pod-name> -- cat /app/.cache/cache.json | jq
```

### Clear Cache

```bash
# Docker Compose
docker-compose run --entrypoint rm cookstyle-runner /app/.cache/cache.json

# Kubernetes
kubectl exec -it <pod-name> -- rm /app/.cache/cache.json
```

### Backup Cache

```bash
# Docker Compose
docker cp <container-id>:/app/.cache/cache.json ./cache-backup.json

# Kubernetes
kubectl cp <pod-name>:/app/.cache/cache.json ./cache-backup.json
```

## Custom Cookstyle Rules

### Mount Custom .rubocop.yml

```yaml
# docker-compose.yml
services:
  cookstyle-runner:
    volumes:
      - ./custom-rubocop.yml:/app/.rubocop.yml:ro
```

Note: This affects the runner itself, not the target repositories.

## Troubleshooting Advanced Scenarios

### Rate Limiting

If you hit rate limits:

```bash
# Check rate limit status
curl -H "Authorization: Bearer <token>" \
  https://api.github.com/rate_limit

# Solutions:
# 1. Reduce thread count
GCR_THREAD_COUNT=2

# 2. Enable aggressive caching
GCR_CACHE_MAX_AGE=30

# 3. Process fewer repos
GCR_FILTER_REPOS=critical-repo1,critical-repo2
```

### Large Repository Sets

For organizations with 100+ repositories:

```bash
# Split into batches
# Batch 1
GCR_FILTER_REPOS=repo1,repo2,...,repo50

# Batch 2 (run later)
GCR_FILTER_REPOS=repo51,repo52,...,repo100
```

### Network Issues

Handle transient network failures:

```bash
# Increase retry count
GCR_RETRY_COUNT=5

# Enable debug logging
GCR_DEBUG_MODE=1
```

## Next Steps

- [Troubleshooting guide](troubleshooting.md)
- [Configuration reference](../configuration/index.md)
- [Basic usage](basic.md)
