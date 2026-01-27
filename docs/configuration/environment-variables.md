# Environment Variables

Complete reference for all environment variables supported by the GitHub Cookstyle Runner.

## Authentication

The application supports two authentication methods with GitHub. You must configure one of these methods:

### GitHub App Authentication (Recommended)

GitHub App authentication provides better security, more granular permissions, and higher rate limits. This is the recommended authentication method for production use.

#### GITHUB_APP_ID

- **Type**: String (numeric)
- **Required**: Yes (if using GitHub App authentication)
- **Description**: The GitHub App ID for authentication
- **Example**: `123456`

#### GITHUB_APP_INSTALLATION_ID

- **Type**: String (numeric)
- **Required**: Yes (if using GitHub App authentication)
- **Description**: The installation ID for the GitHub App
- **Example**: `789012`

#### GITHUB_APP_PRIVATE_KEY

- **Type**: String (PEM format)
- **Required**: Yes (if using GitHub App authentication)
- **Description**: The PEM-encoded private key for the GitHub App
- **Example**:

```bash
GITHUB_APP_PRIVATE_KEY="-----BEGIN RSA PRIVATE KEY-----
MIIEpAIBAAKCAQEA...
-----END RSA PRIVATE KEY-----"
```

!!! info "Creating a GitHub App"
    See the [GitHub App Setup Guide](https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/about-authentication-with-a-github-app) for detailed instructions on creating and configuring a GitHub App.

### Personal Access Token (PAT) Authentication

Personal Access Token authentication is simpler to set up but less secure and has lower rate limits. Use this for development or testing.

#### GITHUB_TOKEN

- **Type**: String
- **Required**: Yes (if using PAT authentication)
- **Description**: A GitHub Personal Access Token with appropriate permissions
- **Example**: `ghp_1234567890abcdefghijklmnopqrstuvwxyz`
- **Required Scopes**:
    - `repo` - Full control of private repositories
    - `read:org` - Read organization membership

!!! warning "Security Considerations"
    - Personal Access Tokens have the same permissions as the user account
    - GitHub Apps provide more granular permission control
    - Consider using GitHub Apps for production deployments

### GITHUB_API_ENDPOINT

- **Type**: String (URL)
- **Required**: No
- **Default**: `https://api.github.com`
- **Description**: The GitHub API endpoint URL (useful for GitHub Enterprise)
- **Example**: `https://github.company.com/api/v3`

## Repository Configuration

### GCR_DESTINATION_REPO_OWNER

- **Type**: String
- **Required**: Yes
- **Description**: The owner (organization or user) of the repositories to process
- **Example**: `sous-chefs`

### GCR_DESTINATION_REPO_TOPICS

- **Type**: String (comma-separated)
- **Required**: Yes
- **Description**: Topics to search for when finding repositories
- **Example**: `chef-cookbook,chef`

### GCR_FILTER_REPOS

- **Type**: String (comma-separated)
- **Required**: No
- **Description**: Specific repositories to process (overrides topic search)
- **Example**: `apt,nginx,haproxy`

## Git Configuration

### GCR_GIT_EMAIL

- **Type**: String (email)
- **Required**: Yes
- **Description**: Email address for git commits
- **Example**: `cookstyle-bot@example.com`

### GCR_GIT_NAME

- **Type**: String
- **Required**: Yes
- **Description**: Name for git commits
- **Example**: `Cookstyle Bot`

## Branch Configuration

### GCR_BRANCH_NAME

- **Type**: String
- **Required**: No
- **Default**: `automated/cookstyle`
- **Description**: Name of the branch to create for changes
- **Example**: `cookstyle-fixes`

### GCR_DEFAULT_GIT_BRANCH

- **Type**: String
- **Required**: No
- **Default**: `main`
- **Description**: Default branch name to base changes on
- **Example**: `master`

## Pull Request Configuration

### GCR_PULL_REQUEST_TITLE

- **Type**: String
- **Required**: No
- **Default**: `Automated PR: Cookstyle Changes`
- **Description**: Title for created pull requests
- **Example**: `Automated Cookstyle Fixes`

### GCR_PULL_REQUEST_LABELS

- **Type**: String (comma-separated)
- **Required**: No
- **Default**: None
- **Description**: Labels to apply to pull requests
- **Example**: `tech-debt,automated,cookstyle`

### GCR_CREATE_MANUAL_FIX_PRS

- **Type**: Boolean (`0` or `1`)
- **Required**: No
- **Default**: `0` (disabled)
- **Description**: Create PRs for issues requiring manual fixes (with detailed instructions)
- **Example**: `1`

## Cache Configuration

### GCR_USE_CACHE

- **Type**: Boolean (`0` or `1`)
- **Required**: No
- **Default**: `1` (enabled)
- **Description**: Enable/disable the caching system
- **Example**: `1`

### GCR_CACHE_MAX_AGE

- **Type**: Integer (days)
- **Required**: No
- **Default**: `7`
- **Description**: Maximum age of cache entries before they're considered stale
- **Example**: `14`

### GCR_FORCE_REFRESH

- **Type**: Boolean (`0` or `1`)
- **Required**: No
- **Default**: `0` (disabled)
- **Description**: Force refresh all repositories regardless of cache status
- **Example**: `1`

## Performance Configuration

### GCR_THREAD_COUNT

- **Type**: Integer
- **Required**: No
- **Default**: Number of CPU cores
- **Description**: Number of threads for parallel repository processing
- **Example**: `8`

### GCR_RETRY_COUNT

- **Type**: Integer
- **Required**: No
- **Default**: `3`
- **Description**: Number of retry attempts for failed operations
- **Example**: `5`

### GCR_DEBUG_MODE

- **Type**: Boolean (`0` or `1`)
- **Required**: No
- **Default**: `0` (disabled)
- **Description**: Enable verbose debug logging
- **Example**: `1`

## Environment-Specific Examples

### Development (GitHub App)

```bash
# GitHub App Authentication
GITHUB_APP_ID=123456
GITHUB_APP_INSTALLATION_ID=789012
GITHUB_APP_PRIVATE_KEY="-----BEGIN RSA PRIVATE KEY-----
...
-----END RSA PRIVATE KEY-----"

# Repository Configuration
GCR_DESTINATION_REPO_OWNER=my-org
GCR_DESTINATION_REPO_TOPICS=chef-cookbook
GCR_GIT_EMAIL=dev@example.com
GCR_GIT_NAME=Dev Bot

# Development Settings
GCR_DEBUG_MODE=1
GCR_THREAD_COUNT=2
GCR_FILTER_REPOS=test-repo
```

### Development (Personal Access Token)

```bash
# PAT Authentication
GITHUB_TOKEN=ghp_YourPersonalAccessTokenHere

# Repository Configuration
GCR_DESTINATION_REPO_OWNER=my-org
GCR_DESTINATION_REPO_TOPICS=chef-cookbook
GCR_GIT_EMAIL=dev@example.com
GCR_GIT_NAME=Dev Bot

# Development Settings
GCR_DEBUG_MODE=1
GCR_THREAD_COUNT=2
GCR_FILTER_REPOS=test-repo
```

### Staging (GitHub App)

```bash
# GitHub App Authentication
GITHUB_APP_ID=123456
GITHUB_APP_INSTALLATION_ID=789012
GITHUB_APP_PRIVATE_KEY="-----BEGIN RSA PRIVATE KEY-----
...
-----END RSA PRIVATE KEY-----"

# Repository Configuration
GCR_DESTINATION_REPO_OWNER=my-org
GCR_DESTINATION_REPO_TOPICS=chef-cookbook
GCR_GIT_EMAIL=staging-bot@example.com
GCR_GIT_NAME=Staging Cookstyle Bot

# Performance & Cache Settings
GCR_THREAD_COUNT=4
GCR_USE_CACHE=1
GCR_CACHE_MAX_AGE=3
```

### Production (GitHub App - Recommended)

```bash
# GitHub App Authentication (Recommended)
GITHUB_APP_ID=123456
GITHUB_APP_INSTALLATION_ID=789012
GITHUB_APP_PRIVATE_KEY="-----BEGIN RSA PRIVATE KEY-----
...
-----END RSA PRIVATE KEY-----"

# Repository Configuration
GCR_DESTINATION_REPO_OWNER=my-org
GCR_DESTINATION_REPO_TOPICS=chef-cookbook,chef
GCR_GIT_EMAIL=cookstyle-bot@example.com
GCR_GIT_NAME=Cookstyle Bot

# Pull Request Configuration
GCR_PULL_REQUEST_TITLE=Automated Cookstyle Fixes
GCR_PULL_REQUEST_LABELS=tech-debt,automated
GCR_CREATE_MANUAL_FIX_PRS=1

# Performance & Cache Settings
GCR_THREAD_COUNT=8
GCR_RETRY_COUNT=3
GCR_USE_CACHE=1
GCR_CACHE_MAX_AGE=7
```

## Next Steps

- [Advanced configuration options](advanced.md)
- [Configuration examples](index.md#configuration-examples)
- [Troubleshooting configuration issues](../usage/troubleshooting.md)
