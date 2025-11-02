#!/bin/bash

# Function to log messages with timestamps
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

# Define the URL and target paths for AutoPkg
AUTOPKG_URL="https://github.com/autopkg/autopkg/releases/download/v2.7.6/autopkg-2.7.6.pkg"
DOWNLOAD_PATH="/tmp/autopkg-2.7.6.pkg"

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
autopkg repo-add https://github.com/autopkg/jc0b-recipes.git
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

# Run the parent recipe directly from jc0b-recipes
# We'll rename the package afterward to match our naming convention
log "Verifying parent recipe exists..."
if ! autopkg list-recipes 2>&1 | grep -q "fleetctl.pkg"; then
    log "ERROR: Parent recipe fleetctl.pkg not found in list-recipes"
    log "Available fleetctl recipes:"
    autopkg list-recipes 2>&1 | grep -i fleetctl || log "No fleetctl recipes found"
    exit 1
fi
log "Parent recipe found: fleetctl.pkg (com.github.jc0b.pkg.fleetctl)"

# Run the AutoPkg recipe from jc0b-recipes
# This creates fleetctl-v${VERSION}.pkg - we'll rename it afterward
log "Running the AutoPkg recipe to create the Fleet package..."
CACHE_DIR="/Users/runner/Library/AutoPkg/Cache/com.github.jc0b.pkg.fleetctl"
# Use --ignore-parent-trust-verification-errors to avoid interactive prompts
# Redirect stdin from /dev/null to prevent any interactive prompts
log "Executing: autopkg run -vv --ignore-parent-trust-verification-errors fleetctl.pkg"
AUTOPKG_OUTPUT=$(GITHUB_TOKEN="$PACKAGE_AUTOMATION_TOKEN" autopkg run -vv --ignore-parent-trust-verification-errors fleetctl.pkg </dev/null 2>&1)
log "AutoPkg Output:"
echo "$AUTOPKG_OUTPUT"

# Check for fleetctl binary and fix path structure if needed
if [[ "$AUTOPKG_OUTPUT" == *"Error processing path"* ]]; then
    log "AutoPkg recipe failed. Attempting to fix fleetctl binary path..."
    
    # Show extracted contents for debugging
    log "Extracted contents of fleetctl directory:"
    find "$CACHE_DIR/fleetctl" -type f | sort
    
    # Find the actual fleetctl binary
    EXTRACTED_FLEETCTL=$(find "$CACHE_DIR/fleetctl" -type f -name "fleetctl" | head -n 1)
    
    if [ -n "$EXTRACTED_FLEETCTL" ]; then
        log "Found fleetctl binary at: $EXTRACTED_FLEETCTL"
        
        # Create the expected directory structure
        mkdir -p "$CACHE_DIR/fleetctl/fleetctl_v${LATEST_VERSION}_macos_all"
        cp "$EXTRACTED_FLEETCTL" "$CACHE_DIR/fleetctl/fleetctl_v${LATEST_VERSION}_macos_all/fleetctl"
        chmod +x "$CACHE_DIR/fleetctl/fleetctl_v${LATEST_VERSION}_macos_all/fleetctl"
        
        log "Copied fleetctl binary to expected location"
        
        # Try running AutoPkg again
        log "Running AutoPkg recipe again with fixed path..."
        AUTOPKG_OUTPUT=$(GITHUB_TOKEN="$PACKAGE_AUTOMATION_TOKEN" autopkg run -vv --ignore-parent-trust-verification-errors fleetctl.pkg </dev/null 2>&1)
        log "AutoPkg Output (second attempt):"
        echo "$AUTOPKG_OUTPUT"
    else
        # Try to find any binary in the extracted files
        log "Could not find fleetctl binary by name. Looking for any executable file..."
        EXTRACTED_FILES=$(find "$CACHE_DIR/fleetctl" -type f -perm -u+x | head -n 1)
        
        if [ -n "$EXTRACTED_FILES" ]; then
            log "Found possible binary at: $EXTRACTED_FILES"
            mkdir -p "$CACHE_DIR/fleetctl/fleetctl_v${LATEST_VERSION}_macos_all"
            cp "$EXTRACTED_FILES" "$CACHE_DIR/fleetctl/fleetctl_v${LATEST_VERSION}_macos_all/fleetctl"
            chmod +x "$CACHE_DIR/fleetctl/fleetctl_v${LATEST_VERSION}_macos_all/fleetctl"
            
            log "Copied possible binary to expected location"
            
            # Try running AutoPkg again
            log "Running AutoPkg recipe again with fixed path..."
            AUTOPKG_OUTPUT=$(GITHUB_TOKEN="$PACKAGE_AUTOMATION_TOKEN" autopkg run -vv --ignore-parent-trust-verification-errors fleetctl.pkg </dev/null 2>&1)
            log "AutoPkg Output (third attempt):"
            echo "$AUTOPKG_OUTPUT"
        else
            log "Could not find any executable in extracted files!"
            exit 1
        fi
    fi
fi

# Use the latest version we got from GitHub API
DETECTED_VERSION="${LATEST_VERSION}"
log "Using version: $DETECTED_VERSION"

# Find the created package - jc0b's recipe creates fleetctl-${VERSION}.pkg (with hyphen, no 'v')
log "Searching for package in cache directory..."
ORIGINAL_PACKAGE=$(find "$CACHE_DIR" -name "fleetctl-*.pkg" -type f | head -n 1)

if [ -z "$ORIGINAL_PACKAGE" ]; then
    log "Package not found with pattern fleetctl-*.pkg, trying broader search..."
    ORIGINAL_PACKAGE=$(find "$CACHE_DIR" -name "fleetctl*.pkg" -type f | head -n 1)
fi

if [ -z "$ORIGINAL_PACKAGE" ]; then
        # Manual package creation as a last resort
        log "No package file found. Attempting manual package creation..."
        
        # Create a basic package structure
        PKG_ROOT="$CACHE_DIR/pkg_root"
        mkdir -p "$PKG_ROOT/usr/local/bin"
        
        # Find any fleetctl binary
        BINARY_PATH=$(find "$CACHE_DIR" -name "fleetctl" -type f | head -n 1)
        
        if [ -n "$BINARY_PATH" ]; then
            cp "$BINARY_PATH" "$PKG_ROOT/usr/local/bin/"
            chmod +x "$PKG_ROOT/usr/local/bin/fleetctl"
            
            # Create package with correct naming
            ORIGINAL_PACKAGE="$CACHE_DIR/fleetctl_v${DETECTED_VERSION}.pkg"
            pkgbuild --root "$PKG_ROOT" --identifier "com.fleetdm.fleetctl" --version "$DETECTED_VERSION" "$ORIGINAL_PACKAGE"
            
            if [ $? -ne 0 ]; then
                log "Manual package creation failed!"
                ls -la "$CACHE_DIR"
                exit 1
            fi
        else
            log "No fleetctl binary found! Directory contents:"
            ls -la "$CACHE_DIR"
            exit 1
        fi
fi

if [ -n "$ORIGINAL_PACKAGE" ]; then
    log "Found original package at: $ORIGINAL_PACKAGE"
fi

# Rename package to match our naming convention (fleetctl_v${VERSION}.pkg instead of fleetctl-v${VERSION}.pkg)
TARGET_PACKAGE="$CACHE_DIR/fleetctl_v${DETECTED_VERSION}.pkg"
if [ "$ORIGINAL_PACKAGE" != "$TARGET_PACKAGE" ]; then
    log "Renaming package from $(basename "$ORIGINAL_PACKAGE") to $(basename "$TARGET_PACKAGE")"
    mv "$ORIGINAL_PACKAGE" "$TARGET_PACKAGE"
    if [ $? -ne 0 ]; then
        log "ERROR: Failed to rename package"
        exit 1
    fi
fi

PACKAGE_FILE="$TARGET_PACKAGE"
log "Final package at: $PACKAGE_FILE"

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
