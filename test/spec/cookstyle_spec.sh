#!/usr/bin/env bash
# ShellSpec tests for cookstyle.sh module

# Source the spec helper
. "${SHELLSPEC_PROJECT_ROOT}/test/spec/spec_helper.sh"

# Path to the module
MODULE_PATH="${SHELLSPEC_PROJECT_ROOT}/app/lib/cookstyle.sh"

Describe 'cookstyle.sh module'
  # We need to mock cookstyle and other commands
  BeforeAll 'setup_mocks'
  AfterAll 'teardown_mocks'

  setup_mocks() {
    # Create mock directory
    mkdir -p "${SHELLSPEC_TMPDIR}/bin"
    PATH="${SHELLSPEC_TMPDIR}/bin:${PATH}"

    # Mock cookstyle command using POSIX shell syntax
    cat > "${SHELLSPEC_TMPDIR}/bin/cookstyle" << 'EOF'
#!/bin/sh
if [ "$1" = "-a" ]; then
  # Auto-correct version - success
  echo "Cookstyle applied auto-corrections"
  exit 0
else
  # Check version - fail with issues
  echo "Inspecting 12 files"
  echo "Offenses:"
  echo "test.rb:10:80: Style/StringLiterals: Prefer single-quoted strings"
  exit 1
fi
EOF
    chmod +x "${SHELLSPEC_TMPDIR}/bin/cookstyle"

    # Set up test repo directory
    mkdir -p "${SHELLSPEC_TMPDIR}/repo-test"

    # Mock git for diff command
    cat > "${SHELLSPEC_TMPDIR}/bin/git" << 'EOF'
#!/bin/sh
if [ "$1" = "diff" ] && [ "$2" = "--quiet" ]; then
  # Mock changes detected (non-zero exit means changes exist)
  exit 1
elif [ "$1" = "rev-parse" ]; then
  # Branch doesn't exist by default
  exit 1
else
  # Default behavior for other git commands
  echo "Running git $*"
  exit 0
fi
EOF
    chmod +x "${SHELLSPEC_TMPDIR}/bin/git"

    # Define other functions that cookstyle.sh depends on
    # We'll use stub functions for these
    log() {
      echo "LOG: $*"
    }
    export -f log

    clone_or_update_repo() {
      echo "Mock: Cloned/updated $1 to $3"
      return 0
    }
    export -f clone_or_update_repo

    create_cookstyle_branch() {
      echo "Mock: Created branch $1"
      return 0
    }
    export -f create_cookstyle_branch

    update_changelog() {
      echo "Mock: Updated changelog at $1 with marker $2"
      return 0
    }
    export -f update_changelog

    commit_and_push_changes() {
      echo "Mock: Committed and pushed changes to branch $1 with message $2"
      return 0
    }
    export -f commit_and_push_changes

    create_pull_request() {
      echo "Mock: Created PR for repo $1"
      return 0
    }
    export -f create_pull_request

    # Set required variables
    export CACHE_DIR="${SHELLSPEC_TMPDIR}/cache"
    export GCR_BRANCH_NAME="cookstyle-fixes"
    export GCR_MANAGE_CHANGELOG="1"
    export GCR_CHANGELOG_LOCATION="CHANGELOG.md"
    export GCR_CHANGELOG_MARKER="## Unreleased"
    export GCR_PULL_REQUEST_TITLE="Cookstyle Auto Corrections"

    # Create cache directory
    mkdir -p "${CACHE_DIR}"
  }

  teardown_mocks() {
    rm -rf "${SHELLSPEC_TMPDIR}/bin"
    rm -rf "${SHELLSPEC_TMPDIR}/repo-test"
    rm -rf "${CACHE_DIR}"
  }

  Describe 'run_cookstyle_check function'
    # Source the module for this specific test
    BeforeEach 'source "${MODULE_PATH}"'

    It 'detects cookstyle issues correctly'
      repo_name="test-repo"

      When call run_cookstyle_check "${repo_name}"
      The output should include "Running cookstyle on test-repo"
      The output should include "FAIL: test-repo has cookstyle issues"
      The status should be failure
    End
  End

  Describe 'run_cookstyle_autocorrect function'
    # Source the module for this specific test
    BeforeEach 'source "${MODULE_PATH}"'

    It 'applies auto-corrections successfully'
      repo_name="test-repo"

      When call run_cookstyle_autocorrect "${repo_name}"
      The output should include "Auto-correct applied successfully"
      The output should include "Changes detected after auto-correction"
      The status should be success
    End
  End

  Describe 'process_cookstyle_errors function'
    # Source the module for this specific test
    BeforeEach 'source "${MODULE_PATH}"'

    It 'formats error output correctly'
      output="Line 1 error\nLine 2 error"

      When call process_cookstyle_errors "${output}"
      The output should include "LOG: ERROR:   Line 1 error"
      The output should include "LOG: ERROR:   Line 2 error"
      The status should be success
    End
  End

  Describe 'process_repository function'
    # Source the module for this specific test
    BeforeEach 'source "${MODULE_PATH}"'

    It 'processes a repository with issues correctly'
      repo_url="https://github.com/test/repo.git"
      processed_count=1
      total_repos=2

      When call process_repository "${repo_url}" "${processed_count}" "${total_repos}"
      The output should include "Processing: repo"
      The output should include "Mock: Cloned/updated"
      The output should include "Running cookstyle"
      The output should include "Mock: Created branch"
      The output should include "Auto-correct applied"
      The output should include "Mock: Updated changelog"
      The output should include "Mock: Committed and pushed"
      The output should include "Mock: Created PR"
      The status should be success
    End
  End
End
