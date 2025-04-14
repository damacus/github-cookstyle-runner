#!/usr/bin/env bash
# =============================================================================
# GitHub Cookstyle Runner - Cookstyle Operations Module
# =============================================================================
#
# This module provides functions for running Cookstyle checks, applying
# auto-corrections, and processing Ruby code linting results.
#
# Required environment variables:
#   - GCR_BRANCH_NAME: Branch name for cookstyle fixes
#   - CACHE_DIR: Directory for repository clones
#   - GCR_MANAGE_CHANGELOG: Whether to update changelog (0 or 1)
#   - GCR_CHANGELOG_LOCATION: Path to changelog file
#   - GCR_CHANGELOG_MARKER: Marker in changelog for adding entries
#   - GCR_PULL_REQUEST_TITLE: Title for pull requests
#
# Usage:
#   source "path/to/cookstyle.sh"
#   run_cookstyle_check "repo-name"
#   run_cookstyle_autocorrect "repo-name"
#   process_cookstyle_errors "$error_output"
#   process_repository "https://github.com/org/repo.git" "1" "10"

# Library functions for cookstyle operations - will only be sourced, not run standalone

# Source logging
source "/app/lib/logging.sh"

# Run cookstyle check on a repository
run_cookstyle_check() {
    local repo_name="$1"

    log "INFO" "Running cookstyle on ${repo_name}..."

    # Run cookstyle and capture output
    if output=$(cookstyle 2>&1); then
        log "INFO" "OK: ${repo_name} passed cookstyle checks."
        return 0
    else
        log "ERROR" "FAIL: ${repo_name} has cookstyle issues. Attempting auto-correction."
        return 1
    fi
}

# Run cookstyle with auto-correction
run_cookstyle_autocorrect() {
    local repo_name="$1"

    # Run cookstyle with auto-correct
    if cookstyle -a; then
        log "INFO" "Auto-correct applied successfully to ${repo_name}"

        # Check if there are actual changes
        if ! git diff --quiet; then
            log "INFO" "Changes detected after auto-correction"
            return 0
        else
            log "INFO" "No changes after applying cookstyle auto-corrections"
            return 2  # Return 2 for no changes (success but no action needed)
        fi
    else
        log "ERROR" "Auto-correct failed for ${repo_name}"
        return 1
    fi
}

# Process cookstyle errors
process_cookstyle_errors() {
    local output="$1"

    # Use parameter expansion instead of sed for indentation
    while IFS= read -r line; do
        log "ERROR" "  ${line}"
    done <<< "${output}"
}

# Process a single repository - runs all cookstyle operations
# Returns:
#   0 - Success (no issues or issues fixed)
#   1 - Failure (issues that couldn't be fixed)
process_repository() {
    local repo_url="$1"
    local processed_count="$2"
    local total_repos="$3"

    local repo_name lint_status=0
    local output=""

    # Extract repo name and set directory
    repo_name=$(basename "${repo_url}" .git)
    local repo_dir="${CACHE_DIR}/${repo_name}"

    log "INFO" "[${processed_count}/${total_repos}] Processing: ${repo_name}"

    # Clone or update repository
    if ! clone_or_update_repo "${repo_url}" "${repo_name}" "${repo_dir}"; then
        log "ERROR" "Failed to clone/update ${repo_name}. Skipping."
        return 1  # Repository setup failed
    fi

    # Change to repo directory for further operations
    cd "${repo_dir}" || { log "ERROR" "Cannot cd into ${repo_dir}"; return 1; }

    # Run cookstyle check
    if output=$(cookstyle 2>&1); then
        log "INFO" "OK: ${repo_name} passed cookstyle checks."
    else
        # Create branch for fixes
        if ! create_cookstyle_branch "${GCR_BRANCH_NAME}"; then
            log "ERROR" "Failed to create branch for ${repo_name}. Skipping."
            cd "${CACHE_DIR}" || exit 1
            return 1
        fi

        # Apply auto-corrections
        if run_cookstyle_autocorrect "${repo_name}"; then
            # Changes detected, proceed with PR creation

            # Update changelog if needed
            if [[ "${GCR_MANAGE_CHANGELOG}" == "1" ]] && [[ -f "${GCR_CHANGELOG_LOCATION}" ]]; then
                update_changelog "${GCR_CHANGELOG_LOCATION}" "${GCR_CHANGELOG_MARKER}"
            fi

            # Commit and push changes
            if commit_and_push_changes "${GCR_BRANCH_NAME}" "${GCR_PULL_REQUEST_TITLE}"; then
                # Create pull request
                if create_pull_request "${repo_name}"; then
                    log "INFO" "Successfully created PR for ${repo_name}"
                else
                    log "ERROR" "Failed to create PR for ${repo_name}"
                    lint_status=1
                fi
            else
                log "ERROR" "Failed to commit and push changes for ${repo_name}"
                lint_status=1
            fi
        elif [[ $? -eq 2 ]]; then
            # No changes after auto-correction (exit code 2)
            log "INFO" "No changes after applying cookstyle auto-corrections"
        else
            # Auto-correction failed (exit code 1)
            log "ERROR" "Auto-correct failed for ${repo_name}"
            process_cookstyle_errors "${output}"
            lint_status=1
        fi
    fi

    # Return to cache directory for next repo
    cd "${CACHE_DIR}" || exit 1

    return $lint_status
}

# Export functions so they're available when sourced
export -f run_cookstyle_check
export -f run_cookstyle_autocorrect
export -f process_cookstyle_errors
export -f process_repository
