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

### List Repositories

View repositories that would be processed:

```bash
# Simple table format (default)
./bin/cookstyle-runner list

# Pretty table format with borders
./bin/cookstyle-runner list --format pretty

# JSON format for scripting
./bin/cookstyle-runner list --format json
```

**Pretty table output example:**

```text
╭─────────────────────────╮
│ Found 3 repositories    │
├────┬────────────────────┤
│  # │ Repository         │
├────┼────────────────────┤
│  1 │ apt                │
│  2 │ nginx              │
│  3 │ haproxy            │
╰────┴────────────────────╯
```

### View Configuration

```bash
# Display current configuration
./bin/cookstyle-runner config

# Validate configuration
./bin/cookstyle-runner config --validate
```

### Check Status

```bash
# View cache statistics (simple table)
./bin/cookstyle-runner status

# Pretty table format
./bin/cookstyle-runner status --format pretty

# JSON format for scripting
./bin/cookstyle-runner status --format json
```

## Understanding Output

### Startup

```text
[INFO] GitHub Cookstyle Runner starting...
[INFO] Configuration loaded successfully
[INFO] GitHub App authenticated
[INFO] Cache loaded: 15 entries
[INFO] Thread count: 4
[INFO] Cache max age: 7 days
```

### Repository Processing

```text
[INFO] Found 23 repositories matching topics: chef-cookbook
[INFO] Processing repositories...
[INFO] [1/23] Processing: sous-chefs/apt
[INFO] [1/23] Cloning repository...
[INFO] [1/23] Running Cookstyle...
[INFO] [1/23] Found 3 offenses (1 auto-correctable, 2 manual)
[INFO] [1/23] Creating pull request...
[INFO] [1/23] ✓ Pull request created: #42
[INFO] [2/23] Processing: sous-chefs/nginx
[INFO] [2/23] ✓ No offenses found (cached)
```

### Completion

```text
[INFO] Processing complete
[INFO] Summary:
[INFO]   Total repositories: 23
[INFO]   Processed: 23
[INFO]   Skipped (cached): 15
[INFO]   Pull requests created: 5
[INFO]   Issues created: 2
[INFO]   Errors: 0
[INFO] Cache saved: 23 entries
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
