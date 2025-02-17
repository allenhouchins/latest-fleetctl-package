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

# Check package size for Git LFS
PKGSIZE=$(stat -f%z "${PACKAGE_FILE}")
if [ "$PKGSIZE" -gt "104857600" ]; then
    echo "Installing git-lfs"
    brew install git-lfs
    export add_git_lfs="git lfs install; git lfs track *.pkg; git add .gitattributes"
else
    export add_git_lfs="echo 'git lfs not needed. Continuing...'"
fi

# Configure git
git config --global user.email "$USER_EMAIL"
git config --global user.name "$USER_NAME"

# Clone repo and add package
echo "Cloning repository with token..."
git clone "https://$PACKAGE_AUTOMATION_TOKEN@github.com/$REPO_OWNER/$REPO_NAME.git" /tmp/repo || {
    echo "Failed to clone repository"
    exit 1
}

cp "${PACKAGE_FILE}" /tmp/repo
cd /tmp/repo
eval "$add_git_lfs"

# Commit and push
git add $(basename "$PACKAGE_FILE")
git commit -m "Add Fleet package version ${FLEET_VERSION}"
echo "Pushing to repository..."
git push origin HEAD:main || {
    echo "Failed to push to repository"
    exit 1
}

# Cleanup
rm -rf /tmp/repo
# Clean up the GitHub token
defaults delete com.github.autopkg GITHUB_TOKEN