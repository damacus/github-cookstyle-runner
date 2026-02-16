# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

GitHub Cookstyle Runner is a Ruby-based application that automatically runs Cookstyle (Chef's Ruby linting tool) against repositories in a GitHub organization and creates pull requests with automated fixes. It features multi-threaded processing, intelligent caching, and comprehensive error handling.

## Development Commands

### Testing

```bash
# Run all tests
bundle exec rspec

# Run specific test file
bundle exec rspec spec/path/to/file_spec.rb

# Run specific test (by line number)
bundle exec rspec spec/path/to/file_spec.rb:42

# Run with coverage
COVERAGE=true bundle exec rspec
```

### Linting and Type Checking

```bash
# RuboCop (Ruby style)
bundle exec rubocop                # Check style
bundle exec rubocop -a             # Auto-fix safe issues
bundle exec rubocop -A             # Auto-fix all issues (use with caution)

# Sorbet (type checking)
bundle exec srb tc                 # Run type checker
bundle exec tapioca sync           # Sync gem RBIs
bundle exec tapioca dsl            # Generate DSL RBIs

# Run all quality checks
rake quality                       # Runs RuboCop + Sorbet typecheck
```

### Rake Tasks

```bash
rake                              # Default: runs specs + quality checks
rake spec                         # Run RSpec tests
rake rubocop                      # Run RuboCop
rake rubocop_autocorrect          # Auto-correct RuboCop violations
rake sorbet:typecheck             # Run Sorbet type checking
rake sorbet:all                   # Run all Sorbet tasks
```

### Application CLI

```bash
./bin/cookstyle-runner run        # Run Cookstyle on repositories
./bin/cookstyle-runner list       # List repositories to be processed
./bin/cookstyle-runner config     # Display configuration
./bin/cookstyle-runner status     # Show cache status
./bin/cookstyle-runner version    # Display version

# Debug mode
GCR_DEBUG_MODE=1 ./bin/cookstyle-runner run
```

## Architecture

### Core Design Patterns

**Service Objects**: Each major operation is encapsulated in a dedicated service object following the Single Responsibility Principle:
- `RepositoryProcessor` - Orchestrates repository processing with thread pool
- `GitHubPRManager` - Manages PR/issue creation
- `CookstyleOperations` - Executes Cookstyle and parses results
- `Git` - Handles all git operations (clone, commit, push)
- `Cache` - Manages repository state tracking

**Process Isolation**: Each repository is processed in its own isolated directory to prevent cross-repository conflicts in multi-threaded execution.

**Dependency Injection**: Dependencies are injected into constructors, not created internally. This makes testing easier and dependencies explicit.

### Execution Flow

1. **Configuration & Authentication**: Loads settings from environment variables, validates schema, authenticates with GitHub (using App or PAT)
2. **Repository Discovery**: Searches GitHub for repositories by topics, applies filters
3. **Parallel Processing**: Processes repositories concurrently using thread pool (configurable via `GCR_THREAD_COUNT`)
4. **Per-Repository Processing**:
   - Check cache (skip if unchanged and fresh)
   - Clone repository (shallow clone for performance)
   - Run Cookstyle with auto-correction
   - Parse JSON output to categorize offenses
   - Create branch, commit changes, push
   - Create PR (separate PRs for auto-correctable vs manual fixes)
   - Update cache with new state
5. **Completion**: Save cache statistics, log summary

### Multi-threading Model

- Uses `Parallel` gem with configurable thread pool size
- Each thread processes one repository at a time in an isolated working directory
- Cache writes are synchronized (thread-safe)
- GitHub API client and logger are thread-safe
- Errors in one thread don't affect others (comprehensive error handling with retry logic)

### Caching System

- **Storage**: JSON file-based (simple, portable, atomic writes)
- **Tracking**: Repository state via commit SHA
- **Expiration**: Time-based (configurable via `GCR_CACHE_MAX_AGE`)
- **Benefits**: Skips unchanged repositories, reduces API calls, improves performance on subsequent runs

### Authentication

Supports two methods (only one required):
- **GitHub App** (recommended): JWT-based with installation tokens (`GITHUB_APP_ID`, `GITHUB_APP_INSTALLATION_ID`, `GITHUB_APP_PRIVATE_KEY`)
- **Personal Access Token**: Simpler setup (`GITHUB_TOKEN`)

Both provide authenticated HTTPS URLs for git operations and GitHub API access.

## Code Standards

### Test-Driven Development (TDD)

**CRITICAL**: This project follows strict TDD principles:
1. Write a failing test first (Red)
2. Implement minimum code to make it pass (Green)
3. Refactor while keeping tests green
4. Run RSpec and RuboCop after every change
5. Show test output to prove Red → Green transition

### Sorbet Type Safety

**STRICT COMPLIANCE REQUIRED**:
- All code must use Sorbet `strict` mode
- Add `sig` type signatures to all public methods
- Use `extend T::Sig` in classes with type signatures
- Use `T.nilable` for nullable types
- **NEVER use `T.untyped` or `T.unsafe`** - these are prohibited

Example:
```ruby
extend T::Sig

sig { params(repo_name: String, branch: String).returns(T.nilable(String)) }
def process_repository(repo_name, branch)
  # implementation
end
```

### Logging with SemanticLogger

**Logger Initialization**:
```ruby
@logger = SemanticLogger[self.class]  # Use class-based logger names
```

**Structured Logging**:
- Always use structured payloads with `payload:` parameter
- Include relevant context: `repo`, `operation`, `action`, `error`
- Follow consistent key naming conventions

```ruby
# Good - structured with context
@logger.info('Finished processing repository', payload: {
  repo: repo_name,
  time_taken: duration,
  issues_found: count
})

@logger.error('Failed to create pull request', exception: e, payload: {
  repo: repo_name,
  operation: 'create_pr',
  branch: branch_name
})

# Bad - string interpolation without structure
@logger.info("Finished processing #{repo_name}")
```

**Log Levels**:
- **DEBUG**: Internal operations, command execution, detailed flow
- **INFO**: User-facing milestones, significant state changes
- **WARN**: Recoverable issues, retry attempts
- **ERROR**: Failures requiring attention, unrecoverable errors
- **FATAL**: Critical errors preventing application from continuing

See `docs/development/logging-guidelines.md` for comprehensive patterns.

### Code Organization

**Module Structure**:
- All code under `lib/cookstyle_runner/`
- One class per file
- Use descriptive names
- Follow Ruby naming conventions (snake_case for files/methods, CamelCase for classes)

**When Complexity Increases**:
- Extract internal helper methods rather than expanding public methods
- Keep public APIs stable
- Use guard clauses for early returns to reduce nesting

**Code Hygiene**:
- Delete unused code immediately (don't comment out)
- Remove all TODO comments before finalizing
- Maximum method length: 15 lines
- Maximum class length: 120 lines

### RuboCop Configuration

- Maximum line length: 150 characters
- Use `frozen_string_literal: true` at top of all Ruby files
- Configuration in `.rubocop.yml` with temporary exceptions in `.rubocop_todo.yml`

## Configuration

Environment variables prefixed with `GCR_` (GitHub Cookstyle Runner):

**Required**:
- `GCR_DESTINATION_REPO_OWNER` - Owner of repositories to update
- `GCR_DESTINATION_REPO_TOPICS` - Topics to search for (CSV)
- `GCR_GIT_EMAIL` - Email for git commits
- `GCR_GIT_NAME` - Name for git commits
- Either GitHub App credentials OR `GITHUB_TOKEN`

**Key Optional**:
- `GCR_THREAD_COUNT` - Parallel processing threads (default: CPU cores)
- `GCR_CACHE_MAX_AGE` - Cache expiration in days (default: 7)
- `GCR_DEBUG_MODE` - Enable verbose debug logging (default: disabled)
- `GCR_FILTER_REPOS` - Process specific repositories only (CSV)

Configuration validation uses `dry-schema` in `settings_validator.rb`.

## Testing

### Test Structure

- Tests mirror `lib/` directory structure
- Use RSpec mocking and stubbing
- Maximum 20 memoized helpers per spec file
- Maximum 10 expectations per example
- Maximum 20 lines per example

### Test Requirements

- Write tests for all new functionality
- Aim for 100% coverage on new/modified code
- Test error conditions and edge cases
- Use VCR for API mocking in integration tests

### Example Test Pattern

```ruby
RSpec.describe CookstyleRunner::MyFeature do
  let(:logger) { instance_double(SemanticLogger::Logger) }

  before do
    allow(SemanticLogger).to receive(:[]).and_return(logger)
    allow(logger).to receive(:info)
  end

  it 'logs completion with structured data' do
    subject.process

    expect(logger).to have_received(:info).with(
      'Processing complete',
      payload: hash_including(repo: anything, status: 'completed')
    )
  end
end
```

## Commit Conventions

Follow [Conventional Commits](https://www.conventionalcommits.org/):

```
<type>: <description>

[optional body]
```

**Types**:
- `feat`: New feature
- `fix`: Bug fix
- `refactor`: Code refactoring
- `test`: Adding/updating tests
- `docs`: Documentation changes
- `chore`: Maintenance (dependencies, CI)
- `perf`: Performance improvements

## Common Development Workflows

### Adding a New Feature

1. Write failing test first (TDD)
2. Create new module/class under `lib/cookstyle_runner/`
3. Add type signatures (Sorbet strict)
4. Implement with structured logging
5. Run tests and linters after each change
6. Update CHANGELOG.md under "## Unreleased"
7. Update README.md if adding configuration options

### Bug Fixes

1. Add failing test demonstrating the bug
2. Implement fix
3. Verify test passes
4. Run full test suite
5. Update CHANGELOG.md if user-facing

### Modifying Configuration

1. Update validation in `settings_validator.rb`
2. Add to README.md configuration table
3. Add tests for validation
4. Update environment variable examples

## Important Constraints

- **GitHub API Rate Limits**: 5,000 requests/hour - do not run continuously
- **No Repository Forking**: Works directly on repositories (requires push permissions)
- **Ruby Version**: 3.4.1 (managed via `.tool-versions`)
- **Cookstyle Version**: Baked into Docker image at build time

## Documentation

Full documentation available at: https://damacus.github.io/github-cookstyle-runner/

Key docs:
- `docs/development/architecture.md` - Detailed architecture diagrams
- `docs/development/logging-guidelines.md` - Comprehensive logging patterns
- `docs/development/semantic-logger-patterns.md` - SemanticLogger examples
