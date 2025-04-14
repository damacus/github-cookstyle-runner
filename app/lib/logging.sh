#!/usr/bin/env bash
# =============================================================================
# GitHub Cookstyle Runner - Logging Module
# =============================================================================
#
# This module provides logging functionality with different severity levels and
# consistent timestamp formatting.
#
# Usage:
#   source "path/to/logging.sh"
#   log "INFO" "This is an information message"
#   log "ERROR" "This is an error message"
#
# Available log levels:
#   - INFO: General information messages
#   - WARN: Warning messages that don't prevent execution
#   - ERROR: Error messages that indicate failures
#   - DEBUG: Detailed debugging information

# Function to log messages
log() {
    echo "[$(date +'%Y-%m-%dT%H:%M:%SZ')] $1: $2"
}

# Export the function so it's available when sourced
export -f log
