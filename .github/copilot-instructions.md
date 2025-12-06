# GitHub Copilot Instructions for github-cookstyle-runner

This repository contains the GitHub Cookstyle Runner application, a Ruby-based tool that automatically runs Cookstyle (Chef's Ruby linting tool) against repositories in a GitHub organization and creates pull requests with automated fixes.

## Project Overview

The application is designed to:

- Find repositories by topic in a GitHub organization
- Run Cookstyle against those repositories
- Apply automated fixes where possible
- Create pull requests with the changes
- Update changelogs automatically
- Support multi-threaded processing with intelligent caching

## Language & Frameworks

- **Language**: Ruby 3.4.1 (managed via `.tool-versions`)
- **Key Dependencies**:
  - `octokit` - GitHub API client
  - `git` - Git operations
  - `cookstyle` - Chef Ruby linting tool
  - `parallel` - Multi-threaded processing
  - `config` - Configuration management
  - `dry-schema` - Configuration validation
  - `jwt` - GitHub App authentication

## Development Environment

### Prerequisites

- Ruby 3.4.1 (use `.tool-versions` file)
- Bundler for dependency management
- Docker (optional, for containerized development)

### Setup

```bash
bundle install
```

### Running Tests

```bash
bundle exec rspec
```

### Running Linters

```bash
# RuboCop for Ruby code style
bundle exec rubocop

# YAML linting (via GitHub Actions or local tools)
yamllint **/*.yml **/*.yaml

# Markdown linting
markdownlint-cli2 "**/*.md"
```

## Code Style Guidelines

### Ruby Style

- Follow RuboCop rules defined in `.rubocop.yml`
- Maximum line length: 150 characters
- Maximum method length: 15 lines
- Maximum class length: 120 lines
- Use `frozen_string_literal: true` at the top of all Ruby files
- Enable Sorbet type checking with `extend T::Sig` and type signatures

### Configuration

- RuboCop configuration: `.rubocop.yml` with `.rubocop_todo.yml` for temporary exceptions
- Markdown linting: `.markdownlint-cli2.yaml`
- YAML linting: `.yamllint`

### Coding Standards

- Use Sorbet for type checking (see `sorbet/` directory)
- Follow module-based organization under `lib/cookstyle_runner/`
- Use descriptive method and variable names
- Add comments for complex logic, but prefer self-documenting code
- Use `# frozen_string_literal: true` at the top of all Ruby files

### Type Checking

This project uses Sorbet for type safety:

```bash
# Run type checker
bundle exec srb tc

# Update RBI files
bundle exec tapioca gem
```

**Type requirements**:

- Add type signatures to all public methods using `sig` blocks
- Use `extend T::Sig` in classes that use type signatures
- Use `T.nilable` for nullable types
- Avoid `T.untyped` unless absolutely necessary
- Follow existing patterns in the codebase for type annotations

### Logging Guidelines

This project uses SemanticLogger for structured logging:

**Logger Initialization**:

- Use class-based logger names: `@logger = SemanticLogger[self.class]`
- This automatically includes the class name in all log entries

**Log Levels**:

- **DEBUG**: Internal operations, detailed flow, command execution details
- **INFO**: User-facing milestones, significant state changes
- **WARN**: Recoverable issues, unexpected but handled situations
- **ERROR**: Failures requiring attention, unrecoverable errors
- **FATAL**: Critical errors that prevent application from continuing

**Exception Logging**:

- Use `exception:` parameter: `@logger.error('Message', exception: e, payload: { ... })`
- Always include structured payload with relevant context (repo_name, operation, etc.)
- See `docs/development/logging-guidelines.md` and `docs/development/semantic-logger-patterns.md` for detailed patterns

## Testing

### Test Framework

- **RSpec** for unit and integration tests
- Tests are located in `spec/` directory
- Follow existing test patterns and structure

### Test Guidelines

- Write tests for all new functionality
- Maintain or improve code coverage
- Use RSpec's mocking and stubbing capabilities
- Test files mirror the structure of `lib/` directory
- Maximum 20 memoized helpers per spec file
- Maximum 10 expectations per example
- Maximum 20 lines per example

### Running Tests

```bash
# Run all tests
bundle exec rspec

# Run specific test file
bundle exec rspec spec/path/to/spec_file.rb

# Run with coverage report
bundle exec rspec
# Coverage report is generated in coverage/ directory
```

## Project Structure

```
lib/
├── cookstyle_runner.rb           # Main application entry point
└── cookstyle_runner/
    ├── application.rb            # Application orchestration
    ├── authentication.rb         # GitHub authentication (PAT/App)
    ├── cache.rb                  # Cache management
    ├── cache_entry.rb            # Cache entry model
    ├── cache_stats.rb            # Cache statistics
    ├── changelog_updater.rb      # Changelog management
    ├── config_manager.rb         # Configuration loading
    ├── configuration.rb          # Configuration object
    ├── context_manager.rb        # Context management
    ├── cookstyle_operations.rb   # Cookstyle execution
    ├── formatter.rb              # Output formatting
    ├── git.rb                    # Git operations
    ├── github_api.rb             # GitHub API interactions
    ├── github_pr_manager.rb      # Pull request management
    ├── reporter.rb               # Result reporting
    ├── repository_manager.rb     # Repository filtering
    ├── repository_processor.rb   # Repository processing
    └── settings_validator.rb     # Settings validation

spec/                             # RSpec tests
config/                           # Configuration files
bin/                             # Executable scripts
```

## Key Components

### Main Application Flow

1. **Configuration Loading** - Loads and validates settings from environment variables
2. **Repository Discovery** - Finds repositories by topic using GitHub API
3. **Parallel Processing** - Processes repositories in multiple threads
4. **Cookstyle Execution** - Runs Cookstyle with autocorrect
5. **Git Operations** - Creates branches, commits changes
6. **Pull Request Creation** - Opens PRs with detailed descriptions
7. **Changelog Updates** - Updates CHANGELOG.md with fixes
8. **Caching** - Tracks processed repositories to avoid redundant work

### Configuration

- Environment variables prefixed with `GCR_` (GitHub Cookstyle Runner)
- Required: `GITHUB_APP_ID`, `GITHUB_APP_INSTALLATION_ID`, `GITHUB_APP_PRIVATE_KEY`, `GCR_DESTINATION_REPO_OWNER`, `GCR_MANAGE_CHANGELOG`
- Configuration validation using `dry-schema` in `settings_validator.rb`
- See README.md for complete list of configuration options

### Authentication

- Supports GitHub App authentication (JWT-based)
- Uses `octokit` gem for GitHub API access
- Authentication handled in `authentication.rb`

## Making Changes

### Branch Naming Convention

Use descriptive branch names following these patterns:

- `feature/add-webhook-support`
- `fix/cache-corruption-issue`
- `refactor/simplify-git-operations`
- `docs/update-installation-guide`

### Commit Message Convention

Follow [Conventional Commits](https://www.conventionalcommits.org/) format:

**Format**:
```
<type>: <description>

[optional body]

[optional footer]
```

**Types**:
- `feat`: New feature
- `fix`: Bug fix
- `refactor`: Code refactoring
- `test`: Adding or updating tests
- `docs`: Documentation changes
- `chore`: Maintenance tasks (dependencies, CI, etc.)

**Examples**:
```
feat: add webhook support for repository events
fix: resolve cache corruption on invalid JSON
refactor: extract PR creation logic into separate class
docs: update installation guide with Kubernetes examples
test: add integration tests for cache system
```

### Test-Driven Development (TDD)

This project follows strict TDD principles:

1. **Write a failing test first**
2. **Implement the minimum code to make it pass**
3. **Refactor while keeping tests green**

### Adding New Features

1. Create a new module/class under `lib/cookstyle_runner/`
2. Follow existing naming conventions and structure
3. Add comprehensive RSpec tests in `spec/`
4. Update README.md if the feature adds new configuration options
5. Update CHANGELOG.md under "## Unreleased" section
6. Run RuboCop and fix any style violations
7. Ensure all tests pass

### Bug Fixes

1. Add a failing test that demonstrates the bug
2. Implement the fix
3. Ensure the test now passes
4. Update CHANGELOG.md if user-facing
5. Run full test suite and linters

### Configuration Changes

1. Update `settings_validator.rb` with new validation rules
2. Update `config_manager.rb` if needed
3. Update README.md configuration table
4. Add tests for configuration validation
5. Update environment variable examples

## CI/CD Pipeline

The project uses GitHub Actions for CI/CD:

### CI Checks (`.github/workflows/ci.yml`)

- YAML linting
- Markdown linting
- RuboCop (Ruby code quality)
- RSpec tests with coverage
- Docker image building and publishing to GHCR

### Release Process (`.github/workflows/release.yml`)

- Automated releases on version tags
- Docker image publishing with semantic versioning

### Pull Request Requirements

- All CI checks must pass
- Code coverage should not decrease
- Follow the PR template in `.github/PULL_REQUEST_TEMPLATE.md`
- Update CHANGELOG.md
- Update README.md if adding configuration options

## Docker

### Dockerfile

- Multi-stage build (builder and final stages)
- Based on Ruby 3.4.1 slim-bullseye
- Runs as non-root user `cookstyle`
- Installs git and required dependencies
- Entry point: `./bin/run_cookstyle_bot`

### Building Locally

```bash
docker build -t cookstyle-runner .
```

### Running with Docker Compose

```bash
docker-compose up
```

Set required environment variables in `docker-compose.yml` or `.env` file.

## Common Tasks

### Adding a New Environment Variable

1. Add to README.md configuration table
2. Add validation in `settings_validator.rb`
3. Add to `config/settings.yml` with default value if applicable
4. Update tests to cover the new variable
5. Update docker-compose.yml with example

### Modifying GitHub API Interactions

1. Changes go in `github_api.rb` or `github_pr_manager.rb`
2. Mock GitHub API responses in tests using RSpec doubles
3. Handle API rate limiting and errors gracefully
4. Follow Octokit best practices

### Updating Cookstyle Execution

1. Modify `cookstyle_operations.rb`
2. Test with various Cookstyle output scenarios
3. Ensure error handling covers edge cases
4. Update tests with new Cookstyle output formats

## Performance Considerations

- Multi-threaded processing using `parallel` gem
- Intelligent caching to avoid re-processing unchanged repositories
- Configurable thread count via `GCR_THREAD_COUNT`
- Cache expiration configurable via `GCR_CACHE_MAX_AGE`
- Process isolation to prevent cross-repository conflicts

## Troubleshooting

### Common Issues

- **Bundle install fails**: Ensure Ruby 3.4.1 is installed
- **Tests fail**: Check that all dependencies are installed with `bundle install`
- **RuboCop violations**: Run `bundle exec rubocop -a` to auto-fix
- **Docker build fails**: Check that Dockerfile is using correct Ruby version

### Debugging

- Set `GCR_LOG_LEVEL=DEBUG` for verbose logging
- Use `GCR_DEBUG_MODE=1` for additional debug output
- Check logs for GitHub API rate limiting issues
- Verify GitHub App credentials are correct

## Additional Resources

- [GitHub API Documentation](https://docs.github.com/en/rest)
- [Octokit.rb Documentation](https://github.com/octokit/octokit.rb)
- [Cookstyle Documentation](https://docs.chef.io/workstation/cookstyle/)
- [RuboCop Documentation](https://docs.rubocop.org/)
- [RSpec Documentation](https://rspec.info/)

## Important Notes

- This application requires permissions to create branches and pull requests
- Do not run continuously to avoid GitHub API rate limits
- Use a dedicated GitHub bot account for production deployments
- The application does not fork repositories; it works directly on them
- Cookstyle version is baked into the Docker image at build time
