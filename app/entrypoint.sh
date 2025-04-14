#!/usr/bin/env bash
set -euo pipefail

# === Configuration ===
# Ensure required environment variables are set
: "${GITHUB_TOKEN:?ERROR: GITHUB_TOKEN is required}"
: "${TARGET_ORG:?ERROR: TARGET_ORG is required}"
: "${REPO_TOPIC:?ERROR: REPO_TOPIC is required}"
: "${CACHE_DIR:?ERROR: CACHE_DIR is required}"

# Set defaults for optional variables
DEFAULT_BRANCH_NAME="${DEFAULT_BRANCH_NAME:-main}"
GITHUB_API_ROOT="${GITHUB_API_ROOT:-api.github.com}"
API_PER_PAGE=100 # Number of results per API page

# === Setup ===
mkdir -p "$CACHE_DIR"
echo "--- Configuration ---"
echo "Target Org:   $TARGET_ORG"
echo "Repo Topic:   $REPO_TOPIC"
echo "Cache Dir:    $CACHE_DIR"
echo "Default Branch: $DEFAULT_BRANCH_NAME"
echo "GitHub API:   $GITHUB_API_ROOT"
echo "---------------------"

# === Functions ===
# Function to log messages
log() {
	echo "[$(date +'%Y-%m-%dT%H:%M:%SZ')] $1: $2"
}

# Function to fetch repositories from GitHub API, handles pagination
fetch_repo_urls() {
	local api_url="https://${GITHUB_API_ROOT}/search/repositories?q=org:${TARGET_ORG}+topic:${REPO_TOPIC}&per_page=${API_PER_PAGE}"
	local all_urls=()

	log "INFO" "Fetching repositories..."

	while [ -n "${api_url}" ]; do
		log "DEBUG" "Fetching page: ${api_url}"
		# Fetch headers and body separately to handle rate limits and errors gracefully
		local response_headers
		response_headers=$(mktemp)
		local response_body
		response_body=$(mktemp)

		local http_status
		http_status=$(curl -s -w "%{http_code}" -o "$response_body" \
			-D "$response_headers" \
			-H "Authorization: token $GITHUB_TOKEN" \
			-H "Accept: application/vnd.github.v3+json" \
			"$api_url")

		if [ "$http_status" -ne 200 ]; then
			log "ERROR" "GitHub API request failed with status $http_status. URL: $api_url"
			log "ERROR" "Response body: $(cat "$response_body")"
			rm -f "$response_headers" "$response_body"
			return 1
		fi

		# Extract clone URLs from the current page
		local page_urls
		page_urls=$(jq -r '.items[].clone_url' "$response_body")
		if [ -n "${page_urls}" ]; then
			while IFS= read -r url; do
				all_urls+=("$url")
			done <<< "${page_urls}"
		fi

		# Get the URL for the next page from the Link header
		local link_header
		link_header=$(grep -i '^Link:' "${response_headers}")
		api_url=$(echo "${link_header}" | sed -n 's/.*<\\([^>]*\\)>; rel="next".*/\\1/p')

		rm -f "${response_headers}" "${response_body}"

		# Optional: Add a small delay to avoid hitting rate limits aggressively
		# sleep 1
	done

	# Return urls by printing them space-separated
	echo "${all_urls[@]}"
}

# === Discover Repos ===
declare -a REPO_URLS
# Call function and read space-separated URLs into the array
read -r -a REPO_URLS <<< "$(fetch_repo_urls)"

if [[ $? -ne 0 ]]; then
	log "ERROR" "Failed to fetch repository list. Exiting."
	exit 1
fi

log "INFO" "Found ${#REPO_URLS[@]} repositories."
if [[ ${#REPO_URLS[@]} -eq 0 ]]; then
	log "WARN" "No repositories found matching the criteria. Exiting."
	exit 0
fi


# === Process Repos ===
lint_failed_count=0
processed_count=0
total_repos=${#REPO_URLS[@]}

for repo_url in "${REPO_URLS[@]}"; do
	((processed_count++))
	repo_name=$(basename "$repo_url" .git)
	repo_dir="$CACHE_DIR/$repo_name"
	log "INFO" "[$processed_count/$total_repos] Processing: ${repo_name}"

	# --- Cache Handling ---
	if [[ -d "${repo_dir}/.git" ]]; then
		log "INFO" "Updating existing clone: ${repo_dir}"
		cd "${repo_dir}" || { log "ERROR" "Cannot cd into ${repo_dir}"; ((lint_failed_count++)); continue; }
		# Use || true to prevent script exit if git commands fail initially
		if (git fetch origin "$DEFAULT_BRANCH_NAME" --quiet && git reset --hard "origin/$DEFAULT_BRANCH_NAME" --quiet); then
			log "DEBUG" "Update successful for ${repo_name}."
		else
			log "WARN" "Failed to update ${repo_name} cleanly. Attempting full re-clone."
			cd "$CACHE_DIR" || exit 1 # Exit if we can't cd back
			rm -rf "$repo_dir"
			if git clone --depth 1 --branch "$DEFAULT_BRANCH_NAME" "$repo_url" "$repo_dir" --quiet; then
				log "INFO" "Re-clone successful for ${repo_name}."
			else
				log "ERROR" "Failed to re-clone ${repo_name}. Skipping."
				((lint_failed_count++)) # Consider clone failure a lint failure
				continue
			fi
		fi
		cd "$CACHE_DIR" || exit 1 # Go back to cache dir base
	else
		log "INFO" "Cloning ${repo_name} into ${repo_dir}"
		if git clone --depth 1 --branch "$DEFAULT_BRANCH_NAME" "$repo_url" "$repo_dir" --quiet; then
			log "DEBUG" "Clone successful for ${repo_name}."
		else
			log "ERROR" "Failed to clone ${repo_name}. Skipping."
			((lint_failed_count++)) # Consider clone failure a lint failure
			continue
		fi
	fi

	# --- Linting ---
	log "INFO" "Running cookstyle on ${repo_name}..."
	# Run cookstyle, capture stdout and stderr, check exit code
	if output=$(cookstyle "${repo_dir}" 2>&1); then
		log "INFO" "OK: ${repo_name} passed cookstyle checks."
	else
		log "ERROR" "FAIL: ${repo_name} has cookstyle issues:"
		# Indent cookstyle output for clarity
		echo "$output" | sed 's/^/  /' # Output indented errors
		((lint_failed_count++))
	fi
	echo # Add a blank line for readability between repos
done

# === Report ===
log "INFO" "--- Summary ---"
log "INFO" "Processed $processed_count repositories."
if [[ "$lint_failed_count" -gt 0 ]]; then
	log "ERROR" "Linting finished with $lint_failed_count failure(s)."
	exit 1
else
	log "INFO" "All processed repositories passed cookstyle checks."
	exit 0
fi