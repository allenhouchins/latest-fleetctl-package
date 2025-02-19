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
    log "Verifying recipe: $recipe_id"
    
    # List all available recipes
    log "Available recipes:"
    autopkg list-recipes
    
    # Try to get recipe info
    if ! autopkg info "$recipe_id" 2>&1; then
        log "Error: Recipe $recipe_id not found"
        log "Searching for recipe files..."
        find ~/Library/AutoPkg/RecipeRepos -type f -name "*.recipe.yaml" -o -name "*.recipe"
        return 1
    fi
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

# List all recipe paths
log "Current AutoPkg search path:"
autopkg repo-list

# Show contents of recipe repos
log "Listing contents of recipe repos:"
ls -R ~/Library/AutoPkg/RecipeRepos/

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
AUTOPKG_OUTPUT=$(autopkg run -vvv "$RECIPE_ID" 2>&1) || {
    log "Error running AutoPkg recipe. Output:"
    echo "$AUTOPKG_OUTPUT"
    log "Recipe not found. Checking recipe locations..."
    find ~/Library/AutoPkg/RecipeRepos -type f -name "*.recipe.yaml" -o -name "*.recipe"
    exit 1
}

echo "AutoPkg Output:"
echo "$AUTOPKG_OUTPUT"

# Rest of the script remains the same...
# (Previous GitHub release creation and upload code)

log "Script completed successfully"