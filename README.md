# Github-cookstyle-runner

This application is designed to run cookstyle against repositories found by a topic in a GitHub organization and issue pull requests with the automated fixes. It can also create issues for manual fixes that cannot be automatically applied.

## User Permissions

- It is recommended to use a GitHub bot account when using this application
- You must ensure the account has permissions to create branches and pull requests directly on the repository, it will not try to fork
- You must also supply a `GITHUB_TOKEN` to access the GitHub API server with

## Items of Note

- GitHub has a rate limiter, do not run this script continuously as you will get rate limited and then the script will fail
- The application includes a caching mechanism to reduce API calls to GitHub
- Configuration validation is performed at startup to ensure all required settings are properly configured

## Configuration

The application uses a comprehensive configuration validation system to ensure all required settings are properly configured. Below are the environment variables that can be used to configure the application:

| Name | Type | Required | Description |
|------|------|----------|-------------|
| GITHUB_TOKEN | `String` | Yes | Token to access the GitHub API with, see [Creating a token](https://help.github.com/en/github/authenticating-to-github/creating-a-personal-access-token-for-the-command-line) |
| GITHUB_API_ROOT | `String` | No | Where the API root is for GitHub, defaults to `api.github.com` (Useful for enterprise users) |
| GCR_DESTINATION_REPO_OWNER | `String` | Yes | The owner of the destination repositories you wish to update |
| GCR_DESTINATION_REPO_TOPICS | `String` | Yes | The topics that the destination repositories are tagged with to search for. Takes a CSV, e.g.: `chef-cookbook,vscode` |
| GCR_BRANCH_NAME | `String` | Yes | The name of the branch to create if changes are required |
| GCR_PULL_REQUEST_TITLE | `String` | Yes | The title to apply to the Pull Request |
| GCR_PULL_REQUEST_LABELS | `String` | No | The labels to apply to the Pull Request. Takes a CSV, e.g.: `tech-debt,automated` |
| GCR_GIT_NAME | `String` | No | The name to use when creating the git commits |
| GCR_GIT_EMAIL | `String` | No | The email address to use when creating the git commits |
| GCR_CHANGELOG_LOCATION | `String` | No | The location of the changelog to update relative to the root of the repo |
| GCR_CHANGELOG_MARKER | `String` | No | The string to use as the update point in the changelog, if not found it will be added before the next subtitle of `##` |
| GCR_MANAGE_CHANGELOG | `String` | Yes | Should we be managing the changelog, set to `0` for no, `1` for yes |
| GCR_DEFAULT_GIT_BRANCH | `String` | No | The name of the default branch, if not set this will default to `main` |
| GCR_CACHE_MAX_AGE | `Integer` | No | Maximum age of the cache in days, defaults to 7 days |

## Git Authentication

We use the `GITHUB_TOKEN` environment variable to also authenticate against git. GitHub allows this to be used instead of username and password.

## Docker Tags

This application is published to GitHub Container Registry (GHCR) with the following tags:

| Name | Description |
|------|-------------|
| latest | The latest main branch merge |
| dev  | The latest Pull Request build |
| semver (e.g.: 1.0.0) | A GitHub Release of a fixed point in time |

While all updates should result in a release, this is not always the case. Sometimes the main branch will change for non-functional related changes and a release will not be made, e.g., a new file in the `infrastructure` folder.

## Cookstyle Version

Cookstyle is baked into the image as part of Chef Workstation. The Chef Workstation version will be the latest version available at build time.

## Development

### Prerequisites

- Ruby 3.4.1 (managed via `.tool-versions`)
- Bundler

### Setup

```bash
bundle install
```

### Testing

The application includes comprehensive test coverage using RSpec:

```bash
bundle exec rspec
```

### CI/CD Pipeline

The project uses GitHub Actions for continuous integration and deployment with the following checks:

- YAML linting
- Markdown linting
- RuboCop for Ruby code quality
- RSpec tests
- Docker image building and publishing to GitHub Container Registry

### Running Locally with Docker Compose

A `docker-compose.yml` file is provided for local development and testing. To use it:

```bash
docker-compose up
```

Make sure to set the required environment variables in the docker-compose file or through a `.env` file.
