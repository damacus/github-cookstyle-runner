# Github-cookstyle-runner

This application is designed to run cookstyle against repositories found by a topic in a GitHub organization and issue pull requests with the changes. It features multi-threading, intelligent caching, and comprehensive error handling.

## Documentation

📚 **[View Full Documentation](https://damacus.github.io/github-cookstyle-runner/)**

- [Installation Guide](https://damacus.github.io/github-cookstyle-runner/installation/) - Docker Compose and Kubernetes setup
- [Configuration Reference](https://damacus.github.io/github-cookstyle-runner/configuration/) - All environment variables and options
- [Usage Guide](https://damacus.github.io/github-cookstyle-runner/usage/basic/) - How to run and use the application
- [Troubleshooting](https://damacus.github.io/github-cookstyle-runner/usage/troubleshooting/) - Common issues and solutions
- [Contributing](https://damacus.github.io/github-cookstyle-runner/development/contributing/) - Development setup and guidelines

## Quick Start

### Docker Compose

```bash
# Create docker-compose.yml (see Installation Guide for full example)
docker-compose up
```

### Kubernetes CronJob

```bash
# Apply manifests (see Installation Guide for full examples)
kubectl apply -f secrets.yaml
kubectl apply -f configmap.yaml
kubectl apply -f cronjob.yaml
```

### CLI Commands

The application provides several commands for different operations:

```bash
# Run Cookstyle on repositories
./bin/cookstyle-runner run

# List repositories that would be processed
./bin/cookstyle-runner list

# Display configuration
./bin/cookstyle-runner config

# Show cache status
./bin/cookstyle-runner status

# Display version
./bin/cookstyle-runner version

# Show help
./bin/cookstyle-runner help
```

See the [Usage Guide](https://damacus.github.io/github-cookstyle-runner/usage/basic/) for detailed command documentation.

## Installation

For detailed installation instructions including Kubernetes (CronJob) and docker-compose setups, see the [Installation Guide](https://damacus.github.io/github-cookstyle-runner/installation/).

## User Permissions

- It is recommended to use a github bot account when using this application
- You must ensure the account has permissions to create branches and pull requests directly on the repository, it will not try to fork.
- You must supply GitHub App credentials (GITHUB_APP_ID, GITHUB_APP_INSTALLATION_ID, GITHUB_APP_PRIVATE_KEY) to access the GitHub API.

## Items of Note

Github has a rate limiter, do not run this script continously you will get rate limited and then the script will fail

## Configuration

Below are a list of variables, what they mean and example values

### Core Configuration

| Name                        | Type     | Required | Description                                                                                                                                                                   |
|-----------------------------|----------|----------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| GCR_DESTINATION_REPO_OWNER  | `String` | Yes      | The owner of the destination repositories you wish to update                                                                                                                  |
| GCR_DESTINATION_REPO_TOPICS | `String` | Yes      | The topics that the destination repositories are tagged with to search for, Takes a csv, eg: `chef-cookbook,vscode`                                                           |
| GCR_GIT_EMAIL               | `String` | Yes      | The E-mail address to use when creating the git commits                                                                                                                       |
| GCR_GIT_NAME                | `String` | Yes      | The Name to use when creating the git commits                                                                                                                                 |
| GITHUB_APP_ID               | `String` | Yes      | The GitHub App ID for authentication |
| GITHUB_APP_INSTALLATION_ID  | `String` | Yes      | The installation ID for the GitHub App |
| GITHUB_APP_PRIVATE_KEY      | `String` | Yes      | The PEM-encoded private key for the GitHub App |
| GCR_BRANCH_NAME             | `String` | No       | The name of the branch to create if changes are required, defaults to `automated/cookstyle`                                                                                   |
| GCR_DEFAULT_GIT_BRANCH      | `String` | No       | The name of the default branch, if not set this will default to `main`                                                                                                        |
| GCR_PULL_REQUEST_LABELS     | `String` | No       | The labels to apply to the Pull Request, Takes a csv, eg: `tech-debt,automated`, defaults to no labels                                                                        |
| GCR_PULL_REQUEST_TITLE      | `String` | No       | The title to apply to the Pull Request, defaults to `Automated PR: Cookstyle Changes`                                                                                         |
| GITHUB_API_ROOT             | `String` | No       | Where the api root is for github, defaults to api.github.com (Useful for enterprise users)                                                                                    |

### Caching Configuration

| Name                    | Type      | Required | Description                                                                                                      |
|-------------------------|-----------|----------|------------------------------------------------------------------------------------------------------------------|
| GCR_USE_CACHE           | `Boolean` | No       | Enable/disable caching system (default: enabled, set to `0` to disable)                                          |
| GCR_CACHE_MAX_AGE       | `Integer` | No       | Maximum age of cache entries in days before they're considered stale (default: 7)                                |
| GCR_FORCE_REFRESH       | `Boolean` | No       | Force refresh of all repositories regardless of cache status (default: disabled, set to `1` to enable)           |

### Repository Filtering

| Name              | Type     | Required | Description                                                                                                      |
|-------------------|----------|----------|------------------------------------------------------------------------------------------------------------------|
| GCR_FILTER_REPOS  | `String` | No       | Comma-separated list of specific repositories to process (will only process these repos)                         |

### Performance Configuration

| Name              | Type      | Required | Description                                                                                                      |
|-------------------|-----------|----------|------------------------------------------------------------------------------------------------------------------|
| GCR_THREAD_COUNT  | `Integer` | No       | Number of threads to use for parallel processing (default: number of CPU cores)                                  |
| GCR_RETRY_COUNT   | `Integer` | No       | Number of retry attempts for repository processing before giving up (default: 3)                                 |
| GCR_DEBUG_MODE    | `Boolean` | No       | Enable verbose debug logging (default: disabled, set to `1` to enable)                                           |

### Logging Configuration

| Name                     | Type     | Required | Description                                                                  |
|--------------------------|----------|----------|------------------------------------------------------------------------------|
| GCR_LOG_LEVEL            | `String` | No       | Log level: DEBUG, INFO, WARN, ERROR, FATAL (default: INFO)                   |
| GCR_LOG_FORMAT           | `String` | No       | Log format: text or json (default: text)                                     |
| GCR_LOG_DEBUG_COMPONENTS | `String` | No       | Comma-separated list of components for debug logging (e.g., `git,cache,api`) |

For detailed logging configuration, see [Logging Documentation](docs/logging.md).

### Pull Request Configuration

| Name                          | Type      | Required | Description                                                                                                      |
|-------------------------------|-----------|----------|------------------------------------------------------------------------------------------------------------------|
| GCR_CREATE_MANUAL_FIX_ISSUES  | `Boolean` | No       | Create issues for violations that require manual fixes (default: enabled, set to `0` to disable)                |
| GCR_AUTO_ASSIGN_MANUAL_FIXES  | `Boolean` | No       | Automatically assign manual fix issues to a Copilot agent (default: enabled, set to `0` to disable)            |
| GCR_COPILOT_ASSIGNEE          | `String`  | No       | GitHub username to assign manual fix issues to (default: `copilot`)                                            |

## Git Authentication

We use the `GITHUB_APP_ID`, `GITHUB_APP_INSTALLATION_ID` and `GITHUB_APP_PRIVATE_KEY` environment variables to authenticate against git, github allows this to be used instead of username and password

## Docker Tags

This application is tagged as follows

| Name | Description |
|------|-------------|
| latest | The latest master merge |
| dev  | The latest Pull Request build |
| semvar (eg: 1.0.0) | A Github Release of a fixed point in time |

While all updates should result in a release this is not always the case, sometimes master will change for non-functional related changes and a release will not be made, eg a new file in the `infrastructure` folder

## Cookstyle version

Cookstyle will be baked into the image, it is baked into the image as part of chef workstation, the chef workstation version will be the latest version available at runtime.

## Features

### Intelligent Caching

The application implements a robust caching system that tracks:

- Repository state via commit SHAs
- Time-based cache expiration (configurable)
- Detailed result caching
- Performance statistics

This significantly improves performance for repeated runs by only processing repositories that have changed since the last run.

### Multi-threaded Processing

Repositories are processed in parallel using a configurable thread pool, dramatically improving performance for large repository sets.

### Advanced Repository Filtering

The application supports flexible repository filtering options:

- Process only specific repositories
- Include additional repositories outside of topic search
- Exclude specific repositories from processing

### Comprehensive Error Handling

- Automatic retry mechanism for transient failures
- Process-level isolation to prevent cross-repository conflicts
- Detailed logging for troubleshooting

### Pull Request Management

- Automatic branch creation and management
- Detailed PR descriptions with cookstyle output
- Label support
- Support for manual fix PRs with detailed instructions

### CLI Output Formats

- **Text**: Simple text-based list (default for `list` command)
- **Table**: Formatted output with structure (default for `status` command)
- **JSON**: Machine-readable output for scripting

```bash
# View repositories in table format
./bin/cookstyle-runner list --format table

# View cache status in JSON format
./bin/cookstyle-runner status --format json
```

## Usage Examples

### Basic Usage

```bash
docker run --rm \
  -e GITHUB_APP_ID="your-github-app-id" \
  -e GITHUB_APP_INSTALLATION_ID="your-installation-id" \
  -e GITHUB_APP_PRIVATE_KEY="$(cat /path/to/private-key.pem)" \
  -v /tmp/cookstyle-runner:/tmp/cookstyle-runner \
  cookstyle-runner:latest
```

### Process Specific Repositories

```bash
docker run --rm \
  -e GITHUB_APP_ID="your-github-app-id" \
  -e GITHUB_APP_INSTALLATION_ID="your-installation-id" \
  -e GITHUB_APP_PRIVATE_KEY="$(cat /path/to/private-key.pem)" \
  -e GCR_FILTER_REPOS="repo1,repo2,repo3" \
  -v /tmp/cookstyle-runner:/tmp/cookstyle-runner \
  cookstyle-runner:latest
```

### Force Refresh All Repositories

```bash
docker run --rm \
  -e GITHUB_APP_ID="your-github-app-id" \
  -e GITHUB_APP_INSTALLATION_ID="your-installation-id" \
  -e GITHUB_APP_PRIVATE_KEY="$(cat /path/to/private-key.pem)" \
  -e GCR_FORCE_REFRESH=1 \
  -v /tmp/cookstyle-runner:/tmp/cookstyle-runner \
  cookstyle-runner:latest
```
