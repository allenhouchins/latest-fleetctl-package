#!/bin/bash

# Define the URL and target paths for AutoPkg
AUTOPKG_URL="https://github.com/autopkg/autopkg/releases/download/v2.7.3/autopkg-2.7.3.pkg"
DOWNLOAD_PATH="/tmp/autopkg-2.7.3.pkg"

# Download and install AutoPkg
echo "Downloading AutoPkg package..."
curl -L -o "$DOWNLOAD_PATH" "$AUTOPKG_URL"

if [ $? -ne 0 ]; then
    echo "Download failed!"
    exit 1
fi

if ! command -v autopkg &> /dev/null; then
    echo "Installing AutoPkg..."
    sudo installer -pkg "$DOWNLOAD_PATH" -target /
    if [ $? -ne 0 ]; then
        echo "AutoPkg installation failed!"
        exit 1
    fi
fi

# Install Homebrew if needed
if ! command -v brew &> /dev/null; then
    echo "Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    brew install git
fi

# Add required AutoPkg repos
echo "Adding required AutoPkg repos..."
autopkg repo-add homebysix-recipes
autopkg repo-add https://github.com/allenhouchins/fleet-stuff.git

# Set up GitHub token for AutoPkg
defaults write com.github.autopkg GITHUB_TOKEN -string "$PACKAGE_AUTOMATION_TOKEN"

# Run the AutoPkg recipe for Fleet
echo "Running the AutoPkg recipe to create the Fleet package..."
autopkg run -v fleetctl.pkg

# Find the created package in the correct location
PACKAGE_FILE=$(ls /Users/runner/Library/AutoPkg/Cache/github.fleetdm.fleetctl.pkg.recipe/fleetctl_v*.pkg | tail -n 1)

if [ ! -f "$PACKAGE_FILE" ]; then
    echo "Package not found at expected location!"
    echo "Listing directory contents:"
    ls -la /Users/runner/Library/AutoPkg/Cache/github.fleetdm.fleetctl.pkg.recipe/
    exit 1
fi

echo "Found package at: $PACKAGE_FILE"

# Calculate package checksum
PACKAGE_SHA256=$(shasum -a 256 "${PACKAGE_FILE}" | awk '{print $1}')

# Create GitHub release
echo "Creating GitHub release..."
RELEASE_TAG="${FLEET_VERSION}"
RELEASE_NAME="Fleet ${FLEET_VERSION} Package"
RELEASE_BODY="Fleet package version ${FLEET_VERSION}

Package SHA256: ${PACKAGE_SHA256}"

# Create the release
RELEASE_RESPONSE=$(curl -L \
  -X POST \
  -H "Accept: application/vnd.github+json" \
  -H "Authorization: Bearer ${PACKAGE_AUTOMATION_TOKEN}" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  "https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/releases" \
  -d "{
    \"tag_name\":\"${RELEASE_TAG}\",
    \"target_commitish\":\"main\",
    \"name\":\"${RELEASE_NAME}\",
    \"body\":\"${RELEASE_BODY}\",
    \"draft\":false,
    \"prerelease\":false,
    \"generate_release_notes\":false
  }")

# Get the release ID from the response
RELEASE_ID=$(echo "${RELEASE_RESPONSE}" | jq -r '.id')

if [ -z "${RELEASE_ID}" ] || [ "${RELEASE_ID}" = "null" ]; then
    echo "Failed to create release. Response:"
    echo "${RELEASE_RESPONSE}"
    exit 1
fi

echo "Created release with ID: ${RELEASE_ID}"

# Upload the package file
echo "Uploading package to release..."
PACKAGE_NAME=$(basename "${PACKAGE_FILE}")
curl -L \
  -X POST \
  -H "Accept: application/vnd.github+json" \
  -H "Authorization: Bearer ${PACKAGE_AUTOMATION_TOKEN}" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  -H "Content-Type: application/octet-stream" \
  "https://uploads.github.com/repos/${REPO_OWNER}/${REPO_NAME}/releases/${RELEASE_ID}/assets?name=${PACKAGE_NAME}" \
  --data-binary "@${PACKAGE_FILE}"

if [ $? -ne 0 ]; then
    echo "Failed to upload package to release"
    exit 1
fi

echo "Successfully uploaded package to release"

# Clean up the GitHub token
defaults delete com.github.autopkg GITHUB_TOKEN