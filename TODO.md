# TODO: Switch to GitHub App Authentication

## Current Status (as of 2025-04-16)

- **Significant refactoring completed.**
  - The codebase is now much more maintainable, testable, and ready for the GitHub App authentication migration.
  - All major architectural and code quality groundwork is complete.

## Overview

Switch the authentication and API access in the GitHub Cookstyle Runner to use GitHub App authentication instead of a personal access token (PAT) or legacy OAuth. GitHub Apps provide more granular permissions, better rate limits, and are the recommended authentication method for GitHub integrations.

---

## Phase 1: GitHub App Creation

### 1.1. Register a GitHub App

1. Go to your GitHub organization settings → Developer settings → GitHub Apps → New GitHub App
2. Configure the following settings:
   - App name: `Cookstyle Runner`
   - Homepage URL: Your project's GitHub repository URL
   - Webhook URL: Leave blank for now (unless you're handling webhooks)
   - Webhook secret: Generate and save a secure random string if using webhooks
   - Permissions: Based on analysis from Phase 0.2
     - Repository permissions:
       - Contents: Read & Write
       - Metadata: Read
       - Pull requests: Read & Write
     - Organization permissions:
       - Members: Read (if needed)
   - Where can this GitHub App be installed: Select either "Only on this account" or "Any account"
3. Submit the form to create the app

### 1.2. Generate and Store Private Key

1. On the app settings page, scroll to "Private keys" section
2. Click "Generate a private key"
3. Download and securely store the .pem file
4. Note the App ID displayed at the top of the page

### 1.3. Install the App

1. On the app settings page, go to "Install App" tab
2. Click "Install" next to your organization/account
3. Select repositories to provide access to
4. After installation, note the Installation ID from the URL: `https://github.com/settings/installations/{installation_id}`

---

## Phase 2: Update Application Configuration

### 2.1. Add Required Gems

```ruby
# In Gemfile
gem 'jwt', '~> 2.7'  # For creating JWT tokens
```

Then run:

```bash
bundle install
```

### 2.2. Update Configuration Format

Update `config.yml` (or equivalent configuration file):

```yaml
# Before
github:
  access_token: "your-personal-access-token"

# After
github:
  # Legacy token (kept temporarily during migration)
  access_token: "your-personal-access-token"

  # GitHub App authentication (new)
  app:
    enabled: true  # Set to false to use PAT during testing/migration
    app_id: "123456"  # Your GitHub App ID
    installation_id: "12345678"  # Your installation ID
    private_key_path: "/path/to/private-key.pem"  # Path to the private key file
    # Alternative: provide the key directly (in secure contexts only)
    # private_key: |
    #   -----BEGIN RSA PRIVATE KEY-----
    #   MIIEpAIBAAKCAQEA...
    #   -----END RSA PRIVATE KEY-----
```

### 2.3. Add Environment Variables for CI/CD

For CI/CD environments, set up these environment variables:

- `GITHUB_APP_ID`: Your GitHub App ID
- `GITHUB_APP_INSTALLATION_ID`: Your installation ID
- `GITHUB_APP_PRIVATE_KEY`: The contents of your private key (with newlines represented as `\n`)

---

## Phase 3: Implement GitHub App Authentication

### 3.1. Create GitHub App Authentication Module

Create file `app/github_app_auth.rb`:

```ruby
require 'jwt'
require 'net/http'
require 'json'
require 'time'
require 'logger'

class CookstyleRunner::Authentication
  TOKEN_ENDPOINT = 'https://api.github.com/app/installations/%s/access_tokens'
  TOKEN_TTL = 3600 # 1 hour in seconds

  attr_reader :app_id, :installation_id, :private_key, :logger

  def initialize(app_id:, installation_id:, private_key:, logger: nil)
    @app_id = app_id
    @installation_id = installation_id
    @private_key = private_key.is_a?(String) ? OpenSSL::PKey::RSA.new(private_key) : private_key
    @logger = logger || Logger.new($stdout)
    @token_expires_at = Time.at(0)
    @token = nil
  end

  def token
    if @token.nil? || Time.now >= @token_expires_at
      refresh_token
    end
    @token
  end

  private

  def refresh_token
    jwt_token = generate_jwt
    endpoint = format(TOKEN_ENDPOINT, installation_id)

    uri = URI(endpoint)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    request = Net::HTTP::Post.new(uri)
    request['Accept'] = 'application/vnd.github.v3+json'
    request['Authorization'] = "Bearer #{jwt_token}"

    response = http.request(request)

    if response.code.to_i == 201
      data = JSON.parse(response.body)
      @token = data['token']
      @token_expires_at = Time.parse(data['expires_at']) - 300 # 5 minutes buffer
      logger.info("GitHub App token refreshed, expires at #{@token_expires_at}")
    else
      logger.error("Failed to get GitHub App token: #{response.code} #{response.body}")
      raise "Failed to get GitHub App installation token: #{response.code} #{response.body}"
    end
  end

  def generate_jwt
    now = Time.now.to_i
    payload = {
      # Issued at time
      iat: now,
      # JWT expiration time (10 minutes max)
      exp: now + 600,
      # GitHub App identifier
      iss: app_id
    }

    JWT.encode(payload, private_key, 'RS256')
  end

  # Helper to load a private key from a file path
  def self.load_private_key_from_file(path)
    OpenSSL::PKey::RSA.new(File.read(path))
  end
end
```

### 3.2. Create GitHub Client Factory

Create file `app/github_client_factory.rb`:

```ruby
require 'octokit'
require_relative 'github_app_auth'

class GitHubClientFactory
  def self.create_client(config, logger = nil)
    if config[:github][:app][:enabled]
      create_app_client(config, logger)
    else
      create_pat_client(config, logger)
    end
  end

  private

  def self.create_app_client(config, logger)
    app_config = config[:github][:app]

    # Get private key either from path or direct config
    private_key = if app_config[:private_key]
                    app_config[:private_key]
                  elsif app_config[:private_key_path]
                    File.read(app_config[:private_key_path])
                  else
                    raise "GitHub App private key not provided"
                  end

    # Create auth instance
    auth = CookstyleRunner::Authentication.new(
      app_id: app_config[:app_id],
      installation_id: app_config[:installation_id],
      private_key: private_key,
      logger: logger
    )

    # Create a client with a proc that provides a fresh token each time
    Octokit::Client.new(access_token: -> { auth.token })
  end

  def self.create_pat_client(config, logger)
    Octokit::Client.new(access_token: config[:github][:access_token])
  end
end
```

---

## Phase 4: Refactor Existing Code

### 4.1. Update PR Manager

Refactor `pr_manager.rb` to use the new client factory:

```ruby
require_relative 'github_client_factory'

class PRManager
  def initialize(config, logger = nil)
    @config = config
    @logger = logger || Logger.new($stdout)
    @client = GitHubClientFactory.create_client(config, logger)
  end

  # Rest of your PR manager code using @client
  # ...
end
```

### 4.2. Update Other GitHub API Interactions

Audit and update any other files that directly use GitHub API:

- Find any direct Octokit client creation
- Replace with GitHubClientFactory
- Ensure all token access is through the factory

### 4.3. Handling Token Expiration

Update any long-running processes to handle token expiration:

```ruby
def perform_github_operation
  retries = 0
  begin
    # Your GitHub API calls here
    @client.create_pull_request(...)
  rescue Octokit::Unauthorized
    if retries < 1 # Only retry once
      retries += 1
      # Re-initialize client to force token refresh
      @client = GitHubClientFactory.create_client(@config, @logger)
      retry
    else
      raise
    end
  end
end
```

---

## Phase 5: Testing

### 5.1. Create Unit Tests

Create tests for the new authentication module:

```ruby
require 'minitest/autorun'
require 'webmock/minitest'
require_relative '../app/github_app_auth'

class CookstyleRunner::AuthenticationTest < Minitest::Test
  def setup
    # Generate a test private key
    @private_key = OpenSSL::PKey::RSA.generate(2048)
    @app_id = '12345'
    @installation_id = '67890'
    @auth = CookstyleRunner::Authentication.new(
      app_id: @app_id,
      installation_id: @installation_id,
      private_key: @private_key.to_s
    )

    # Set up WebMock for the token endpoint
    stub_request(:post, "https://api.github.com/app/installations/67890/access_tokens")
      .to_return(
        status: 201,
        headers: { 'Content-Type' => 'application/json' },
        body: JSON.dump({
          token: 'ghs_test_token',
          expires_at: (Time.now + 3600).iso8601
        })
      )
  end

  def test_token_generation
    token = @auth.token
    assert_equal 'ghs_test_token', token
  end

  # Add more tests for error cases, expiration, etc.
end
```

### 5.2. Manual Testing

Perform manual testing with both authentication methods:

1. Set `app.enabled: false` and test with PAT authentication
2. Set `app.enabled: true` and test with GitHub App authentication
3. Verify all functionality works the same with both methods

### 5.3. Integration Testing

Create integration tests that run against real GitHub repositories:

```ruby
require 'minitest/autorun'
require_relative '../app/cookstyle_runner'

class GitHubAppIntegrationTest < Minitest::Test
  def setup
    # Load test configuration with GitHub App credentials
    @config = YAML.load_file('test/fixtures/test_config.yml')
    @runner = CookstyleRunner.new(@config)
  end

  def test_repository_processing
    result = @runner.process_repository('org/test-repo')
    assert result[:status] == :success
    # More assertions based on expected behavior
  end

  # Additional integration tests
end
```

---

## Phase 6: Migration Strategy

### 6.1. Implement Feature Flag

Use the `app.enabled` configuration as a feature flag to toggle between PAT and GitHub App auth:

```yaml
github:
  app:
    enabled: false  # Start with this false in production
```

### 6.2. Phased Rollout Plan

1. **Development Testing**: Enable App auth in development environments only
2. **Staging Deployment**: Deploy to staging with App auth enabled
3. **Production Parallel Run**: Deploy to production with App auth disabled, but log what would happen if enabled
4. **Production Limited Rollout**: Enable for a subset of repositories
5. **Production Full Rollout**: Enable for all repositories

### 6.3. Rollback Plan

In case of issues:

1. Set `app.enabled: false` to immediately revert to PAT authentication
2. Document any necessary code rollbacks if structural changes were made
3. Have a communication plan for users/maintainers if service disruption occurs

---

## Phase 7: Documentation Updates

### 7.1. Update README.md

Add a new section on GitHub App authentication:

```markdown
## GitHub App Authentication

This application uses GitHub App authentication for interacting with the GitHub API.

### Setup Instructions

1. Register a new GitHub App (see detailed instructions in GITHUB_APP_SETUP.md)
2. Generate a private key for the app
3. Install the app to your organization/account
4. Update the configuration with your App ID, Installation ID, and private key

### Configuration

Add the following to your `config.yml`:

```yaml
github:
  app:
    enabled: true
    app_id: "your-app-id"
    installation_id: "your-installation-id"
    private_key_path: "/path/to/private-key.pem"
```

### 7.2. Create GITHUB_APP_SETUP.md

Create a detailed guide for setting up the GitHub App with screenshots and step-by-step instructions.

### 7.3. Update Troubleshooting Guide

Add a section on common GitHub App authentication issues and their solutions.

---

## Phase 8: Cleanup

### 8.1. Remove Legacy Code

After successful migration and testing:

1. Remove PAT authentication code paths
2. Update configuration examples to only show GitHub App authentication
3. Remove any temporary logging or feature flags

### 8.2. Security Audit

1. Review the application for any hardcoded or leaked credentials
2. Verify private key handling follows security best practices
3. Ensure no sensitive information is being logged

---

## Stretch Goals

### Multi-Tenant Support

- Extend CookstyleRunner::Authentication to support multiple installations
- Create a database model to store installation IDs per organization
- Add UI for users to install the GitHub App to their own organizations

### Enhanced Logging and Metrics

- Add instrumentation to track token refreshes and API calls
- Set up alerting for authentication failures
- Create a dashboard for monitoring GitHub API usage and rate limits

### Advanced Security

- Implement key rotation procedures
- Use a secrets manager (e.g., HashiCorp Vault) for storing private keys
- Add audit logging for all GitHub operations

---

## References

- [GitHub Docs: Authenticating as a GitHub App](https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app)
- [Octokit.rb GitHub App Auth Guide](https://github.com/octokit/octokit.rb#github-app-authentication)
- [JWT Ruby Gem Documentation](https://github.com/jwt/ruby-jwt)
- [GitHub Apps Rate Limits](https://docs.github.com/en/rest/overview/resources-in-the-rest-api#rate-limiting)
- [GitHub Security Best Practices](https://docs.github.com/en/code-security/supply-chain-security)
