#!/bin/bash

# Function to log messages with timestamps
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

# Define the URL and target paths for AutoPkg
AUTOPKG_URL="https://github.com/autopkg/autopkg/releases/download/v2.7.3/autopkg-2.7.3.pkg"
DOWNLOAD_PATH="/tmp/autopkg-2.7.3.pkg"

# Download and install AutoPkg
log "Downloading AutoPkg package..."
curl -L -o "$DOWNLOAD_PATH" "$AUTOPKG_URL"

if [ $? -ne 0 ]; then
    log "Download failed!"
    exit 1
fi

if ! command -v autopkg &> /dev/null; then
    log "Installing AutoPkg..."
    sudo installer -pkg "$DOWNLOAD_PATH" -target /
    if [ $? -ne 0 ]; then
        log "AutoPkg installation failed!"
        exit 1
    fi
fi

# Install Homebrew if needed
if ! command -v brew &> /dev/null; then
    log "Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    brew install git jq
fi

# Add required AutoPkg repos
log "Adding required AutoPkg repos..."
autopkg repo-add jazzace-recipes
autopkg repo-add https://github.com/allenhouchins/latest-fleetctl-package.git

# Set up GitHub token for AutoPkg
defaults write com.github.autopkg GITHUB_TOKEN -string "$PACKAGE_AUTOMATION_TOKEN"

# Get the version directly from GitHub API first
LATEST_VERSION=$(curl -L \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: Bearer ${PACKAGE_AUTOMATION_TOKEN}" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "https://api.github.com/repos/fleetdm/fleet/releases/latest" | jq -r '.tag_name' | sed 's/fleet-v//')

log "Latest version from GitHub API: ${LATEST_VERSION}"

# Run the AutoPkg recipe for Fleet with verbose output
log "Running the AutoPkg recipe to create the Fleet package..."
AUTOPKG_OUTPUT=$(GITHUB_TOKEN="$PACKAGE_AUTOMATION_TOKEN" autopkg run -vv com.github.jc0b.pkg.fleetctl)
log "AutoPkg Output:"
echo "$AUTOPKG_OUTPUT"

# Use the latest version we got from GitHub API
DETECTED_VERSION="${LATEST_VERSION}"
log "Using version: $DETECTED_VERSION"

# Find the created package in the correct location
CACHE_DIR="/Users/runner/Library/AutoPkg/Cache/com.github.jc0b.pkg.fleetctl"
PACKAGE_FILE="$CACHE_DIR/fleetctl_v${DETECTED_VERSION}.pkg"

if [ ! -f "$PACKAGE_FILE" ]; then
    log "Package not found at: $PACKAGE_FILE"
    log "Searching for package in cache directory..."
    PACKAGE_FILE=$(find "$CACHE_DIR" -name "fleetctl_v*.pkg" -type f)
    if [ -z "$PACKAGE_FILE" ]; then
        log "No package file found! Directory contents:"
        ls -la "$CACHE_DIR"
        exit 1
    fi
    log "Found package at: $PACKAGE_FILE"
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

# Check if release exists
EXISTING_RELEASE=$(curl -L \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: Bearer ${PACKAGE_AUTOMATION_TOKEN}" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/releases/tags/${RELEASE_TAG}")

RELEASE_ID=$(echo "${EXISTING_RELEASE}" | jq -r '.id')

if [ "${RELEASE_ID}" = "null" ]; then
    log "Creating new release..."
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
        log "Failed to create release. Response:"
        echo "${RELEASE_RESPONSE}" | jq .
        exit 1
    fi
    log "Created new release with ID: ${RELEASE_ID}"
else
    log "Release already exists with ID: ${RELEASE_ID}"
fi

# Check for existing assets
EXISTING_ASSETS=$(curl -L \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: Bearer ${PACKAGE_AUTOMATION_TOKEN}" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/releases/${RELEASE_ID}/assets")

EXISTING_ASSET_ID=$(echo "${EXISTING_ASSETS}" | jq -r ".[] | select(.name==\"${PACKAGE_NAME}\") | .id")

# Delete existing asset if it exists
if [ ! -z "${EXISTING_ASSET_ID}" ] && [ "${EXISTING_ASSET_ID}" != "null" ]; then
    log "Deleting existing asset with ID: ${EXISTING_ASSET_ID}"
    curl -L \
        -X DELETE \
        -H "Accept: application/vnd.github+json" \
        -H "Authorization: Bearer ${PACKAGE_AUTOMATION_TOKEN}" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/releases/assets/${EXISTING_ASSET_ID}"
fi

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
    log "Failed to upload package to release. Status: ${UPLOAD_STATUS}"
    log "Response: ${UPLOAD_RESPONSE}"
    exit 1
fi

log "Successfully uploaded package to release"

# Clean up
rm -f release.json
defaults delete com.github.autopkg GITHUB_TOKEN