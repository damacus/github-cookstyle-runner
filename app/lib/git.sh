#!/usr/bin/env bash
# =============================================================================
# GitHub Cookstyle Runner - Git Operations Module
# =============================================================================
#
# This module provides functions for Git operations such as cloning repositories,
# creating branches, managing changelogs, and committing changes.
#
# Required environment variables:
#   - GCR_DEFAULT_GIT_BRANCH: Default branch name (usually 'main')
#   - GCR_GIT_NAME: Git author name for commits
#   - GCR_GIT_EMAIL: Git author email for commits
#   - GCR_CHANGELOG_LOCATION: Path to changelog file
#   - GCR_CHANGELOG_MARKER: Marker in changelog for adding entries
#   - CACHE_DIR: Directory for repository clones
#
# Usage:
#   source "path/to/git.sh"
#   clone_or_update_repo "https://github.com/org/repo.git" "repo" "/path/to/cache/repo"
#   create_cookstyle_branch "cookstyle-fixes"
#   update_changelog "CHANGELOG.md" "## Unreleased"
#   commit_and_push_changes "branch-name" "Commit message"

# Library functions for Git operations - will only be sourced, not run standalone

# Source logging
source "/app/lib/logging.sh"

# Clone or update a git repository
clone_or_update_repo() {
    local repo_url="$1"
    local repo_name="$2"
    local repo_dir="$3"

    # Check if repo already exists locally
    if [[ -d "${repo_dir}/.git" ]]; then
        log "INFO" "Updating existing clone: ${repo_dir}"
        cd "${repo_dir}" || return 1

        # Use || true to prevent script exit if git commands fail initially
        if (git fetch origin "${GCR_DEFAULT_GIT_BRANCH}" --quiet &&
            git reset --hard "origin/${GCR_DEFAULT_GIT_BRANCH}" --quiet); then
            log "DEBUG" "Update successful for ${repo_name}."
            return 0
        else
            log "WARN" "Failed to update ${repo_name} cleanly. Attempting full re-clone."
            cd "${CACHE_DIR}" || return 1
            rm -rf "${repo_dir}"
            if git clone --depth 1 --branch "${GCR_DEFAULT_GIT_BRANCH}" "${repo_url}" "${repo_dir}" --quiet; then
                log "INFO" "Re-clone successful for ${repo_name}."
                return 0
            else
                log "ERROR" "Failed to re-clone ${repo_name}."
                return 1
            fi
        fi
    else
        log "INFO" "Cloning ${repo_name} into ${repo_dir}"
        if git clone --depth 1 --branch "${GCR_DEFAULT_GIT_BRANCH}" "${repo_url}" "${repo_dir}" --quiet; then
            log "DEBUG" "Clone successful for ${repo_name}."
            return 0
        else
            log "ERROR" "Failed to clone ${repo_name}."
            return 1
        fi
    fi
}

# Create a branch for cookstyle changes
create_cookstyle_branch() {
    local branch_name="$1"

    # Check if the branch already exists, delete it if it does
    if git rev-parse --verify "${branch_name}" &>/dev/null; then
        log "INFO" "Branch ${branch_name} exists, deleting"
        git branch -D "${branch_name}"
    fi

    # Create new branch
    git checkout -b "${branch_name}"
    return $?
}

# Update changelog with cookstyle changes
update_changelog() {
    local changelog_location="$1"
    local changelog_marker="$2"

    log "INFO" "Updating changelog at ${changelog_location}"

    # Separate command execution from variable assignment to avoid masking return values
    local current_date
    current_date=$(date +"%Y-%m-%d")
    local changelog_entry="\n* Cookstyle auto-correction applied (${current_date})\n"

    # Check if the marker exists in the changelog
    if grep -q "${changelog_marker}" "${changelog_location}"; then
        # Insert after the marker
        sed -i "s/${changelog_marker}/${changelog_marker}${changelog_entry}/" "${changelog_location}"
        log "DEBUG" "Inserted entry after ${changelog_marker}"
    else
        # Insert before the next level 2 heading (##)
        sed -i "/## /i${changelog_entry}" "${changelog_location}"
        log "DEBUG" "Inserted entry before next level 2 heading"
    fi

    return $?
}

# Commit and push changes
commit_and_push_changes() {
    local branch_name="$1"
    local commit_message="$2"

    # Commit changes
    git add -A
    git commit -m "${commit_message}"
    log "INFO" "Changes committed to branch ${branch_name}"

    # Push to GitHub
    if git push -u origin "${branch_name}" -f; then
        log "INFO" "Branch pushed to GitHub"
        return 0
    else
        log "ERROR" "Failed to push branch to GitHub"
        return 1
    fi
}

# Export functions so they're available when sourced
export -f clone_or_update_repo
export -f create_cookstyle_branch
export -f update_changelog
export -f commit_and_push_changes
