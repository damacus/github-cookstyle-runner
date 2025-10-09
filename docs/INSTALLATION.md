# Installation Guide

This guide covers installing and running the GitHub Cookstyle Runner in different environments.

## Prerequisites

Before installing, ensure you have:

1. **GitHub App Credentials**:
   - GitHub App ID
   - GitHub App Installation ID
   - GitHub App Private Key (PEM format)
   - See [GitHub App Setup Guide](https://docs.github.com/en/apps/creating-github-apps) for creating a GitHub App

2. **Required Permissions**:
   - The GitHub App must have permissions to:
     - Read repository contents
     - Create branches
     - Create pull requests
     - Read repository metadata

3. **Environment Requirements**:
   - Docker (for docker-compose installation)
   - Kubernetes cluster (for Kubernetes installation)
   - kubectl configured (for Kubernetes installation)

## Installation Methods

### 1. Docker Compose

Docker Compose is ideal for local development, testing, or running on a single host.

#### Setup

1. **Create a docker-compose.yml file**:

```yaml
services:
  cookstyle-runner:
    image: ghcr.io/damacus/github-cookstyle-runner:latest
    volumes:
      # Persistent cache for improved performance
      - cookstyle_cache:/app/.cache
      # Optional: mount custom configuration
      # - ./config/settings/local.yml:/app/config/settings/local.yml
    environment:
      # Required: GitHub App Authentication
      - GITHUB_APP_ID=${GITHUB_APP_ID}
      - GITHUB_APP_INSTALLATION_ID=${GITHUB_APP_INSTALLATION_ID}
      - GITHUB_APP_PRIVATE_KEY=${GITHUB_APP_PRIVATE_KEY}

      # Required: Repository Configuration
      - GCR_DESTINATION_REPO_OWNER=your-org-name
      - GCR_DESTINATION_REPO_TOPICS=chef-cookbook

      # Required: Git Configuration
      - GCR_GIT_EMAIL=bot@example.com
      - GCR_GIT_NAME=Cookstyle Bot

      # Optional: Branch Configuration
      - GCR_BRANCH_NAME=automated/cookstyle
      - GCR_DEFAULT_GIT_BRANCH=main

      # Optional: Pull Request Configuration
      - GCR_PULL_REQUEST_TITLE=Automated PR: Cookstyle Changes
      - GCR_PULL_REQUEST_LABELS=tech-debt,automated
      - GCR_CREATE_MANUAL_FIX_PRS=1

      # Optional: Cache Configuration
      - GCR_USE_CACHE=1
      - GCR_CACHE_MAX_AGE=7
      - GCR_FORCE_REFRESH=0

      # Optional: Performance Configuration
      - GCR_THREAD_COUNT=4
      - GCR_RETRY_COUNT=3
      - GCR_DEBUG_MODE=0

      # Optional: Repository Filtering
      # - GCR_FILTER_REPOS=repo1,repo2,repo3

volumes:
  cookstyle_cache:
```

1. **Create a .env file** (recommended for sensitive data):

```bash
# .env
GITHUB_APP_ID=123456
GITHUB_APP_INSTALLATION_ID=789012
GITHUB_APP_PRIVATE_KEY="-----BEGIN RSA PRIVATE KEY-----
MIIEpAIBAAKCAQEA...
-----END RSA PRIVATE KEY-----"
```

1. **Run the application**:

```bash
# One-time run
docker-compose up

# Run in background
docker-compose up -d

# View logs
docker-compose logs -f

# Stop the application
docker-compose down
```

#### Scheduled Runs with Docker Compose

For scheduled runs, use a cron job on the host:

```bash
# Edit crontab
crontab -e

# Add entry to run daily at 2 AM
0 2 * * * cd /path/to/cookstyle-runner && docker-compose run -it --rm app
```

### 2. Kubernetes

Kubernetes is ideal for production deployments, especially when using CronJobs for scheduled runs.

#### Setup

1. **Create a Secret for GitHub App credentials**:

```bash
# Create secret from file
kubectl create secret generic cookstyle-runner-secrets \
  --from-literal=github-app-id=123456 \
  --from-literal=github-app-installation-id=789012 \
  --from-file=github-app-private-key=/path/to/private-key.pem \
  --namespace=default
```

Or create from YAML:

```yaml
# secrets.yaml
apiVersion: v1
kind: Secret
metadata:
  name: cookstyle-runner-secrets
  namespace: default
type: Opaque
stringData:
  github-app-id: "123456"
  github-app-installation-id: "789012"
  github-app-private-key: |
    -----BEGIN RSA PRIVATE KEY-----
    MIIEpAIBAAKCAQEA...
    -----END RSA PRIVATE KEY-----
```

```bash
kubectl apply -f secrets.yaml
```

1. **Create a ConfigMap for application configuration**:

```yaml
# configmap.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: cookstyle-runner-config
  namespace: default
data:
  GCR_DESTINATION_REPO_OWNER: "your-org-name"
  GCR_DESTINATION_REPO_TOPICS: "chef-cookbook"
  GCR_GIT_EMAIL: "bot@example.com"
  GCR_GIT_NAME: "Cookstyle Bot"
  GCR_BRANCH_NAME: "automated/cookstyle"
  GCR_DEFAULT_GIT_BRANCH: "main"
  GCR_PULL_REQUEST_TITLE: "Automated PR: Cookstyle Changes"
  GCR_PULL_REQUEST_LABELS: "tech-debt,automated"
  GCR_CREATE_MANUAL_FIX_PRS: "1"
  GCR_USE_CACHE: "1"
  GCR_CACHE_MAX_AGE: "7"
  GCR_THREAD_COUNT: "4"
  GCR_RETRY_COUNT: "3"
  GCR_DEBUG_MODE: "0"
```

```bash
kubectl apply -f configmap.yaml
```

1. **Create a CronJob for scheduled runs**:

```yaml
# cronjob.yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: cookstyle-runner
  namespace: default
spec:
  # Run daily at 2 AM UTC
  schedule: "0 2 * * *"

  # Keep last 3 successful and 1 failed job for debugging
  successfulJobsHistoryLimit: 3
  failedJobsHistoryLimit: 1

  # Don't start new job if previous is still running
  concurrencyPolicy: Forbid

  jobTemplate:
    spec:
      # Clean up completed jobs after 1 hour
      ttlSecondsAfterFinished: 3600

      template:
        metadata:
          labels:
            app: cookstyle-runner
        spec:
          restartPolicy: OnFailure

          containers:
          - name: cookstyle-runner
            image: ghcr.io/damacus/github-cookstyle-runner:latest
            imagePullPolicy: Always

            # Resource limits (adjust based on your needs)
            resources:
              requests:
                memory: "512Mi"
                cpu: "500m"
              limits:
                memory: "2Gi"
                cpu: "2000m"

            # Environment variables from ConfigMap
            envFrom:
            - configMapRef:
                name: cookstyle-runner-config

            # Sensitive environment variables from Secret
            env:
            - name: GITHUB_APP_ID
              valueFrom:
                secretKeyRef:
                  name: cookstyle-runner-secrets
                  key: github-app-id
            - name: GITHUB_APP_INSTALLATION_ID
              valueFrom:
                secretKeyRef:
                  name: cookstyle-runner-secrets
                  key: github-app-installation-id
            - name: GITHUB_APP_PRIVATE_KEY
              valueFrom:
                secretKeyRef:
                  name: cookstyle-runner-secrets
                  key: github-app-private-key

            # Persistent cache volume
            volumeMounts:
            - name: cache
              mountPath: /app/.cache

          volumes:
          - name: cache
            persistentVolumeClaim:
              claimName: cookstyle-runner-cache
```

1. **Create a PersistentVolumeClaim for cache**:

```yaml
# pvc.yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: cookstyle-runner-cache
  namespace: default
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 5Gi
  # Optional: specify storage class
  # storageClassName: standard
```

1. **Deploy to Kubernetes**:

```bash
# Apply all resources
kubectl apply -f secrets.yaml
kubectl apply -f configmap.yaml
kubectl apply -f pvc.yaml
kubectl apply -f cronjob.yaml

# Verify deployment
kubectl get cronjob cookstyle-runner
kubectl get pvc cookstyle-runner-cache

# Manually trigger a job for testing
kubectl create job --from=cronjob/cookstyle-runner cookstyle-runner-manual-test

# View job logs
kubectl logs -f job/cookstyle-runner-manual-test

# Clean up manual test job
kubectl delete job cookstyle-runner-manual-test
```

#### Alternative: Kubernetes Job (One-time Run)

For one-time runs instead of scheduled CronJobs:

```yaml
# job.yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: cookstyle-runner-oneshot
  namespace: default
spec:
  ttlSecondsAfterFinished: 3600
  template:
    metadata:
      labels:
        app: cookstyle-runner
    spec:
      restartPolicy: OnFailure
      containers:
      - name: cookstyle-runner
        image: ghcr.io/damacus/github-cookstyle-runner:latest
        envFrom:
        - configMapRef:
            name: cookstyle-runner-config
        env:
        - name: GITHUB_APP_ID
          valueFrom:
            secretKeyRef:
              name: cookstyle-runner-secrets
              key: github-app-id
        - name: GITHUB_APP_INSTALLATION_ID
          valueFrom:
            secretKeyRef:
              name: cookstyle-runner-secrets
              key: github-app-installation-id
        - name: GITHUB_APP_PRIVATE_KEY
          valueFrom:
            secretKeyRef:
              name: cookstyle-runner-secrets
              key: github-app-private-key
        volumeMounts:
        - name: cache
          mountPath: /app/.cache
      volumes:
      - name: cache
        persistentVolumeClaim:
          claimName: cookstyle-runner-cache
```

```bash
kubectl apply -f job.yaml
kubectl logs -f job/cookstyle-runner-oneshot
```

## Configuration

See the main [README.md](../README.md) for detailed configuration options.

### Common Configuration Patterns

#### Process Only Specific Repositories

```yaml
environment:
  - GCR_FILTER_REPOS=repo1,repo2,repo3
```

#### Enable Debug Logging

```yaml
environment:
  - GCR_DEBUG_MODE=1
```

#### Force Refresh All Repositories

```yaml
environment:
  - GCR_FORCE_REFRESH=1
```

#### Disable Caching

```yaml
environment:
  - GCR_USE_CACHE=0
```

## Monitoring and Troubleshooting

### Docker Compose

```bash
# View logs
docker-compose logs -f cookstyle-runner

# Check container status
docker-compose ps

# Access container shell
docker-compose exec cookstyle-runner /bin/bash
```

### Kubernetes

```bash
# View CronJob status
kubectl get cronjob cookstyle-runner

# View recent jobs
kubectl get jobs --selector=app=cookstyle-runner

# View logs from most recent job
kubectl logs -l app=cookstyle-runner --tail=100

# View logs from specific job
kubectl logs job/cookstyle-runner-28934567

# Describe CronJob for events
kubectl describe cronjob cookstyle-runner

# Check cache PVC
kubectl get pvc cookstyle-runner-cache
kubectl describe pvc cookstyle-runner-cache
```

### Common Issues

#### Rate Limiting

**Symptom**: GitHub API rate limit errors

**Solution**:

- Reduce run frequency
- Use caching (`GCR_USE_CACHE=1`)
- Increase `GCR_CACHE_MAX_AGE`
- Use `GCR_FILTER_REPOS` to process fewer repositories

#### Authentication Errors

**Symptom**: 401 or 403 errors from GitHub API

**Solution**:

- Verify GitHub App credentials are correct
- Ensure GitHub App has required permissions
- Check that Installation ID matches your organization
- Verify private key is in correct PEM format

#### Out of Memory

**Symptom**: Container killed or OOMKilled status

**Solution**:

- Reduce `GCR_THREAD_COUNT`
- Increase memory limits in Kubernetes
- Process fewer repositories at once using `GCR_FILTER_REPOS`

#### Cache Issues

**Symptom**: Repositories not being cached or stale cache

**Solution**:

- Check cache volume is mounted correctly
- Verify cache directory has write permissions
- Use `GCR_FORCE_REFRESH=1` to bypass cache
- Adjust `GCR_CACHE_MAX_AGE` for your needs

## Security Best Practices

1. **Never commit secrets to version control**
   - Use `.env` files (add to `.gitignore`)
   - Use Kubernetes Secrets
   - Use secret management tools (Vault, AWS Secrets Manager, etc.)

2. **Use least-privilege GitHub App permissions**
   - Only grant required permissions
   - Use separate GitHub Apps for different environments

3. **Rotate credentials regularly**
   - Generate new GitHub App private keys periodically
   - Update secrets in your deployment

4. **Restrict network access**
   - Use Kubernetes NetworkPolicies
   - Limit egress to GitHub API endpoints only

5. **Monitor and audit**
   - Enable GitHub App webhook logs
   - Monitor application logs for suspicious activity
   - Set up alerts for authentication failures

## Upgrading

### Docker Compose

```bash
# Pull latest image
docker-compose pull

# Restart with new image
docker-compose up -d
```

### Kubernetes

```bash
# Update image in CronJob
kubectl set image cronjob/cookstyle-runner cookstyle-runner=ghcr.io/damacus/github-cookstyle-runner:latest

# Or apply updated manifest
kubectl apply -f cronjob.yaml

# Verify update
kubectl describe cronjob cookstyle-runner | grep Image
```

## Uninstallation

### Docker Compose

```bash
# Stop and remove containers
docker-compose down

# Remove volumes (including cache)
docker-compose down -v

# Remove images
docker rmi ghcr.io/damacus/github-cookstyle-runner:latest
```

### Kubernetes

```bash
# Delete all resources
kubectl delete cronjob cookstyle-runner
kubectl delete configmap cookstyle-runner-config
kubectl delete secret cookstyle-runner-secrets
kubectl delete pvc cookstyle-runner-cache

# Or delete by file
kubectl delete -f cronjob.yaml
kubectl delete -f configmap.yaml
kubectl delete -f secrets.yaml
kubectl delete -f pvc.yaml
```

## Next Steps

- Review [Configuration Options](../README.md#configuration)
- Set up monitoring and alerting
- Configure GitHub App webhooks (optional)
- Customize Cookstyle rules for your organization
