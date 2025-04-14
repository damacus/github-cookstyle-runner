#!/usr/bin/env bash
# ShellSpec tests for logging.sh module

# Source the spec helper
. "${SHELLSPEC_PROJECT_ROOT}/test/spec/spec_helper.sh"

# Path to the module
MODULE_PATH="${SHELLSPEC_PROJECT_ROOT}/app/lib/logging.sh"

Describe 'logging.sh module'
  # Source the module before each test
  BeforeAll 'source "${MODULE_PATH}"'

  Describe 'log function'
    It 'outputs log message with expected format'
      When call log "INFO" "Test message"
      The output should match pattern '\[[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}T[0-9]\{2\}:[0-9]\{2\}:[0-9]\{2\}Z\] INFO: Test message'
    End

    It 'handles INFO level correctly'
      When call log "INFO" "Info message"
      The output should include "INFO: Info message"
    End

    It 'handles ERROR level correctly'
      When call log "ERROR" "Error message"
      The output should include "ERROR: Error message"
    End

    It 'handles WARN level correctly'
      When call log "WARN" "Warning message"
      The output should include "WARN: Warning message"
    End

    It 'handles DEBUG level correctly'
      When call log "DEBUG" "Debug message"
      The output should include "DEBUG: Debug message"
    End
  End
End
