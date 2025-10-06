# Installation Overview

The GitHub Cookstyle Runner can be deployed in multiple ways depending on your infrastructure and requirements.

## Prerequisites

Before installing, ensure you have:

### 1. GitHub App Credentials

You'll need to create a GitHub App with the following:

- **GitHub App ID**: The numeric ID of your GitHub App
- **Installation ID**: The installation ID for your organization
- **Private Key**: A PEM-encoded private key for authentication

!!! info "Creating a GitHub App"
    See the [GitHub App Setup Guide](https://docs.github.com/en/apps/creating-github-apps) for detailed instructions on creating a GitHub App.

### 2. Required Permissions

Your GitHub App must have the following permissions:

- **Repository permissions**:
    - Contents: Read & Write (to clone repos and create branches)
    - Pull Requests: Read & Write (to create PRs)
    - Issues: Read & Write (to create issues for manual fixes)
    - Metadata: Read (to access repository information)

- **Organization permissions**:
    - Members: Read (to search for repositories)

### 3. Environment Requirements

Choose your deployment method:

=== "Docker Compose"
    - Docker Engine 20.10+
    - Docker Compose 2.0+

=== "Kubernetes"
    - Kubernetes 1.19+
    - kubectl configured
    - Persistent storage support

=== "Local Development"
    - Ruby 3.4+
    - Git
    - Bundler

## Installation Methods

### Docker Compose

Best for: Local development, testing, single-host deployments

[Docker Compose Installation Guide →](docker-compose.md)

### Kubernetes

Best for: Production deployments, scheduled runs, high availability

[Kubernetes Installation Guide →](kubernetes.md)

### Local Development

Best for: Contributing to the project, debugging

```bash
# Clone the repository
git clone https://github.com/damacus/github-cookstyle-runner.git
cd github-cookstyle-runner

# Install dependencies
bundle install

# Configure (copy and edit)
cp config/settings/local.yml.example config/settings/local.yml

# Run
./bin/cookstyle-runner
```

## Docker Images

Images are published to GitHub Container Registry:

| Tag | Description | Use Case |
|-----|-------------|----------|
| `latest` | Latest main branch | Production |
| `v1.0.0` | Specific version | Pinned deployments |
| `dev` | Latest PR build | Testing |

Pull the image:

```bash
docker pull ghcr.io/damacus/github-cookstyle-runner:latest
```

## Next Steps

1. Choose your installation method above
2. Follow the detailed installation guide
3. [Configure the application](../configuration/index.md)
4. [Run your first scan](../usage/basic.md)
