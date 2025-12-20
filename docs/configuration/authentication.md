# Authentication

The GitHub Cookstyle Runner supports two methods for authenticating with GitHub: GitHub App authentication and Personal Access Token (PAT) authentication.

## Overview

| Method | Security | Rate Limit | Setup Complexity | Recommended For |
|--------|----------|------------|------------------|-----------------|
| GitHub App | ⭐⭐⭐⭐⭐ | 5,000/hour | Medium | Production, Organizations |
| Personal Access Token (PAT) | ⭐⭐⭐ | 5,000/hour | Low | Development, Testing |

## GitHub App Authentication (Recommended)

GitHub App authentication is the recommended method for production deployments because it provides:

- **Better Security**: Apps have scoped permissions and can be restricted to specific repositories
- **Audit Trail**: All actions are attributed to the app, not a user account
- **Independence**: Not tied to a specific user account
- **Granular Permissions**: Fine-grained control over what the app can access

### Prerequisites

1. Organization admin access to create a GitHub App
2. Ability to install the app on your organization/repositories

### Setup Steps

#### 1. Create a GitHub App

1. Navigate to your organization settings: `https://github.com/organizations/YOUR_ORG/settings/apps`
2. Click **"New GitHub App"**
3. Fill in the required information:
   - **Name**: `Cookstyle Runner` (or your preferred name)
   - **Homepage URL**: Your organization's homepage or repository URL
   - **Webhook**: Uncheck "Active" (not needed for this application)

#### 2. Configure Permissions

Set the following repository permissions:

- **Contents**: Read & Write (to clone repos and create branches)
- **Pull Requests**: Read & Write (to create PRs)
- **Issues**: Read & Write (to create issues for manual fixes)
- **Metadata**: Read (to access repository information)

Set the following organization permissions:

- **Members**: Read (to search for repositories by topic)

#### 3. Generate a Private Key

1. Scroll to the bottom of the app settings page
2. Click **"Generate a private key"**
3. Save the downloaded `.pem` file securely

#### 4. Install the App

1. Go to the "Install App" tab in your app settings
2. Click **"Install"** next to your organization
3. Choose **"All repositories"** or select specific repositories
4. Note the Installation ID from the URL: `https://github.com/organizations/YOUR_ORG/settings/installations/INSTALLATION_ID`

#### 5. Configure Environment Variables

Set the following environment variables:

```bash
# From the app settings page (General tab)
GITHUB_APP_ID=123456

# From the installation URL
GITHUB_APP_INSTALLATION_ID=789012

# Contents of the downloaded .pem file
GITHUB_APP_PRIVATE_KEY="-----BEGIN RSA PRIVATE KEY-----
MIIEpAIBAAKCAQEA1234567890abcdef...
-----END RSA PRIVATE KEY-----"
```

!!! tip "Multi-line Private Key"
    When setting the private key as an environment variable, you can:

    - **In `.env` file**: Include the entire key with line breaks
    - **In shell**: Use quotes and literal line breaks
    - **In Kubernetes Secret**: Use a multiline YAML literal block (`|`)
    - **From file**: Use command substitution: `GITHUB_APP_PRIVATE_KEY="$(cat private-key.pem)"`

### Verification

Test your GitHub App authentication:

```bash
./bin/cookstyle-runner config
```

You should see output confirming your GitHub App ID and installation ID.

## Personal Access Token (PAT) Authentication

Personal Access Token authentication is simpler to set up but less secure. Use this for:

- Local development and testing
- Quick prototyping
- Environments where GitHub Apps are not available

### Prerequisites

1. GitHub user account with appropriate permissions
2. Access to create personal access tokens

### Setup Steps

#### 1. Create a Personal Access Token

1. Navigate to: `https://github.com/settings/tokens`
2. Click **"Generate new token"** → **"Generate new token (classic)"**
3. Give your token a descriptive name: `Cookstyle Runner - Dev`
4. Set expiration (recommended: 90 days or less)
5. Select the following scopes:
   - `repo` - Full control of private repositories
   - `read:org` - Read organization membership (if processing org repos)

#### 2. Save the Token

Copy the generated token immediately - you won't be able to see it again.

#### 3. Configure Environment Variable

Set the `GITHUB_TOKEN` environment variable:

```bash
GITHUB_TOKEN=ghp_1234567890abcdefghijklmnopqrstuvwxyz
```

### Verification

Test your PAT authentication:

```bash
./bin/cookstyle-runner config
```

You should see output confirming your authentication is working.

!!! warning "Security Considerations"
    - Personal Access Tokens have the same permissions as your user account
    - Tokens should be treated like passwords and never committed to version control
    - Use GitHub Apps for production deployments where possible
    - Rotate tokens regularly

## Authentication Fallback

The application automatically detects which authentication method to use based on the environment variables present:

1. **GitHub App** - If `GITHUB_APP_ID`, `GITHUB_APP_INSTALLATION_ID`, and `GITHUB_APP_PRIVATE_KEY` are all set
2. **PAT** - If `GITHUB_TOKEN` is set
3. **Error** - If neither authentication method is configured

You cannot use both methods simultaneously. If both are configured, GitHub App authentication takes precedence.

## GitHub Enterprise

Both authentication methods work with GitHub Enterprise Server. Set the `GITHUB_API_ENDPOINT` environment variable:

```bash
# For GitHub Enterprise
GITHUB_API_ENDPOINT=https://github.company.com/api/v3

# For GitHub.com (default, no need to set)
GITHUB_API_ENDPOINT=https://api.github.com
```

## Troubleshooting

### GitHub App Authentication Issues

#### Error: "Invalid GitHub App credentials"

- Verify your `GITHUB_APP_ID` is correct (numeric value)
- Check that `GITHUB_APP_INSTALLATION_ID` matches your installation
- Ensure the private key is complete with headers and footers
- Confirm the app is installed on your organization

#### Error: "Resource not accessible by integration"

- Review the app permissions - it may need additional scopes
- Verify the app is installed on the repositories you're trying to access
- Check that the installation is active (not suspended)

#### Error: "401 Unauthorized"

- The private key may be incorrect or corrupted
- The app may have been uninstalled
- The installation ID may be wrong

### PAT Authentication Issues

#### Error: "Bad credentials"

- Verify the token hasn't expired
- Check that the token is correctly copied (no extra spaces)
- Ensure the token has the required scopes (`repo`, `read:org`)

#### Error: "Resource not accessible"

- The token's user account may not have access to the repositories
- The required scopes may not be selected
- The organization may require SSO authorization for the token

### Common Issues

#### Rate Limiting

Both methods have the same rate limit (5,000 requests/hour), but GitHub Apps can request rate limit increases more easily. If you hit rate limits:

- Enable caching (`GCR_USE_CACHE=1`)
- Reduce the number of repositories processed
- Use `GCR_FILTER_REPOS` to process specific repositories
- Consider spreading runs over time

## Best Practices

### For Production

1. **Use GitHub Apps** - Better security and audit trail
2. **Rotate keys regularly** - Generate new private keys periodically
3. **Monitor usage** - Track API rate limit usage
4. **Limit permissions** - Only grant necessary permissions
5. **Use organization-level apps** - Better than user-level

### For Development

1. **Use PAT for convenience** - Easier to set up for local testing
2. **Set token expiration** - Use short-lived tokens (90 days or less)
3. **Never commit tokens** - Use `.env` files (added to `.gitignore`)
4. **Use test repositories** - Don't test on production repos

### Security

1. **Never log secrets** - The application never logs tokens or keys
2. **Use environment variables** - Don't hard-code credentials
3. **Secure storage** - Use secret management tools (Kubernetes Secrets, AWS Secrets Manager, etc.)
4. **Least privilege** - Grant only the minimum required permissions
5. **Audit regularly** - Review app installations and token usage

## Next Steps

- [Configure other environment variables](environment-variables.md)
- [Set up repository filtering](index.md#repository-filtering)
- [Run your first scan](../usage/basic.md)
