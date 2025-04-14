#!/usr/bin/env bash
# =============================================================================
# GitHub Cookstyle Runner - GitHub API Module
# =============================================================================
#
# This module provides functions for interacting with the GitHub API, including
# repository discovery, pull request creation, and label management.
#
# Required environment variables:
#   - GITHUB_TOKEN: Authentication token for GitHub API
#   - GCR_DESTINATION_REPO_OWNER: Target GitHub organization/user
#   - GCR_DESTINATION_REPO_TOPICS: Repository topics to filter by (comma-separated)
#   - GCR_BRANCH_NAME: Branch name for cookstyle fixes
#   - GCR_DEFAULT_GIT_BRANCH: Default branch name (usually 'main')
#   - GCR_PULL_REQUEST_TITLE: Title for generated pull requests
#   - GITHUB_API_ROOT: GitHub API URL (defaults to api.github.com)
#   - API_PER_PAGE: Number of results per API page (defaults to 100)
#
# Usage:
#   source "path/to/github.sh"
#   repo_urls=$(fetch_repo_urls)
#   create_pull_request "repo-name"

# Library functions for GitHub API operations - will only be sourced, not run standalone
[[ -z "${GCR_PULL_REQUEST_LABELS}" ]] && GCR_PULL_REQUEST_LABELS="${GCR_PULL_REQUEST_LABELS:-}"
[[ -z "${GCR_DESTINATION_REPO_TOPICS}" ]] && GCR_DESTINATION_REPO_TOPICS="${GCR_DESTINATION_REPO_TOPICS:-}"
[[ -z "${GITHUB_API_ROOT}" ]] && GITHUB_API_ROOT="${GITHUB_API_ROOT:-api.github.com}"
[[ -z "${API_PER_PAGE}" ]] && API_PER_PAGE="${API_PER_PAGE:-100}"

# Source logging
# shellcheck source=./app/lib/logging.sh
source "$(dirname "$0")/logging.sh"

# Function to fetch repositories from GitHub API, handles pagination
fetch_repo_urls() {
    # Parse comma-separated topics
    IFS=',' read -ra TOPICS <<< "${GCR_DESTINATION_REPO_TOPICS}"
    local topic_query=""
    for topic in "${TOPICS[@]}"; do
        topic_query+="+topic:${topic}"
    done

    local api_url="https://${GITHUB_API_ROOT}/search/repositories?q=org:${GCR_DESTINATION_REPO_OWNER}${topic_query}&per_page=${API_PER_PAGE}"
    local all_urls=()

    log "INFO" "Fetching repositories..."

    while [[ -n "${api_url}" ]]; do
        log "DEBUG" "Fetching page: ${api_url}"
        # Fetch headers and body separately to handle rate limits and errors gracefully
        local response_headers
        response_headers=$(mktemp)
        local response_body
        response_body=$(mktemp)

        local http_status
        http_status=$(curl -s -w "%{http_code}" -o "${response_body}" \
            -D "${response_headers}" \
            -H "Authorization: token ${GITHUB_TOKEN}" \
            -H "Accept: application/vnd.github.v3+json" \
            "${api_url}")

        if [[ "${http_status}" -ne 200 ]]; then
            log "ERROR" "GitHub API request failed with status ${http_status}. URL: ${api_url}"
            log "ERROR" "Response body: $(cat "${response_body}")"
            rm -f "${response_headers}" "${response_body}"
            return 1
        fi

        # Extract clone URLs from the current page
        local page_urls
        page_urls=$(jq -r '.items[].clone_url' "${response_body}")
        if [[ -n "${page_urls}" ]]; then
            while IFS= read -r url; do
                all_urls+=("${url}")
            done <<< "${page_urls}"
        fi

        # Get the URL for the next page from the Link header
        local link_header
        link_header=$(grep -i '^Link:' "${response_headers}" || echo "")
        api_url=$(echo "${link_header}" | sed -n 's/.*<\([^>]*\)>; rel="next".*/\1/p')

        rm -f "${response_headers}" "${response_body}"
    done

    # Return urls by printing them space-separated
    echo "${all_urls[@]}"
}

# Function to create a pull request for a repository
create_pull_request() {
    local repo_name="$1"

    # Create PR data JSON
    local pr_data="{\"title\":\"${GCR_PULL_REQUEST_TITLE}\",\"head\":\"${GCR_BRANCH_NAME}\",\"base\":\"${GCR_DEFAULT_GIT_BRANCH}\"}"

    log "DEBUG" "Creating PR with data: ${pr_data}"
    local pr_url="https://${GITHUB_API_ROOT}/repos/${GCR_DESTINATION_REPO_OWNER}/${repo_name}/pulls"

    local pr_response
    pr_response=$(curl -s -X POST "${pr_url}" \
        -H "Authorization: token ${GITHUB_TOKEN}" \
        -H "Accept: application/vnd.github.v3+json" \
        -d "${pr_data}")

    local pr_html_url
    pr_html_url=$(echo "${pr_response}" | jq -r '.html_url')

    if [[ "${pr_html_url}" != "null" ]]; then
        log "INFO" "Pull request created: ${pr_html_url}"

        # Add labels if provided
        if [[ -n "${GCR_PULL_REQUEST_LABELS}" ]]; then
            local pr_number
            pr_number=$(echo "${pr_response}" | jq -r '.number')

            # Parse comma-separated labels into JSON array
            IFS=',' read -ra LABELS <<< "${GCR_PULL_REQUEST_LABELS}"
            local labels_json="["
            for label in "${LABELS[@]}"; do
                labels_json+="\"${label}\","
            done
            labels_json="${labels_json%,}]" # Remove trailing comma and close array

            # Add labels to PR
            local labels_url="https://${GITHUB_API_ROOT}/repos/${GCR_DESTINATION_REPO_OWNER}/${repo_name}/issues/${pr_number}/labels"
            local labels_response
            labels_response=$(curl -s -X POST "${labels_url}" \
                -H "Authorization: token ${GITHUB_TOKEN}" \
                -H "Accept: application/vnd.github.v3+json" \
                -d "{\"labels\":${labels_json}}")

            log "INFO" "Added labels to PR: ${GCR_PULL_REQUEST_LABELS}"
            log "DEBUG" "Labels response: ${labels_response}"
        fi

        return 0
    else
        log "ERROR" "Failed to create PR: $(echo "${pr_response}" | jq -r '.message')"
        return 1
    fi
}

# Export functions so they're available when sourced
export -f fetch_repo_urls
export -f create_pull_request
