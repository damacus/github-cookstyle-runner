# Integration Tests

This directory contains integration tests that verify the full behavior of the Cookstyle Runner application.

## Test Categories

### 1. CLI Commands (`cli_commands_spec.rb`)

Tests basic CLI functionality without requiring external API calls:

- Version display
- Help information
- Configuration display

**Safe for CI**: ✅ No secrets required

### 2. Repository Processing (`repository_processing_spec.rb`)

Tests Cookstyle execution on local repositories:

- Clean repository processing
- Handling repositories with offenses
- Parallel processing
- Error handling

**Safe for CI**: ✅ Uses local test repositories

### 3. Cache Integration (`cache_integration_spec.rb`)

Tests caching behavior:

- Cache persistence
- Cache hit/miss tracking
- `--no-cache` flag behavior

**Safe for CI**: ✅ No external dependencies

### 4. GitHub API Integration (`github_api_spec.rb`)

Tests GitHub API interactions using VCR cassettes:

- Repository listing
- JSON output format

**Safe for CI**: ✅ Uses VCR cassettes (no real API calls)

### 5. PR and Issue Creation (`pr_creation_spec.rb`)

Tests creating PRs and issues on GitHub:

- Auto-correctable fixes → PR creation
- Manual fixes → Issue creation

**Safe for CI**: ⚠️ **Requires VCR cassettes or skips**

These tests are automatically skipped unless:

- Running in CI with proper secrets configured, OR
- VCR cassettes exist for playback

## Security Considerations

### Running Tests on PRs

Integration tests are designed to be **safe to run on untrusted PRs** from forks:

1. **No secrets required for most tests**: The majority of integration tests work without any GitHub tokens
2. **VCR cassettes for API tests**: Tests that need GitHub API use pre-recorded cassettes
3. **Automatic skipping**: Tests requiring real API calls skip when secrets aren't available
4. **Conditional filtering**: VCR only filters secrets that are actually present

### Environment Variables

The following environment variables are **optional** for running tests:

- `GITHUB_TOKEN` - Only needed for recording new VCR cassettes
- `GCR_GITHUB_TOKEN` - Alternative token name
- `GCR_GITHUB_APP_ID` - For GitHub App authentication (recording only)
- `GCR_GITHUB_APP_INSTALLATION_ID` - For GitHub App authentication (recording only)
- `GCR_GITHUB_APP_PRIVATE_KEY` - For GitHub App authentication (recording only)

**None of these are required for running existing tests in CI.**

## Running Integration Tests

### Locally (without secrets)

```bash
bundle exec rspec spec/integration
```

Most tests will run. Tests requiring real API calls will be skipped.

### Locally (with secrets for recording)

```bash
export GITHUB_TOKEN=your_token_here
VCR_RECORD_MODE=all bundle exec rspec spec/integration
```

This will record new VCR cassettes for API interactions.

### In CI

```bash
bundle exec rspec spec/integration
```

All tests run using VCR cassettes. No secrets needed.

## VCR Configuration

VCR (Video Cassette Recorder) records HTTP interactions and replays them during tests:

- **Cassettes stored in**: `spec/fixtures/vcr_cassettes/`
- **Record mode**: Controlled via `VCR_RECORD_MODE` environment variable
  - `once` (default): Record new interactions, replay existing
  - `none`: Only replay, never record (fail if cassette missing)
  - `new_episodes`: Record new interactions, replay existing
  - `all`: Re-record everything
- **Sensitive data**: Automatically filtered from cassettes (tokens, keys, etc.)

### Recording New Cassettes

1. Set up your GitHub token:

   ```bash
   export GITHUB_TOKEN=your_personal_access_token
   ```

2. Delete old cassette (if updating):

   ```bash
   rm spec/fixtures/vcr_cassettes/your_test_name.yml
   ```

3. Run the test in record mode:

   ```bash
   VCR_RECORD_MODE=all bundle exec rspec spec/integration/your_spec.rb
   ```

4. Verify the cassette was created and secrets are filtered:

   ```bash
   grep -i "token" spec/fixtures/vcr_cassettes/your_test_name.yml
   # Should show <GITHUB_TOKEN> instead of actual token
   ```

## Best Practices

1. **Keep tests fast**: Integration tests should complete in seconds, not minutes
2. **Use VCR for external APIs**: Never make real API calls in CI
3. **Test with realistic data**: Use actual repository structures when possible
4. **Clean up after tests**: Remove temporary files and directories
5. **Skip appropriately**: Use `skip` for tests that can't run without specific setup
6. **Document requirements**: Clearly state what each test needs to run

## Troubleshooting

### Test fails with "VCR cassette not found"

The test is trying to make a real HTTP request but no cassette exists. Either:

- Record a new cassette (see "Recording New Cassettes" above)
- The test should skip when cassette is missing (check test implementation)

### Test fails with "Real HTTP connections are disabled"

WebMock is blocking HTTP requests. This is expected behavior. Either:

- Provide a VCR cassette for the test
- Set `VCR_ALLOW_HTTP=true` (only for debugging, never in CI)

### Secrets appearing in cassettes

VCR filtering isn't working. Check:

- Environment variables are set when recording
- `spec/support/vcr.rb` has correct filter configuration
- Cassette was recorded with current VCR configuration

## Adding New Integration Tests

1. Create a new spec file in `spec/integration/`
2. Include `IntegrationHelpers` module for common utilities
3. Tag with `:integration` metadata
4. Use VCR for any external API calls
5. Skip tests that require unavailable resources
6. Document any special requirements in this README

Example:

```ruby
RSpec.describe 'My Feature', :integration do
  include IntegrationHelpers

  it 'does something', vcr: { cassette_name: 'my_feature/test_case' } do
    # Test implementation
  end
end
```
