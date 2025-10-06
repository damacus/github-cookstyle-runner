# GitHub Cookstyle Runner

Welcome to the GitHub Cookstyle Runner documentation!

## Overview

The GitHub Cookstyle Runner is an automated tool designed to run [Cookstyle](https://docs.chef.io/workstation/cookstyle/) (a RuboCop-based linter for Chef) against repositories in a GitHub organization and automatically create pull requests with fixes.

## Key Features

- **Automated Linting**: Automatically runs Cookstyle on Chef cookbooks
- **Pull Request Creation**: Creates PRs with auto-correctable fixes
- **Issue Creation**: Creates issues for manual fixes with detailed instructions
- **Intelligent Caching**: Tracks repository state to avoid redundant processing
- **Multi-threaded Processing**: Processes multiple repositories in parallel
- **Flexible Filtering**: Process specific repositories or exclude certain ones
- **GitHub App Authentication**: Secure authentication using GitHub Apps

## Quick Start

Get started quickly with Docker Compose:

```bash
# Create docker-compose.yml
cat > docker-compose.yml <<EOF
services:
  cookstyle-runner:
    image: ghcr.io/damacus/github-cookstyle-runner:latest
    environment:
      - GITHUB_APP_ID=\${GITHUB_APP_ID}
      - GITHUB_APP_INSTALLATION_ID=\${GITHUB_APP_INSTALLATION_ID}
      - GITHUB_APP_PRIVATE_KEY=\${GITHUB_APP_PRIVATE_KEY}
      - GCR_DESTINATION_REPO_OWNER=your-org
      - GCR_DESTINATION_REPO_TOPICS=chef-cookbook
      - GCR_GIT_EMAIL=bot@example.com
      - GCR_GIT_NAME=Cookstyle Bot
    volumes:
      - cookstyle_cache:/app/.cache
volumes:
  cookstyle_cache:
EOF

# Run
docker-compose up
```

For detailed installation instructions, see the [Installation Guide](installation/index.md).

## Use Cases

### Continuous Compliance

Run the Cookstyle Runner on a schedule (e.g., daily via Kubernetes CronJob) to ensure all your Chef cookbooks stay compliant with style guidelines.

### Migration Assistance

Use the runner to help migrate large numbers of cookbooks to new Cookstyle rules or Chef versions by automatically fixing what can be fixed and creating issues for manual review.

### Code Review Automation

Integrate into your CI/CD pipeline to automatically check and fix style issues before code review.

## Architecture

The application is built with:

- **Ruby 3.4**: Modern Ruby with type checking via Sorbet
- **GitHub API**: Uses GitHub Apps for secure authentication
- **Docker**: Containerized for easy deployment
- **Multi-threading**: Concurrent processing for performance

## Getting Help

- **Installation Issues**: See [Troubleshooting](usage/troubleshooting.md)
- **Configuration Questions**: Check [Configuration Guide](configuration/index.md)
- **Bug Reports**: [Open an issue](https://github.com/damacus/github-cookstyle-runner/issues)
- **Feature Requests**: [Start a discussion](https://github.com/damacus/github-cookstyle-runner/discussions)

## Next Steps

- [Install the application](installation/index.md)
- [Configure for your organization](configuration/index.md)
- [Learn about advanced features](usage/advanced.md)
