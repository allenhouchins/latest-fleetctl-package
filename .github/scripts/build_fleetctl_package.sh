#!/bin/bash

set -euo pipefail

log() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"; }

cleanup() {
  defaults delete com.github.autopkg GITHUB_TOKEN >/dev/null 2>&1 || true
}
trap cleanup EXIT

# Prefer ephemeral GITHUB_TOKEN, fall back to PACKAGE_AUTOMATION_TOKEN if provided
TOKEN="${GITHUB_TOKEN:-${PACKAGE_AUTOMATION_TOKEN:-}}"

# Install AutoPkg if not present
AUTOPKG_URL="https://github.com/autopkg/autopkg/releases/download/v2.7.3/autopkg-2.7.3.pkg"
DOWNLOAD_PATH="/tmp/autopkg-2.7.3.pkg"

log "Ensuring AutoPkg is installed..."
if ! command -v autopkg >/dev/null 2>&1; then
  log "Downloading AutoPkg..."
  curl -fsSL -o "$DOWNLOAD_PATH" "$AUTOPKG_URL"
  log "Installing AutoPkg..."
  sudo installer -pkg "$DOWNLOAD_PATH" -target /
fi

log "Configuring AutoPkg and adding required repos..."
defaults write com.github.autopkg GITHUB_TOKEN -string "$TOKEN"

# Add community processors and recipe source
autopkg repo-add jazzace-recipes || true
autopkg repo-add https://github.com/allenhouchins/latest-fleetctl-package.git || true

log "Running AutoPkg recipe to build fleetctl pkg (unsigned)..."
GITHUB_TOKEN="$TOKEN" autopkg run -vv com.github.jc0b.pkg.fleetctl

# Locate the produced package in the standard cache path
CACHE_DIR="$HOME/Library/AutoPkg/Cache/com.github.jc0b.pkg.fleetctl"
if [ ! -d "$CACHE_DIR" ]; then
  echo "Cache directory not found: $CACHE_DIR" >&2
  exit 1
fi

# Pick the most recent pkg (exclude any signed variants just in case)
PKG_PATH=$(ls -t "$CACHE_DIR"/fleetctl_v*.pkg 2>/dev/null | grep -v "_signed\.pkg" | head -n 1 || true)
if [ -z "${PKG_PATH}" ]; then
  echo "No pkg found in $CACHE_DIR" >&2
  ls -la "$CACHE_DIR" || true
  exit 1
fi

log "Built pkg: $PKG_PATH"
echo "$PKG_PATH" > "$GITHUB_WORKSPACE/unsigned_pkg_path.txt"

