#!/usr/bin/env bash
set -euo pipefail

# === Configuration ===
# Ensure required environment variables are set
: "${GITHUB_TOKEN:?ERROR: GITHUB_TOKEN is required}"
: "${GCR_DESTINATION_REPO_OWNER:?ERROR: GCR_DESTINATION_REPO_OWNER is required}"
# Only GCR_MANAGE_CHANGELOG and GITHUB_TOKEN are absolutely required
: "${GCR_MANAGE_CHANGELOG:?ERROR: GCR_MANAGE_CHANGELOG is required (set to 0 or 1)}"

# Set defaults for optional variables
# Using values from NFS example as defaults
GCR_DESTINATION_REPO_TOPICS="${GCR_DESTINATION_REPO_TOPICS:-chef-cookbook}"
GCR_BRANCH_NAME="${GCR_BRANCH_NAME:-automated/cookstyle}"
GCR_PULL_REQUEST_TITLE="${GCR_PULL_REQUEST_TITLE:-Automated PR: Cookstyle Changes}"
GCR_CHANGELOG_LOCATION="${GCR_CHANGELOG_LOCATION:-CHANGELOG.md}"

# Other optional variables
GCR_DEFAULT_GIT_BRANCH="${GCR_DEFAULT_GIT_BRANCH:-main}"
GITHUB_API_ROOT="${GITHUB_API_ROOT:-api.github.com}"
GCR_GIT_NAME="${GCR_GIT_NAME:-Cookstyle Bot}"
GCR_GIT_EMAIL="${GCR_GIT_EMAIL:-cookstyle@example.com}"
GCR_PULL_REQUEST_LABELS="${GCR_PULL_REQUEST_LABELS:-""}"
GCR_CHANGELOG_MARKER="${GCR_CHANGELOG_MARKER:-"## Unreleased"}"
CACHE_DIR="/tmp/cookstyle-runner"
export API_PER_PAGE=100 # Number of results per API page - exported for github.sh

# === Setup ===
mkdir -p "${CACHE_DIR}"
echo "--- Configuration ---"
echo "Destination Repo Owner: ${GCR_DESTINATION_REPO_OWNER}"
echo "Destination Repo Topics: ${GCR_DESTINATION_REPO_TOPICS}"
echo "Branch Name: ${GCR_BRANCH_NAME}"
echo "PR Title: ${GCR_PULL_REQUEST_TITLE}"
echo "PR Labels: ${GCR_PULL_REQUEST_LABELS:-None}"
echo "Git Author: ${GCR_GIT_NAME} <${GCR_GIT_EMAIL}>"
echo "Default Branch: ${GCR_DEFAULT_GIT_BRANCH}"
echo "GitHub API: ${GITHUB_API_ROOT}"
echo "Cache Dir: ${CACHE_DIR}"
echo "Manage Changelog: ${GCR_MANAGE_CHANGELOG}"
echo "Changelog Location: ${GCR_CHANGELOG_LOCATION:-N/A}"
echo "Changelog Marker: ${GCR_CHANGELOG_MARKER:-N/A}"
echo "---------------------"

# Configure git for PR creation
git config --global user.name "${GCR_GIT_NAME}"
git config --global user.email "${GCR_GIT_EMAIL}"

source "/app/lib/cookstyle.sh"
source "/app/lib/git.sh"
source "/app/lib/github.sh"
source "/app/lib/logging.sh"

# === Discover Repos ===
declare -a REPO_URLS
# Call function and read space-separated URLs into the array
if ! repo_urls=$(fetch_repo_urls); then
    log "ERROR" "Failed to fetch repository list. Exiting."
    exit 1
fi
read -r -a REPO_URLS <<< "${repo_urls}"

log "INFO" "Found ${#REPO_URLS[@]} repositories."
if [[ ${#REPO_URLS[@]} -eq 0 ]]; then
    log "WARN" "No repositories found matching the criteria. Exiting."
    exit 0
fi

# === Process Repos ===
lint_failed_count=0
processed_count=0
total_repos=${#REPO_URLS[@]}

# Process each repository
for repo_url in "${REPO_URLS[@]}"; do
    ((processed_count++))

    # Call the process_repository function from cookstyle.sh
    if ! process_repository "${repo_url}" "${processed_count}" "${total_repos}"; then
        ((lint_failed_count++))
    fi
done

# === Report ===
log "INFO" "--- Summary ---"
log "INFO" "Processed ${processed_count} repositories."
log "INFO" "Found issues in ${lint_failed_count} repositories."

if [[ ${lint_failed_count} -gt 0 ]]; then
    log "WARN" "${lint_failed_count} repositories had cookstyle issues."
    exit 1
else
    log "INFO" "All repositories passed cookstyle checks!"
    exit 0
fi
