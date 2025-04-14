#!/usr/bin/env bash
# ShellSpec tests for git.sh module

# Source the spec helper
. "${SHELLSPEC_PROJECT_ROOT}/test/spec/spec_helper.sh"

# Path to the module
MODULE_PATH="${SHELLSPEC_PROJECT_ROOT}/app/lib/git.sh"

Describe 'git.sh module'
  # We need to mock git and other external commands
  BeforeAll 'setup_mocks'
  AfterAll 'teardown_mocks'

  setup_mocks() {
    # Create mock directory
    mkdir -p "${SHELLSPEC_TMPDIR}/bin"
    PATH="${SHELLSPEC_TMPDIR}/bin:${PATH}"

    # Mock git command
    cat > "${SHELLSPEC_TMPDIR}/bin/git" << 'EOF'
#!/bin/sh
if [ "$1" = "clone" ]; then
  # Mock successful clone
  lastarg=""
  for arg in "$@"; do lastarg="$arg"; done
  mkdir -p "$lastarg"
  echo "Cloning into '$lastarg'..."
  exit 0
elif [ "$1" = "checkout" ] && [ "$2" = "-b" ]; then
  # Mock branch creation
  echo "Switched to a new branch '$3'"
  exit 0
elif [ "$1" = "add" ]; then
  echo "Adding files"
  exit 0
elif [ "$1" = "commit" ]; then
  echo "Created commit"
  exit 0
elif [ "$1" = "push" ]; then
  echo "Branch pushed successfully"
  exit 0
elif [ "$1" = "diff" ] && [ "$2" = "--quiet" ]; then
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

    # Set up test repo directory
    mkdir -p "${SHELLSPEC_TMPDIR}/repo-test"
  }

  teardown_mocks() {
    rm -rf "${SHELLSPEC_TMPDIR:?}/bin"
    rm -rf "${SHELLSPEC_TMPDIR:?}/repo-test"
  }

  Describe 'clone_or_update_repo function'
    # Source the module for this specific test
    BeforeEach 'source "${MODULE_PATH}"'

    It 'clones a repository successfully'
      repo_url="https://github.com/test/repo.git"
      repo_name="repo"
      repo_dir="${SHELLSPEC_TMPDIR}/repo-test"

      # Clean up any existing directory
      rm -rf "${repo_dir}"

      When call clone_or_update_repo "${repo_url}" "${repo_name}" "${repo_dir}"
      The output should include "Cloning"
      The status should be success
    End
  End

  Describe 'create_cookstyle_branch function'
    # Source the module for this specific test
    BeforeEach 'source "${MODULE_PATH}"'

    It 'creates a branch successfully'
      branch_name="cookstyle-fixes"
      When call create_cookstyle_branch "${branch_name}"
      The output should include "Switched to a new branch"
      The status should be success
    End
  End

  Describe 'update_changelog function'
    # Source the module for this specific test
    BeforeEach 'source "${MODULE_PATH}"'

    It 'updates changelog when marker is found'
      changelog_file="${SHELLSPEC_TMPDIR}/CHANGELOG.md"
      marker="## Unreleased"

      # Create test changelog
      echo "${marker}" > "${changelog_file}"
      echo "## v1.0.0" >> "${changelog_file}"

      When call update_changelog "${changelog_file}" "${marker}"
      The status should be success
      The contents of file "${changelog_file}" should include "Cookstyle auto-correction"
    End
  End

  Describe 'commit_and_push_changes function'
    # Source the module for this specific test
    BeforeEach 'source "${MODULE_PATH}"'

    It 'commits and pushes changes successfully'
      branch_name="cookstyle-fixes"
      commit_message="Cookstyle Auto Corrections"

      When call commit_and_push_changes "${branch_name}" "${commit_message}"
      The output should include "Adding files"
      The output should include "Created commit"
      The output should include "Branch pushed successfully"
      The status should be success
    End
  End
End
