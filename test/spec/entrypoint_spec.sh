#!/usr/bin/env bash

Describe 'entrypoint.sh basic execution'
  It 'fails predictably without environment variables'
    When run command bash /app/entrypoint.sh
    The status should be failure # Expecting non-zero exit due to missing env vars
    The error should be present  # Expect *some* error message on stderr
  End
End
