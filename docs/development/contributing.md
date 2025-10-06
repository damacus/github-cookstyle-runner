# Contributing

Thank you for your interest in contributing to the GitHub Cookstyle Runner!

## Getting Started

### Prerequisites

- Ruby 3.4+
- Git
- Docker and Docker Compose
- Bundler

### Development Setup

1. **Fork and clone the repository**:

```bash
git clone https://github.com/YOUR_USERNAME/github-cookstyle-runner.git
cd github-cookstyle-runner
```

1. **Install dependencies**:

```bash
bundle install
```

1. **Set up configuration**:

```bash
cp config/settings/local.yml.example config/settings/local.yml
# Edit local.yml with your GitHub App credentials
```

1. **Run tests**:

```bash
bundle exec rspec
```

## Development Workflow

### Test-Driven Development (TDD)

This project follows strict TDD principles:

1. **Write a failing test first**
2. **Implement the minimum code to make it pass**
3. **Refactor while keeping tests green**

Example workflow:

```bash
# 1. Write test
vim spec/lib/cookstyle_runner/my_feature_spec.rb

# 2. Run test (should fail)
bundle exec rspec spec/lib/cookstyle_runner/my_feature_spec.rb

# 3. Implement feature
vim lib/cookstyle_runner/my_feature.rb

# 4. Run test (should pass)
bundle exec rspec spec/lib/cookstyle_runner/my_feature_spec.rb

# 5. Refactor and ensure all tests pass
bundle exec rspec
```

### Code Style

This project uses RuboCop for code style enforcement:

```bash
# Check style
bundle exec rubocop

# Auto-fix issues
bundle exec rubocop -a

# Auto-fix unsafe issues (use with caution)
bundle exec rubocop -A
```

**Style requirements**:

- Two-space indentation
- snake_case for variables and methods
- CamelCase for classes and modules
- Follow all RuboCop defaults

### Type Checking

This project uses Sorbet for type safety:

```bash
# Run type checker
bundle exec srb tc

# Update RBI files
bundle exec tapioca gem
```

**Type requirements**:

- Add type signatures to all public methods
- Use `T.nilable` for nullable types
- Avoid `T.untyped` unless absolutely necessary

## Making Changes

### Branch Naming

Use descriptive branch names:

- `feature/add-webhook-support`
- `fix/cache-corruption-issue`
- `refactor/simplify-git-operations`
- `docs/update-installation-guide`

### Commit Messages

Follow [Conventional Commits](https://www.conventionalcommits.org/):

```text
feat: add webhook support for repository events
fix: resolve cache corruption on invalid JSON
refactor: extract PR creation logic into separate class
docs: update installation guide with Kubernetes examples
test: add integration tests for cache system
```

**Format**:

```text
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
- `chore`: Maintenance tasks
- `perf`: Performance improvements

### Pull Requests

1. **Create a focused PR**:
   - One feature or fix per PR
   - Keep changes small and reviewable
   - Include tests for all changes

1. **Write a clear description**:

```markdown
## Description
Brief description of the changes

## Motivation
Why is this change needed?

## Changes
- List of specific changes
- Made in this PR

## Testing
How was this tested?

## Checklist
- [ ] Tests added/updated
- [ ] Documentation updated
- [ ] RuboCop passes
- [ ] Sorbet type checks pass
- [ ] All tests pass
```

1. **Ensure CI passes**:
   - All tests must pass
   - RuboCop must pass
   - Sorbet type checks must pass

## Testing

### Running Tests

```bash
# Run all tests
bundle exec rspec

# Run specific test file
bundle exec rspec spec/lib/cookstyle_runner/cache_spec.rb

# Run specific test
bundle exec rspec spec/lib/cookstyle_runner/cache_spec.rb:42

# Run with coverage
COVERAGE=true bundle exec rspec
```

### Writing Tests

**Unit tests**:

```ruby
# spec/lib/cookstyle_runner/my_feature_spec.rb
RSpec.describe CookstyleRunner::MyFeature do
  describe '#my_method' do
    it 'returns expected value' do
      feature = described_class.new
      expect(feature.my_method).to eq('expected')
    end
  end
end
```

**Integration tests**:

```ruby
# spec/integration/my_feature_integration_spec.rb
RSpec.describe 'MyFeature Integration' do
  it 'works end-to-end' do
    # Test full workflow
  end
end
```

### Test Coverage

Aim for >90% test coverage:

```bash
COVERAGE=true bundle exec rspec
open coverage/index.html
```

## Local Development

### Running Locally

```bash
# Run with local configuration
./bin/cookstyle-runner

# Run with debug mode
GCR_DEBUG_MODE=1 ./bin/cookstyle-runner

# Run with specific repos
GCR_FILTER_REPOS=test-repo ./bin/cookstyle-runner
```

### Using Docker

```bash
# Build local image
docker-compose build

# Run tests in Docker
docker-compose run test

# Run application in Docker
docker-compose up
```

### Debugging

```bash
# Enable debug logging
GCR_DEBUG_MODE=1 ./bin/cookstyle-runner

# Use pry for debugging
# Add `binding.pry` in code, then run
bundle exec ./bin/cookstyle-runner

# Use Docker for debugging
docker-compose run --entrypoint /bin/bash app
```

## Documentation

### Updating Documentation

Documentation is built with MkDocs:

```bash
# Install MkDocs
pip install mkdocs-material mkdocs-git-revision-date-localized-plugin

# Serve locally
mkdocs serve

# Build
mkdocs build

# Deploy (maintainers only)
mkdocs gh-deploy
### Documentation Structure

```text
docs/
├── index.md                    # Home page
├── installation/
│   ├── index.md               # Installation overview
│   ├── docker-compose.md      # Docker Compose guide
├── configuration/
│   ├── index.md               # Configuration overview
│   ├── environment-variables.md
│   └── advanced.md
├── usage/
│   ├── basic.md
│   ├── advanced.md
│   └── troubleshooting.md
└── development/
    ├── contributing.md        # This file
    └── architecture.md
```

## Release Process

(For maintainers)

1. **Update CHANGELOG.md**
1. **Create release branch**: `release/v1.2.3`
1. **Update version** (if applicable)
1. **Create PR to main**
1. **After merge, create GitHub Release**
1. **Tag triggers Docker image build**

## Code Review

### As a Reviewer

- Be constructive and respectful
- Focus on code quality, not personal preferences
- Suggest improvements, don't demand them
- Approve when ready, request changes if needed

### As an Author

- Respond to all comments
- Make requested changes or explain why not
- Keep discussions focused on the code
- Be open to feedback

## Getting Help

- **Questions**: Open a [Discussion](https://github.com/damacus/github-cookstyle-runner/discussions)
- **Bugs**: Open an [Issue](https://github.com/damacus/github-cookstyle-runner/issues)
- **Chat**: (If available)

## Code of Conduct

Be respectful, inclusive, and professional. We're all here to build great software together.

## License

By contributing, you agree that your contributions will be licensed under the Apache License 2.0.
