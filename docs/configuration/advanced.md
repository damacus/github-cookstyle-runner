# Advanced Configuration

Advanced configuration options and patterns for power users.

## Custom Configuration Files

While environment variables are the primary configuration method, you can use YAML configuration files for local development.

### Local Configuration

Create `config/settings/local.yml`:

```yaml
github:
  app_id: "123456"
  app_installation_id: "789012"
  app_private_key: |
    -----BEGIN RSA PRIVATE KEY-----
    ...
    -----END RSA PRIVATE KEY-----

destination:
  repo_owner: "my-org"
  repo_topics:
    - chef-cookbook
    - chef

git:
  email: "bot@example.com"
  name: "Cookstyle Bot"
  branch_name: "automated/cookstyle"
  default_branch: "main"

pull_request:
  title: "Automated Cookstyle Fixes"
  labels:
    - tech-debt
    - automated

cache:
  enabled: true
  max_age_days: 7

performance:
  thread_count: 4
  retry_count: 3
  debug_mode: false
```

!!! note
    Environment variables take precedence over configuration files.

## Performance Tuning

### Thread Count Optimization

The optimal thread count depends on your environment:

```bash
# Conservative (low memory, rate limit concerns)
GCR_THREAD_COUNT=2

# Balanced (default)
GCR_THREAD_COUNT=4

# Aggressive (high memory, many repos)
GCR_THREAD_COUNT=16
```

### Memory Considerations

Each thread processes one repository at a time. Estimate memory needs:

- Base application: ~100MB
- Per thread: ~50-100MB
- Per repository clone: ~10-50MB (varies by repo size)

**Example**: 8 threads = ~100MB + (8 × 100MB) = ~900MB minimum

### Rate Limiting

GitHub API rate limits:

- **Authenticated**: 5,000 requests/hour
- **Per repository**: ~10-20 API calls

**Calculation**: With 5,000 requests/hour, you can process ~250-500 repositories/hour.

To avoid rate limiting:

```bash
# Enable caching
GCR_USE_CACHE=1
GCR_CACHE_MAX_AGE=7

# Reduce thread count
GCR_THREAD_COUNT=4

# Process specific repos
GCR_FILTER_REPOS=repo1,repo2,repo3
```

## Repository Filtering Strategies

### Process Specific Repositories

```bash
# Only process these repos
GCR_FILTER_REPOS=apt,nginx,haproxy
```

### Topic-Based Filtering

```bash
# Find repos with multiple topics (AND logic)
GCR_DESTINATION_REPO_TOPICS=chef-cookbook,production

# Note: GitHub searches for repos with ALL specified topics
```

### Exclude Repositories

Currently not supported via environment variables. Use `GCR_FILTER_REPOS` to explicitly list repositories to process.

## GitHub Enterprise Support

For GitHub Enterprise installations:

```bash
# Set custom API root
GITHUB_API_ROOT=github.company.com/api/v3

# Ensure your GitHub App is installed on your Enterprise instance
GITHUB_APP_ID=<your-enterprise-app-id>
GITHUB_APP_INSTALLATION_ID=<your-enterprise-installation-id>
```

## Cache Management

### Cache Location

- **Docker**: `/app/.cache/cache.json`
- **Kubernetes**: Mounted PersistentVolume at `/app/.cache`
- **Local**: `./cache.json`

### Cache Structure

```json
{
  "owner/repo": {
    "last_checked": "2025-10-06T14:30:00Z",
    "last_sha": "abc123...",
    "offense_count": 5,
    "auto_correctable": 3,
    "manual_fixes": 2
  }
}
```

### Cache Strategies

#### Aggressive Caching (Minimize API Calls)

```bash
GCR_USE_CACHE=1
GCR_CACHE_MAX_AGE=30  # 30 days
GCR_FORCE_REFRESH=0
```

#### Balanced Caching (Default)

```bash
GCR_USE_CACHE=1
GCR_CACHE_MAX_AGE=7  # 7 days
GCR_FORCE_REFRESH=0
```

#### Minimal Caching (Always Fresh)

```bash
GCR_USE_CACHE=1
GCR_CACHE_MAX_AGE=1  # 1 day
GCR_FORCE_REFRESH=0
```

#### No Caching (Testing)

```bash
GCR_USE_CACHE=0
# or
GCR_FORCE_REFRESH=1
```

## Pull Request Strategies

### Auto-Correctable Only

```bash
# Don't create PRs for manual fixes
GCR_CREATE_MANUAL_FIX_PRS=0
```

### All Issues

```bash
# Create PRs for both auto-correctable and manual fixes
GCR_CREATE_MANUAL_FIX_PRS=1
```

### Custom PR Labels

```bash
# Organize PRs with labels
GCR_PULL_REQUEST_LABELS=cookstyle,tech-debt,automated,priority-low
```

## Debugging

### Enable Debug Logging

```bash
GCR_DEBUG_MODE=1
```

Debug mode provides:

- Detailed API request/response logs
- Repository processing steps
- Cache hit/miss information
- Cookstyle command output

### Test Single Repository

```bash
GCR_FILTER_REPOS=test-repo
GCR_DEBUG_MODE=1
GCR_THREAD_COUNT=1
GCR_USE_CACHE=0
```

## Security Best Practices

### Secrets Management

Never hardcode secrets. Use:

1. **Environment variables** (Docker Compose `.env`)
2. **Kubernetes Secrets**
3. **Secret managers** (Vault, AWS Secrets Manager, etc.)

### Least Privilege

Configure GitHub App with minimum required permissions:

- **Repository**: Contents (read/write), Pull Requests (read/write)
- **Organization**: Members (read) - only if needed for repo discovery

### Credential Rotation

Regularly rotate GitHub App private keys:

```bash
# Generate new key in GitHub App settings
# Update secret in your deployment
# Revoke old key after verification
```

## Multi-Organization Support

To process repositories across multiple organizations, deploy separate instances:

```yaml
# Instance 1: Organization A
services:
  cookstyle-runner-org-a:
    image: ghcr.io/damacus/github-cookstyle-runner:latest
    environment:
      - GCR_DESTINATION_REPO_OWNER=org-a
      - GITHUB_APP_INSTALLATION_ID=<org-a-installation-id>
      # ... other config

# Instance 2: Organization B
  cookstyle-runner-org-b:
    image: ghcr.io/damacus/github-cookstyle-runner:latest
    environment:
      - GCR_DESTINATION_REPO_OWNER=org-b
      - GITHUB_APP_INSTALLATION_ID=<org-b-installation-id>
      # ... other config
```

## Next Steps

- [Environment variables reference](environment-variables.md)
- [Usage examples](../usage/basic.md)
- [Troubleshooting](../usage/troubleshooting.md)
