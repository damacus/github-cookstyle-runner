# Troubleshooting

Common issues and their solutions.

## Authentication Issues

### Symptom: 401 Unauthorized

```text
[ERROR] GitHub API authentication failed: 401 Unauthorized
```

**Causes**:

- Invalid GitHub App ID
- Invalid Installation ID
- Invalid or expired private key
- App not installed on organization

**Solutions**:

1. Verify GitHub App credentials:

```bash
# Check App ID and Installation ID are numeric
echo $GITHUB_APP_ID
echo $GITHUB_APP_INSTALLATION_ID

# Verify private key format
echo "$GITHUB_APP_PRIVATE_KEY" | head -1
# Should output: -----BEGIN RSA PRIVATE KEY-----
```

1. Verify App installation:
   - Go to GitHub → Settings → GitHub Apps
   - Check that the app is installed on your organization
   - Verify the Installation ID matches

1. Generate new private key:
   - GitHub App settings → Generate new private key
   - Update `GITHUB_APP_PRIVATE_KEY` environment variable

### Symptom: 403 Forbidden

```text
[ERROR] GitHub API request failed: 403 Forbidden
```

**Causes**:

- Insufficient permissions
- Rate limiting
- Repository access denied

**Solutions**:

1. Check GitHub App permissions:
   - Repository: Contents (read/write)
   - Repository: Pull Requests (read/write)
   - Repository: Issues (read/write)
   - Organization: Members (read)

2. Check rate limits:

```bash
# View rate limit status in logs
docker-compose logs cookstyle-runner | grep "rate limit"

# Enable caching to reduce API calls
GCR_USE_CACHE=1
GCR_CACHE_MAX_AGE=7
```

## Configuration Issues

### Symptom: Missing Required Configuration

```text
[ERROR] Configuration validation failed:
  - github.app_id is required
  - destination.repo_owner is required
```

**Solution**:

Ensure all required environment variables are set:

```bash
# Required variables
GITHUB_APP_ID=123456
GITHUB_APP_INSTALLATION_ID=789012
GITHUB_APP_PRIVATE_KEY="-----BEGIN RSA PRIVATE KEY-----..."
GCR_DESTINATION_REPO_OWNER=my-org
GCR_DESTINATION_REPO_TOPICS=chef-cookbook
GCR_GIT_EMAIL=bot@example.com
GCR_GIT_NAME=Cookstyle Bot
```

### Symptom: Invalid Configuration Values

```text
[ERROR] Configuration validation failed:
  - cache.max_age_days must be a positive integer
```

**Solution**:

Check data types:

```bash
# Must be numeric
GCR_CACHE_MAX_AGE=7  # Not "7 days"
GCR_THREAD_COUNT=4   # Not "four"

# Must be 0 or 1 for booleans
GCR_USE_CACHE=1      # Not "true"
GCR_DEBUG_MODE=0     # Not "false"
```

## Repository Processing Issues

### Symptom: No Repositories Found

```text
[INFO] Found 0 repositories matching topics: chef-cookbook
```

**Causes**:

- No repositories have the specified topics
- GitHub App doesn't have access to repositories
- Wrong organization name

**Solutions**:

1. Verify organization name:

```bash
# Check spelling and case
GCR_DESTINATION_REPO_OWNER=my-org  # Not My-Org
```

1. Check repository topics:
   - Go to repositories on GitHub
   - Verify they have the specified topics

1. Use specific repository filter:

```bash
GCR_FILTER_REPOS=known-repo-name
```

### Symptom: Repository Clone Failed

```text
[ERROR] Failed to clone repository: sous-chefs/apt
fatal: could not read Username for 'https://github.com'
```

**Causes**:

- Authentication failure
- Network issues
- Repository doesn't exist

**Solutions**:

1. Verify authentication (see Authentication Issues above)

1. Check repository exists:

```bash
# Test manually
git clone https://github.com/owner/repo
```

1. Check network connectivity:

```bash
# Test GitHub connectivity
curl -I https://github.com
```

### Symptom: Cookstyle Command Failed

```text
[ERROR] Cookstyle command failed with exit code 1
```

**Causes**:

- Invalid Ruby syntax in target repository
- Cookstyle not installed
- Permission issues

**Solutions**:

1. Enable debug mode:

```bash
GCR_DEBUG_MODE=1
```

1. Test Cookstyle manually:

```bash
# Access container
docker-compose exec cookstyle-runner /bin/bash

# Run Cookstyle
cd /tmp/repos/owner/repo
cookstyle --version
cookstyle -a --format json
```

## Pull Request Issues

### Symptom: PR Creation Failed

```text
[ERROR] Failed to create pull request: 422 Unprocessable Entity
```

**Causes**:

- Branch already exists
- No changes to commit
- Invalid branch name
- Base branch doesn't exist

**Solutions**:

1. Check if PR already exists:
   - Go to repository on GitHub
   - Check for existing PR from the branch

2. Verify branch configuration:

```bash
# Check branch names are valid
GCR_BRANCH_NAME=automated/cookstyle  # Valid
GCR_DEFAULT_GIT_BRANCH=main          # Must exist in repo
```

1. Force refresh to recreate:

```bash
GCR_FORCE_REFRESH=1
```

### Symptom: No PRs Created

```text
[INFO] Processing complete
[INFO]   Pull requests created: 0
```

**Causes**:

- No offenses found (good!)
- All repositories cached and unchanged
- Cookstyle auto-correction disabled

**Solutions**:

1. Check if offenses exist:

```bash
# Enable debug mode to see Cookstyle output
GCR_DEBUG_MODE=1
```

1. Force refresh to bypass cache:

```bash
GCR_FORCE_REFRESH=1
```

1. Test specific repository:

```bash
GCR_FILTER_REPOS=repo-with-known-issues
GCR_USE_CACHE=0
```

## Cache Issues

### Symptom: Cache Not Working

```text
[INFO] [1/23] Processing: sous-chefs/apt (not cached)
[INFO] [2/23] Processing: sous-chefs/nginx (not cached)
```

**Causes**:

- Cache disabled
- Cache file corrupted
- Cache volume not mounted

**Solutions**:

1. Verify cache is enabled:

```bash
GCR_USE_CACHE=1
```

1. Check cache volume:

```bash
# Docker Compose
docker-compose exec cookstyle-runner ls -la /app/.cache/

# Kubernetes
kubectl exec <pod-name> -- ls -la /app/.cache/
```

1. Clear and rebuild cache:

```bash
# Remove cache file
docker-compose run --entrypoint rm cookstyle-runner /app/.cache/cache.json

# Run again to rebuild
docker-compose up
```

### Symptom: Stale Cache

```text
[INFO] [1/23] Processing: sous-chefs/apt (cached)
# But repository has new commits
```

**Causes**:

- Cache max age too high
- Repository SHA not updated

**Solutions**:

1. Reduce cache max age:

```bash
GCR_CACHE_MAX_AGE=1  # 1 day
```

1. Force refresh:

```bash
GCR_FORCE_REFRESH=1
```

## Performance Issues

### Symptom: Out of Memory (OOMKilled)

```text
[ERROR] Container killed: OOMKilled
```

**Solutions**:

1. Reduce thread count:

```bash
GCR_THREAD_COUNT=2
```

1. Increase memory limits (Kubernetes):

```yaml
resources:
  limits:
    memory: "2Gi"
```

1. Process fewer repositories:

```bash
GCR_FILTER_REPOS=repo1,repo2,repo3
```

### Symptom: Slow Processing

```text
[INFO] Processing taking longer than expected
```

**Solutions**:

1. Enable caching:

```bash
GCR_USE_CACHE=1
GCR_CACHE_MAX_AGE=7
```

1. Increase thread count:

```bash
GCR_THREAD_COUNT=8
```

1. Check network latency:

```bash
# Test GitHub API response time
time curl -I https://api.github.com
```

## Docker Issues

### Symptom: Image Pull Failed

```text
Error response from daemon: pull access denied
```

**Solution**:

Verify image name and tag:

```bash
docker pull ghcr.io/damacus/github-cookstyle-runner:latest
```

### Symptom: Volume Mount Permission Denied

```text
[ERROR] Permission denied: /app/.cache/cache.json
```

**Solution**:

Fix volume permissions:

```bash
# Create cache directory with correct permissions
mkdir -p /tmp/cookstyle-runner
chmod 777 /tmp/cookstyle-runner
```

## Kubernetes Issues

### Symptom: CronJob Not Running

```shell
kubectl get cronjob cookstyle-runner
# Shows but never creates jobs
```

**Solutions**:

1. Check CronJob schedule:

```shell
kubectl describe cronjob cookstyle-runner
```

1. Manually trigger job:

```shell
kubectl create job --from=cronjob/cookstyle-runner test-run
```

1. Check events:

```shell
kubectl get events --sort-by='.lastTimestamp'
```

### Symptom: Pod Fails to Start

```shell
kubectl get pods
# Shows CrashLoopBackOff or Error
```

**Solutions**:

1. Check pod logs:

```shell
kubectl logs <pod-name>
```

1. Check pod events:

```shell
kubectl describe pod <pod-name>
```

1. Verify secrets and configmaps:

```shell
kubectl get secret cookstyle-runner-secrets
kubectl get configmap cookstyle-runner-config
```

## Getting Help

If you're still experiencing issues:

1. **Enable debug logging**:

```shell
GCR_DEBUG_MODE=1
```

1. **Collect logs**:

```shell
# Docker Compose
docker-compose logs cookstyle-runner > logs.txt

# Kubernetes
kubectl logs <pod-name> > logs.txt
```

1. **Open an issue**:
   - Go to [GitHub Issues](https://github.com/damacus/github-cookstyle-runner/issues)
   - Include:
     - Error message
     - Configuration (redact secrets!)
     - Logs (redact sensitive data!)
     - Environment (Docker/Kubernetes, versions)

## Next Steps

- [Basic usage guide](basic.md)
- [Advanced usage patterns](advanced.md)
- [Configuration reference](../configuration/index.md)
