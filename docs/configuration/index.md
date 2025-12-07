# Configuration Overview

The GitHub Cookstyle Runner is configured primarily through environment variables, making it easy to deploy across different environments.

## Configuration Methods

### Environment Variables

The primary configuration method. Set environment variables in your deployment:

- Docker Compose: Use `.env` files or `environment` section
- Kubernetes: Use ConfigMaps and Secrets
- Local: Export in your shell or use `.envrc`

### Configuration File (Optional)

For local development, you can use `config/settings/local.yml`:

```yaml
github:
  app_id: "123456"
  app_installation_id: "789012"
  app_private_key: "-----BEGIN RSA PRIVATE KEY-----\n..."

destination:
  repo_owner: "your-org"
  repo_topics: ["chef-cookbook"]

git:
  email: "bot@example.com"
  name: "Cookstyle Bot"
```

## Configuration Categories

### Required Settings

These must be configured for the application to run:

- [Authentication](authentication.md) - GitHub App or Personal Access Token
- [Repository Configuration](environment-variables.md#repository-configuration)
- [Git Configuration](environment-variables.md#git-configuration)

### Optional Settings

Customize behavior with these optional settings:

- [Branch Configuration](environment-variables.md#branch-configuration)
- [Pull Request Configuration](environment-variables.md#pull-request-configuration)
- [Cache Configuration](environment-variables.md#cache-configuration)
- [Performance Configuration](environment-variables.md#performance-configuration)
- [Repository Filtering](environment-variables.md#repository-filtering)

## Quick Reference

| Category       | Variables                             | Purpose                                          |
|----------------|---------------------------------------|--------------------------------------------------|
| Authentication | `GITHUB_APP_*` or `GITHUB_TOKEN`      | GitHub API access ([details](authentication.md)) |
| Repository     | `GCR_DESTINATION_REPO_*`              | Target repositories                              |
| Git            | `GCR_GIT_*`                           | Commit author info                               |
| Pull Requests  | `GCR_PULL_REQUEST_*`                  | PR customization                                 |
| Cache          | `GCR_CACHE_*`, `GCR_USE_CACHE`        | Performance optimization                         |
| Performance    | `GCR_THREAD_COUNT`, `GCR_RETRY_COUNT` | Execution tuning                                 |
| Filtering      | `GCR_FILTER_REPOS`                    | Repository selection                             |

## Configuration Examples

### Minimal Configuration (GitHub App)

```bash
# GitHub App Authentication (Recommended)
GITHUB_APP_ID=123456
GITHUB_APP_INSTALLATION_ID=789012
GITHUB_APP_PRIVATE_KEY="-----BEGIN RSA PRIVATE KEY-----..."

# Repository Configuration
GCR_DESTINATION_REPO_OWNER=my-org
GCR_DESTINATION_REPO_TOPICS=chef-cookbook

# Git Configuration
GCR_GIT_EMAIL=bot@example.com
GCR_GIT_NAME=Cookstyle Bot
```

### Minimal Configuration (PAT)

```bash
# Personal Access Token Authentication
GITHUB_TOKEN=ghp_YourPersonalAccessTokenHere

# Repository Configuration
GCR_DESTINATION_REPO_OWNER=my-org
GCR_DESTINATION_REPO_TOPICS=chef-cookbook

# Git Configuration
GCR_GIT_EMAIL=bot@example.com
GCR_GIT_NAME=Cookstyle Bot
```

### Production Configuration

```bash
# Authentication (GitHub App - Recommended)
GITHUB_APP_ID=123456
GITHUB_APP_INSTALLATION_ID=789012
GITHUB_APP_PRIVATE_KEY="-----BEGIN RSA PRIVATE KEY-----..."

# Repository
GCR_DESTINATION_REPO_OWNER=my-org
GCR_DESTINATION_REPO_TOPICS=chef-cookbook,chef

# Git
GCR_GIT_EMAIL=cookstyle-bot@example.com
GCR_GIT_NAME=Cookstyle Bot

# Pull Requests
GCR_PULL_REQUEST_TITLE=Automated Cookstyle Fixes
GCR_PULL_REQUEST_LABELS=tech-debt,automated,cookstyle
GCR_CREATE_MANUAL_FIX_PRS=1

# Performance
GCR_THREAD_COUNT=8
GCR_RETRY_COUNT=3
GCR_USE_CACHE=1
GCR_CACHE_MAX_AGE=7
```

## Validation

The application validates configuration on startup and will exit with clear error messages if:

- Required variables are missing
- Values are invalid (e.g., non-numeric for numeric fields)
- Conflicting options are set

## Next Steps

- [View all environment variables](environment-variables.md)
- [Learn about advanced configuration](advanced.md)
- [See usage examples](../usage/basic.md)
