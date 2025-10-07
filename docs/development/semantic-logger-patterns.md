# SemanticLogger Best Practices

## Overview

SemanticLogger provides powerful structured logging with built-in support for exceptions, timing, and contextual data.

## Logger Initialization

### ✅ Best Practice: Use Class-Based Logger Names

Create loggers using the class constant to automatically inherit the component name:

```ruby
class MyProcessor
  def initialize
    @logger = SemanticLogger[self.class]  # Automatically uses 'MyProcessor' as component
  end
end
```

This eliminates the need to manually add `component:` to every log call - the logger name is automatically included in all log entries.

### ❌ Avoid: String-Based Logger Names

```ruby
# DON'T DO THIS
@logger = SemanticLogger['MyProcessor']  # String instead of class

# And then manually adding component to every call
@logger.info('Message', payload: { component: 'MyProcessor' })  # Redundant!
```

## Exception Logging

### ✅ Best Practice: Use `exception:` Parameter

SemanticLogger automatically captures full exception details including:

- Exception class and message
- Full backtrace
- Cause chain (nested exceptions)
- Child exceptions

```ruby
begin
  risky_operation()
rescue StandardError => e
  @logger.error('Operation failed',
                exception: e,
                payload: {
                  repo: repo_name,
                  component: 'my_component'
                })
end
```

### ❌ Avoid: Manual Exception Formatting

```ruby
# DON'T DO THIS
rescue StandardError => e
  @logger.error('Operation failed', payload: {
    error: e.message,           # Only message, no backtrace
    error_class: e.class.name   # Loses cause chain
  })
end
```

## Timing Measurements

### ✅ Best Practice: Use `measure_*` Methods

SemanticLogger provides built-in timing with automatic duration logging:

```ruby
@logger.measure_info('Processing repository') do
  # Your code here
  process_repo(repo_name)
end
# Automatically logs: "Processing repository -- {:duration => 1234.5}"
```

### Available Measurement Levels

```ruby
@logger.measure_debug('Debug operation') { ... }
@logger.measure_info('Info operation') { ... }
@logger.measure_warn('Slow operation') { ... }
@logger.measure_error('Failed operation') { ... }
```

### With Additional Payload

```ruby
@logger.measure_info('Processing repository',
                     payload: { repo: repo_name, component: 'processor' }) do
  process_repo(repo_name)
end
# Logs: "Processing repository -- {:repo => "my-repo", :component => "processor", :duration => 1234.5}"
```

### ❌ Avoid: Manual Timing

```ruby
# DON'T DO THIS
start_time = Time.now
process_repo(repo_name)
duration = Time.now - start_time
@logger.info('Processed repository', payload: { duration: duration })
```

## Output to Screen

SemanticLogger outputs to configured appenders. The default configuration outputs to STDOUT (screen).

### Current Configuration

```ruby
# In your code
@logger = SemanticLogger['ComponentName']
@logger.info('Message')  # Outputs to screen via STDOUT appender
```

### Appender Configuration (if needed)

```ruby
# Add file appender
SemanticLogger.add_appender(file_name: 'log/application.log')

# Add JSON appender
SemanticLogger.add_appender(io: $stdout, formatter: :json)
```

## Complete Example

```ruby
class MyProcessor
  def initialize
    @logger = SemanticLogger[self.class]  # Component name inherited from class
  end

  def process_repository(repo_name)
    @logger.measure_info('Repository processing',
                         payload: { repo: repo_name }) do  # No need for component:
      begin
        # Your processing logic
        clone_repo(repo_name)
        run_checks(repo_name)
        create_pr(repo_name)
        @logger.info('Repository processed successfully',
                     payload: { repo: repo_name, status: 'success' })
      rescue StandardError => e
        @logger.error('Repository processing failed',
                      exception: e,
                      payload: { repo: repo_name, status: 'failed' })
        raise # Re-raise if needed
      end
    end
  end
end
```

## Migration Checklist

- [ ] Replace `error: e.message` with `exception: e`
- [ ] Remove `error_class: e.class.name` (captured automatically)
- [ ] Replace manual timing with `measure_*` methods
- [ ] Add `component:` to all log payloads for filtering
- [ ] Use appropriate log levels (debug, info, warn, error)

## Benefits

1. **Automatic exception details** - No manual formatting needed
2. **Precise timing** - Millisecond precision, no manual calculation
3. **Structured data** - Easy to parse and analyze
4. **Cause chain tracking** - Automatically captures nested exceptions
5. **Consistent format** - All logs follow the same structure
