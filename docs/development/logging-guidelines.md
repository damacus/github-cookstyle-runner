# Logging Guidelines

This document provides guidelines for logging in the GitHub Cookstyle Runner codebase.

## Log Levels

### DEBUG

**When to use:** Internal operations, detailed flow, command execution details

**Examples:**

- Git operations (clone, checkout, push)
- Command execution start/end
- Repository processing steps
- Cache operations
- Logger initialization

**Structured payload:** Always include relevant context (repo_name, operation, action)

```ruby
log.debug('Cloning repository', payload: { repo: repo_name, branch: branch, action: 'clone' })
```

### INFO

**When to use:** User-facing milestones, significant state changes

**Examples:**

- Repository processing start/completion
- PR/issue creation
- Cache statistics
- Configuration summary
- Found repositories count

**Structured payload:** Include key metrics and identifiers

```ruby
log.info('Finished processing repository', payload: { repo: repo_name, time_taken: duration, issues_found: count })
```

### WARN

**When to use:** Recoverable issues, unexpected but handled situations

**Examples:**

- Branch doesn't exist (falling back to default)
- Cache misses
- Retry attempts
- Non-critical failures

**Structured payload:** Include context about what went wrong and recovery action

```ruby
log.warn('Branch does not exist, using default', payload: { repo: repo_name, branch: branch, fallback: default_branch })
```

### ERROR

**When to use:** Failures requiring attention, unrecoverable errors

**Examples:**

- Git operations failed
- GitHub API errors
- Cookstyle execution failures
- PR/issue creation failures
- Configuration validation errors

**Structured payload:** Always include error message, operation context, and relevant identifiers

```ruby
log.error('Failed to create pull request', payload: { 
  repo: repo_name, 
  operation: 'create_pr',
  error: e.message,
  branch: branch_name
})
```

### FATAL

**When to use:** Critical errors that prevent application from continuing

**Examples:**

- Missing required configuration
- Authentication failures
- Unrecoverable system errors

## Structured Logging

### When to Add Payloads

**Always add structured payloads for:**

1. Operations involving repositories (include `repo` or `repo_name`)
2. Operations with measurable outcomes (include counts, durations)
3. Error conditions (include `error`, `operation`, context)
4. State transitions (include `action`, `status`)

**Simple strings are acceptable for:**

1. Debug messages about internal flow
2. Very generic operations without specific context
3. Messages that are self-contained

### Payload Structure

Use consistent key names across the codebase:

```ruby
# Repository context
{ repo: repo_name, repo_name: repo_name }

# Operations
{ operation: 'create_pr', action: 'clone' }

# Errors
{ error: e.message, error_type: e.class.name }

# Metrics
{ count: number, duration: seconds, time_taken: seconds }

# Git operations
{ branch: branch_name, commit_sha: sha }

# GitHub API
{ pr_number: number, issue_number: number }
```

## Examples by Module

### Git Operations

```ruby
# Good - structured with context
log.debug('Updating repository', payload: { repo: context.repo_name, branch: branch, action: 'update' })
log.error('Repository update failed', payload: { repo: context.repo_name, error: e.message, action: 'update' })

# Avoid - missing context
log.debug('Updating repository')
log.error("Error: #{e.message}")
```

### GitHub API Operations

```ruby
# Good - includes operation context
log.info('Creating new PR', payload: { repo: repo_full_name, branch: branch_name, operation: 'create_pr' })
log.error('GitHub API error', payload: { operation: 'fetch_repositories', error: e.message, query: query })

# Avoid - string interpolation without structure
log.info("Creating new PR for #{repo_full_name}")
log.error("GitHub API error: #{e.message}")
```

### Cookstyle Operations

```ruby
# Good - includes execution context
log.debug('Executing Cookstyle', payload: { repo: context.repo_name, autocorrect: true })
log.error('Cookstyle command failed unexpectedly', payload: { 
  repo: context.repo_name,
  exit_status: result.exit_status,
  stderr: result.err.strip
})

# Avoid - missing repo context
log.debug("Executing Cookstyle: autocorrect=#{autocorrect}")
```

### Repository Processing

```ruby
# Good - includes progress and timing
log.info('Finished processing repository', payload: { 
  repo: repo_name, 
  time_taken: duration,
  issues_found: count,
  status: 'completed'
})

# Avoid - minimal context
log.info("Finished processing #{repo_name}")
```

## Anti-Patterns to Avoid

### 1. String Interpolation in Error Messages

```ruby
# Bad
log.error("Failed to push branch #{branch_name}: #{e.message}")

# Good
log.error('Failed to push branch', payload: { branch: branch_name, error: e.message, operation: 'push' })
```

### 2. Inconsistent Key Names

```ruby
# Bad - mixing conventions
log.info('Processing', payload: { repository: repo1, repo_name: repo2 })

# Good - consistent naming
log.info('Processing', payload: { repo: repo_name })
```

### 3. Missing Operation Context in Errors

```ruby
# Bad - what operation failed?
log.error("Error: #{e.message}")

# Good - clear operation context
log.error('Git checkout failed', payload: { repo: context.repo_name, branch: branch, error: e.message })
```

### 4. Logging Sensitive Information

```ruby
# Bad - exposes credentials
log.debug("Authenticated URL: #{url_with_token}")

# Good - log without sensitive data
log.debug('Authentication successful', payload: { repo: repo_name, auth_method: 'github_app' })
```

## Testing Logging

When writing tests for logging:

1. Use `have_received` for message expectations
2. Test that appropriate log levels are used
3. Verify structured payloads contain expected keys
4. Don't test exact log message strings (they may change)

```ruby
RSpec.describe MyClass do
  let(:logger) { instance_double(SemanticLogger::Logger) }
  
  before do
    allow(SemanticLogger).to receive(:[]).and_return(logger)
    allow(logger).to receive(:info)
    allow(logger).to receive(:error)
  end
  
  it 'logs processing completion with structured data' do
    subject.process_repository('test-repo')
    
    expect(logger).to have_received(:info).with(
      'Finished processing repository',
      payload: hash_including(repo: 'test-repo', time_taken: anything)
    )
  end
end
```

## Migration Guide

### Converting Existing Logs

1. **Identify the log level** - Is it DEBUG, INFO, WARN, or ERROR?
2. **Extract interpolated values** - Pull out variables from the string
3. **Create structured payload** - Move variables into a payload hash
4. **Use consistent keys** - Follow the naming conventions above
5. **Add missing context** - Include repo_name, operation, etc.

**Before:**

```ruby
log.error("Failed to create PR for #{repo_full_name}: #{e.message}")
```

**After:**

```ruby
log.error('Failed to create pull request', payload: {
  repo: repo_full_name,
  operation: 'create_pr',
  error: e.message
})
```

## Performance Considerations

- Structured logging with SemanticLogger is performant
- Avoid expensive operations in payload construction
- Use lazy evaluation for debug payloads when needed

```ruby
# Good - payload only evaluated if DEBUG level is active
log.debug('Expensive operation') { { data: expensive_calculation } }
```

## Tools and Resources

- [SemanticLogger Documentation](https://logger.rocketjob.io/)
- [JSON Logging Best Practices](https://www.datadoghq.com/blog/json-logging-best-practices/)
- Project logging configuration: `lib/cookstyle_runner.rb` (lines 164-186)
