#!/usr/bin/env bash
# Run ShellSpec tests using bash explicitly

# Set up environment for tests
export SHELLSPEC_SHELL="/bin/bash"  # Force ShellSpec to use bash
export SHELLSPEC_SKIP_BUILTIN=1     # Skip built-in shell detection

# Run the tests with detailed output
shellspec "$@" -f documentation
