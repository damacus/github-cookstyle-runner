# Basic Usage

Learn how to run the GitHub Cookstyle Runner and understand its output.

## Running the Application

### Docker Compose

```bash
# One-time run
docker-compose up

# Run in background
docker-compose up -d

# View logs
docker-compose logs -f cookstyle-runner
```

### Kubernetes

```bash
# Manually trigger a job
kubectl create job --from=cronjob/cookstyle-runner cookstyle-manual-run

# View logs
kubectl logs -f job/cookstyle-manual-run
```

### Local Development

```bash
# Run directly
./bin/cookstyle-runner

# Or with bundle
bundle exec ./bin/cookstyle-runner
```

## CLI Commands

### Run Cookstyle

Run Cookstyle on repositories:

```bash
# Run on all configured repositories
./bin/cookstyle-runner run

# Run on specific repositories
./bin/cookstyle-runner run repo1 repo2

# Dry run mode (preview only)
./bin/cookstyle-runner run --dry-run

# Force cache refresh
./bin/cookstyle-runner run --force

# Use specific number of threads
./bin/cookstyle-runner run --threads 8

# Disable cache for this run
./bin/cookstyle-runner run --no-cache

# Output format options
./bin/cookstyle-runner run --format json   # Structured JSON logs
./bin/cookstyle-runner run --format text   # Human-readable colored logs (default)
./bin/cookstyle-runner run --format table  # Same as text
```

### Version Information

```bash
# Display version information
./bin/cookstyle-runner version
```

### List Repositories

View repositories that would be processed:

```bash
# Text format (default) - simple list
./bin/cookstyle-runner list

# Table format - formatted output
./bin/cookstyle-runner list --format table

# JSON format for scripting
./bin/cookstyle-runner list --format json
```

**Table output example:**

```text
Found 3 repositories:
  1. apt
  2. nginx
  3. haproxy
```

### View Configuration

```bash
# Display current configuration
./bin/cookstyle-runner config

# Validate configuration only
./bin/cookstyle-runner config --validate

# Show help for config command
./bin/cookstyle-runner config --help
```

### Check Status

```bash
# View cache statistics (table format - default)
./bin/cookstyle-runner status

# Text format
./bin/cookstyle-runner status --format text

# JSON format for scripting
./bin/cookstyle-runner status --format json
```

## Understanding Output

### Startup

The application uses structured logging with timestamps and log levels:

```text
2025-01-15 10:30:00.123 INFO  [CookstyleRunner] GitHub Cookstyle Runner starting...
2025-01-15 10:30:00.234 INFO  [Configuration] Configuration loaded successfully
2025-01-15 10:30:00.345 INFO  [Authentication] GitHub App authenticated
2025-01-15 10:30:00.456 INFO  [Cache] Cache loaded: 15 entries
2025-01-15 10:30:00.567 INFO  [Configuration] Thread count: 4
2025-01-15 10:30:00.678 INFO  [Configuration] Cache max age: 7 days
```

### Repository Processing

```text
2025-01-15 10:30:01.123 INFO  [RepositoryFetcher] Found 23 repositories matching topics: chef-cookbook
2025-01-15 10:30:01.234 INFO  [RepositoryProcessor] Processing repositories...
2025-01-15 10:30:01.345 INFO  [RepositoryProcessor] [1/23] Processing: sous-chefs/apt
2025-01-15 10:30:01.456 INFO  [GitOperations] [1/23] Cloning repository...
2025-01-15 10:30:05.567 INFO  [CookstyleOperations] [1/23] Running Cookstyle...
2025-01-15 10:30:10.678 INFO  [CookstyleOperations] [1/23] Found 3 offenses (1 auto-correctable, 2 manual)
2025-01-15 10:30:10.789 INFO  [PullRequestManager] [1/23] Creating pull request...
2025-01-15 10:30:11.890 INFO  [PullRequestManager] [1/23] ✓ Pull request created: #42
2025-01-15 10:30:12.001 INFO  [RepositoryProcessor] [2/23] Processing: sous-chefs/nginx
2025-01-15 10:30:12.112 INFO  [Cache] [2/23] ✓ No offenses found (cached)
```

### Completion

```text
2025-01-15 10:35:00.123 INFO  [RepositoryProcessor] Processing complete
2025-01-15 10:35:00.234 INFO  [RepositoryProcessor] Summary:
2025-01-15 10:35:00.345 INFO  [RepositoryProcessor]   Total repositories: 23
2025-01-15 10:35:00.456 INFO  [RepositoryProcessor]   Processed: 23
2025-01-15 10:35:00.567 INFO  [RepositoryProcessor]   Skipped (cached): 15
2025-01-15 10:35:00.678 INFO  [RepositoryProcessor]   Pull requests created: 5
2025-01-15 10:35:00.789 INFO  [RepositoryProcessor]   Issues created: 2
2025-01-15 10:35:00.890 INFO  [RepositoryProcessor]   Errors: 0
2025-01-15 10:35:01.001 INFO  [Cache] Cache saved: 23 entries
```

## Common Workflows

### First Run

On your first run, the application will:

1. Authenticate with GitHub
2. Search for repositories by topics
3. Clone each repository
4. Run Cookstyle
5. Create PRs for auto-correctable issues
6. Cache results

**Expected time**: 2-5 minutes per repository (depending on size)

### Subsequent Runs

With caching enabled:

1. Load cache
2. Check each repository's latest commit SHA
3. Skip unchanged repositories
4. Process only changed repositories

**Expected time**: Seconds for cached repos, 2-5 minutes for changed repos

### Force Refresh

To reprocess all repositories:

```bash
# Docker Compose
docker-compose run -e GCR_FORCE_REFRESH=1 cookstyle-runner

# Kubernetes
kubectl set env cronjob/cookstyle-runner GCR_FORCE_REFRESH=1
kubectl create job --from=cronjob/cookstyle-runner cookstyle-force-refresh
kubectl set env cronjob/cookstyle-runner GCR_FORCE_REFRESH-  # Remove after
```

## Pull Request Output

### Auto-Correctable Issues

When Cookstyle finds auto-correctable issues, a PR is created with:

**Title**: `Automated PR: Cookstyle Changes`

**Body**:

```markdown
## Cookstyle Auto-Corrections

This PR contains automatic fixes from Cookstyle.

### Summary
- **Total Offenses**: 5
- **Auto-Corrected**: 5

### Files Changed
- `recipes/default.rb`: 3 offenses
- `recipes/install.rb`: 2 offenses

### Cookstyle Version
7.32.1

---
*This PR was automatically created by the GitHub Cookstyle Runner*
```

### Manual Fix Issues

When `GCR_CREATE_MANUAL_FIX_PRS=1`, PRs are created for manual fixes with detailed instructions:

**Title**: `Cookstyle: Manual Fixes Required`

**Body**:

```markdown
## Cookstyle Manual Fixes Required

The following issues require manual intervention:

### test/integration/default/default_spec.rb
**Line 1**: Chef/Deprecations/ResourceWithoutUnifiedTrue
> Set `unified_mode true` in your custom resources

### recipes/config.rb
**Line 45**: Chef/Correctness/InvalidPlatformHelper
> Use valid platform helper methods

---
*This PR was automatically created by the GitHub Cookstyle Runner*
```

## Processing Specific Repositories

### Single Repository

```bash
docker-compose run -e GCR_FILTER_REPOS=apt cookstyle-runner
```

### Multiple Repositories

```bash
docker-compose run -e GCR_FILTER_REPOS=apt,nginx,haproxy cookstyle-runner
```

## Monitoring Progress

### Real-time Logs

```bash
# Docker Compose
docker-compose logs -f cookstyle-runner

# Kubernetes
kubectl logs -f -l app=cookstyle-runner
```

### Check GitHub

- **Pull Requests**: Check your organization's repositories for new PRs
- **Issues**: Check for new issues (if `GCR_CREATE_MANUAL_FIX_PRS=1`)

## Global Options

These options work with any command:

```bash
# Enable verbose output (DEBUG level)
./bin/cookstyle-runner <command> --verbose
./bin/cookstyle-runner <command> -v

# Quiet mode (ERROR level only)
./bin/cookstyle-runner <command> --quiet
./bin/cookstyle-runner <command> -q

# Set specific log level
./bin/cookstyle-runner <command> --log-level DEBUG
./bin/cookstyle-runner <command> --log-level WARN

# Show help for any command
./bin/cookstyle-runner <command> --help
./bin/cookstyle-runner <command> -h
```

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success - all repositories processed |
| 1 | Configuration error |
| 2 | Authentication error |
| 3 | Runtime error |

## Next Steps

- [Learn about advanced features](advanced.md)
- [Troubleshooting common issues](troubleshooting.md)
- [Configure the application](../configuration/index.md)
