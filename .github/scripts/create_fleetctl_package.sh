#!/bin/bash

# Enable error handling
set -euo pipefail

# Function to log messages with timestamps
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

# Function to check command existence
check_command() {
    if ! command -v "$1" &> /dev/null; then
        log "Error: $1 is not installed"
        return 1
    fi
}

# Function to verify recipe existence
verify_recipe() {
    local recipe_id="$1"
    autopkg info "$recipe_id" &> /dev/null || {
        log "Error: Recipe $recipe_id not found"
        log "Available recipes:"
        autopkg list-recipes
        return 1
    }
}

# Define constants
AUTOPKG_URL="https://github.com/autopkg/autopkg/releases/download/v2.7.3/autopkg-2.7.3.pkg"
DOWNLOAD_PATH="/tmp/autopkg-2.7.3.pkg"
RECIPE_ID="com.github.jc0b.pkg.fleetctl"
CACHE_DIR="/Users/runner/Library/AutoPkg/Cache/com.github.jc0b.pkg.fleetctl"

# Download and install AutoPkg if not present
if ! check_command autopkg; then
    log "Downloading AutoPkg package..."
    curl -L -o "$DOWNLOAD_PATH" "$AUTOPKG_URL" || {
        log "Failed to download AutoPkg"
        exit 1
    }

    log "Installing AutoPkg..."
    sudo installer -pkg "$DOWNLOAD_PATH" -target / || {
        log "AutoPkg installation failed"
        exit 1
    }
fi

# Install Homebrew if needed
if ! check_command brew; then
    log "Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    brew install git jq
fi

# Clean up any existing AutoPkg cache
log "Cleaning AutoPkg cache..."
rm -rf ~/Library/AutoPkg/Cache/*

# Add required AutoPkg repos
log "Adding required AutoPkg repos..."
autopkg repo-add jazzace-recipes || log "Warning: Failed to add jazzace-recipes"
autopkg repo-add https://github.com/allenhouchins/fleet-stuff.git || log "Warning: Failed to add fleet-stuff repo"

# Update repos to ensure we have the latest recipes
log "Updating AutoPkg repos..."
autopkg repo-update all

# Set up GitHub token for AutoPkg
if [ -z "${PACKAGE_AUTOMATION_TOKEN:-}" ]; then
    log "Error: PACKAGE_AUTOMATION_TOKEN environment variable is not set"
    exit 1
fi

defaults write com.github.autopkg GITHUB_TOKEN -string "$PACKAGE_AUTOMATION_TOKEN"

# Verify recipe exists before running
verify_recipe "$RECIPE_ID" || exit 1

# Run the AutoPkg recipe with verbose output and capture version
log "Running the AutoPkg recipe to create the Fleet package..."
AUTOPKG_OUTPUT=$(autopkg run -vv "$RECIPE_ID" 2>&1)

# Check if the package was created
if [ -d "$CACHE_DIR" ]; then
    # Get the version from the autopkg output
    DETECTED_VERSION=$(echo "$AUTOPKG_OUTPUT" | grep "version:" | tail -n1 | awk '{print $2}')
    if [ -z "$DETECTED_VERSION" ]; then
        log "Error: Could not detect version from AutoPkg output"
        exit 1
    fi
    log "Detected version from AutoPkg: $DETECTED_VERSION"

    PACKAGE_FILE="$CACHE_DIR/fleetctl_v${DETECTED_VERSION}.pkg"
    
    if [ ! -f "$PACKAGE_FILE" ]; then
        log "Error: Package not found at: $PACKAGE_FILE"
        log "Listing cache directory contents:"
        ls -la "$CACHE_DIR"
        exit 1
    fi
else
    log "Error: Cache directory not found at: $CACHE_DIR"
    log "AutoPkg Output:"
    echo "$AUTOPKG_OUTPUT"
    exit 1
fi

log "Found package at: $PACKAGE_FILE"

# Calculate package checksum
PACKAGE_SHA256=$(shasum -a 256 "${PACKAGE_FILE}" | awk '{print $1}')

# Create GitHub release
log "Creating GitHub release..."
PACKAGE_NAME="fleetctl_v${DETECTED_VERSION}.pkg"
RELEASE_TAG="v${DETECTED_VERSION}"

log "Debug info:"
log "Package name: $PACKAGE_NAME"
log "Release tag: $RELEASE_TAG"
log "Package SHA256: $PACKAGE_SHA256"

# Create release data
cat > release.json << EOF
{
  "tag_name": "${RELEASE_TAG}",
  "target_commitish": "main",
  "name": "${PACKAGE_NAME}",
  "body": "Package SHA256: ${PACKAGE_SHA256}",
  "draft": false,
  "prerelease": false,
  "generate_release_notes": false
}
EOF

log "Creating release with data:"
cat release.json

# Verify required environment variables
if [ -z "${REPO_OWNER:-}" ] || [ -z "${REPO_NAME:-}" ]; then
    log "Error: REPO_OWNER and REPO_NAME environment variables must be set"
    exit 1
fi

# Create the release
RELEASE_RESPONSE=$(curl -L \
    -X POST \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: Bearer ${PACKAGE_AUTOMATION_TOKEN}" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/releases" \
    -d @release.json)

# Get the release ID from the response
RELEASE_ID=$(echo "${RELEASE_RESPONSE}" | jq -r '.id')

if [ -z "${RELEASE_ID}" ] || [ "${RELEASE_ID}" = "null" ]; then
    log "Error: Failed to create release. Response:"
    echo "${RELEASE_RESPONSE}" | jq .
    exit 1
fi

log "Created release with ID: ${RELEASE_ID}"

# Upload the package file
log "Uploading package to release..."
UPLOAD_RESPONSE=$(curl -L \
    -X POST \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: Bearer ${PACKAGE_AUTOMATION_TOKEN}" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    -H "Content-Type: application/octet-stream" \
    "https://uploads.github.com/repos/${REPO_OWNER}/${REPO_NAME}/releases/${RELEASE_ID}/assets?name=${PACKAGE_NAME}" \
    --data-binary "@${PACKAGE_FILE}")

UPLOAD_STATUS=$?
if [ $UPLOAD_STATUS -ne 0 ]; then
    log "Error: Failed to upload package to release. Status: ${UPLOAD_STATUS}"
    log "Response: ${UPLOAD_RESPONSE}"
    exit 1
fi

log "Successfully uploaded package to release"

# Clean up
rm -f release.json
defaults delete com.github.autopkg GITHUB_TOKEN

log "Script completed successfully"