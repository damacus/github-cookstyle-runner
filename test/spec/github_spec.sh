#!/usr/bin/env bash
# ShellSpec tests for github.sh module

# Source the spec helper
. "${SHELLSPEC_PROJECT_ROOT}/test/spec/spec_helper.sh"

# Path to the module
MODULE_PATH="${SHELLSPEC_PROJECT_ROOT}/app/lib/github.sh"

Describe 'github.sh module'
  # We need to mock curl, jq, and other external commands
  BeforeAll 'setup_mocks'
  AfterAll 'teardown_mocks'
  
  setup_mocks() {
    # Create mock directory
    mkdir -p "${SHELLSPEC_TMPDIR}/bin"
    PATH="${SHELLSPEC_TMPDIR}/bin:$PATH"
    
    # Mock curl for API requests
    cat > "${SHELLSPEC_TMPDIR}/bin/curl" << 'EOF'
#!/bin/sh
case "$*" in
  *search/repositories*)
    echo '{"items":[{"clone_url":"https://github.com/test/repo1.git"},{"clone_url":"https://github.com/test/repo2.git"}]}'
    ;;
  */pulls*)
    echo '{"html_url":"https://github.com/test/pull/1","number":1}'
    ;;
  */labels*)
    echo '{"status":"success"}'
    ;;
  *)
    echo '{"message":"Not found"}'
    ;;
esac
exit 0
EOF
    chmod +x "${SHELLSPEC_TMPDIR}/bin/curl"
    
    # Mock jq for JSON parsing
    cat > "${SHELLSPEC_TMPDIR}/bin/jq" << 'EOF'
#!/bin/sh
if [ "$2" = ".items[].clone_url" ]; then
  echo "https://github.com/test/repo1.git"
  echo "https://github.com/test/repo2.git"
elif [ "$2" = ".html_url" ]; then
  echo "https://github.com/test/pull/1"
elif [ "$2" = ".number" ]; then
  echo "1"
else
  echo "null"
fi
EOF
    chmod +x "${SHELLSPEC_TMPDIR}/bin/jq"
    
    # Mock grep for header extraction
    cat > "${SHELLSPEC_TMPDIR}/bin/grep" << 'EOF'
#!/bin/sh
if [ "$1" = "-i" ] && [ "$2" = "^Link:" ]; then
  # No next page in this mock
  echo ""
else
  # Default behavior
  /bin/grep "$@"
fi
EOF
    chmod +x "${SHELLSPEC_TMPDIR}/bin/grep"
  }
  
  teardown_mocks() {
    rm -rf "${SHELLSPEC_TMPDIR}/bin"
  }

  Describe 'fetch_repo_urls function'
    # Source the module for this specific test
    BeforeEach 'source "${MODULE_PATH}"'
    
    It 'returns repository URLs correctly'
      When call fetch_repo_urls
      The output should include "https://github.com/test/repo1.git"
      The output should include "https://github.com/test/repo2.git"
      The status should be success
    End
  End
  
  Describe 'create_pull_request function'
    # Source the module for this specific test
    BeforeEach 'source "${MODULE_PATH}"'
    
    It 'creates a pull request successfully'
      repo_name="test-repo"
      When call create_pull_request "${repo_name}"
      The output should include "https://github.com/test/pull/1"
      The status should be success
    End
  End
End
