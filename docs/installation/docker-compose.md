# Docker Compose Installation

Docker Compose is ideal for local development, testing, or running on a single host.

## Setup

### 1. Create docker-compose.yml

Create a `docker-compose.yml` file in your working directory:

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

### 2. Create .env File

For security, store sensitive credentials in a `.env` file:

```bash
# .env
GITHUB_APP_ID=123456
GITHUB_APP_INSTALLATION_ID=789012
GITHUB_APP_PRIVATE_KEY="-----BEGIN RSA PRIVATE KEY-----
MIIEpAIBAAKCAQEA...
-----END RSA PRIVATE KEY-----"
```

!!! warning "Security"
    Add `.env` to your `.gitignore` to prevent committing secrets to version control.

### 3. Run the Application

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

## Scheduled Runs

For scheduled runs, use a cron job on the host:

```bash
# Edit crontab
crontab -e

# Add entry to run daily at 2 AM
0 2 * * * cd /path/to/cookstyle-runner && docker-compose up
```

## Monitoring

### View Logs

```bash
# View logs
docker-compose logs -f cookstyle-runner

# View last 100 lines
docker-compose logs --tail=100 cookstyle-runner
```

### Check Container Status

```bash
# Check container status
docker-compose ps

# Access container shell
docker-compose exec cookstyle-runner /bin/bash
```

## Troubleshooting

### Container Won't Start

Check logs for errors:

```bash
docker-compose logs cookstyle-runner
```

Common issues:

- Missing required environment variables
- Invalid GitHub App credentials
- Network connectivity issues

### Cache Issues

Clear the cache volume:

```bash
# Stop containers
docker-compose down

# Remove volumes
docker-compose down -v

# Restart
docker-compose up
```

## Upgrading

Pull the latest image and restart:

```bash
# Pull latest image
docker-compose pull

# Restart with new image
docker-compose up -d
```

## Uninstallation

```bash
# Stop and remove containers
docker-compose down

# Remove volumes (including cache)
docker-compose down -v

# Remove images
docker rmi ghcr.io/damacus/github-cookstyle-runner:latest
```

## Next Steps

- [Configure the application](../configuration/index.md)
- [Learn about usage](../usage/basic.md)
- [Troubleshooting guide](../usage/troubleshooting.md)
