#!/bin/bash

set -euo pipefail

log() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"; }

cleanup() {
  rm -f release.json >/dev/null 2>&1 || true
}
trap cleanup EXIT

# Inputs
TOKEN="${GITHUB_TOKEN:-${PACKAGE_AUTOMATION_TOKEN:-}}"
DEVELOPER_ID_INSTALLER="${DEVELOPER_ID_INSTALLER:?DEVELOPER_ID_INSTALLER is required}"

# Derive repo owner/name from GitHub context if not explicitly provided
REPO_SLUG="${GITHUB_REPOSITORY:-}"
if [ -z "$REPO_SLUG" ]; then
  # Allow optional overrides for edge cases
  if [ -n "${REPO_OWNER:-}" ] && [ -n "${REPO_NAME:-}" ]; then
    REPO_SLUG="${REPO_OWNER}/${REPO_NAME}"
  else
    echo "GITHUB_REPOSITORY not set and REPO_OWNER/REPO_NAME not provided" >&2
    exit 1
  fi
fi
REPO_OWNER="${REPO_SLUG%/*}"
REPO_NAME="${REPO_SLUG#*/}"

PKG_DIR="${1:-dist}"
if [ ! -d "$PKG_DIR" ]; then
  echo "Package directory not found: $PKG_DIR" >&2
  exit 1
fi

# Pick the newest pkg from the artifact directory
PKG=$(ls -t "$PKG_DIR"/*.pkg 2>/dev/null | head -n 1 || true)
if [ -z "$PKG" ]; then
  echo "No pkg files found in $PKG_DIR" >&2
  exit 1
fi

log "Unsigned pkg: $PKG"

# Derive version from filename (expects fleetctl_vX.Y.Z.pkg)
BASENAME=$(basename "$PKG")
VERSION=$(echo "$BASENAME" | sed -E 's/^fleetctl_v([0-9]+\.[0-9]+\.[0-9]+)\.pkg$/\1/')
if [[ -z "$VERSION" || "$VERSION" == "$BASENAME" ]]; then
  echo "Failed to derive version from $BASENAME" >&2
  exit 1
fi


# Sign with Developer ID Installer identity (keychain is set by the import action)
log "Signing package with identity: $DEVELOPER_ID_INSTALLER"
# productsign requires a different output path; sign to a temp file then replace original
TEMP_SIGNED=$(mktemp "${PKG_DIR}/fleetctl_v${VERSION}.pkg.XXXX")
productsign --sign "$DEVELOPER_ID_INSTALLER" "$PKG" "$TEMP_SIGNED"
mv -f "$TEMP_SIGNED" "$PKG"

log "Verifying signature..."
pkgutil --check-signature "$PKG"

# Compute checksum and prepare release metadata
PACKAGE_SHA256=$(shasum -a 256 "$PKG" | awk '{print $1}')
RELEASE_TAG="v${VERSION}"
ASSET_NAME=$(basename "$PKG")

cat > release.json << EOF
{
  "tag_name": "${RELEASE_TAG}",
  "target_commitish": "main",
  "name": "fleetctl_v${VERSION}.pkg",
  "body": "Package SHA256: ${PACKAGE_SHA256}",
  "draft": false,
  "prerelease": false,
  "generate_release_notes": false
}
EOF

# Optionally skip publishing (for branch testing)
if [ "${PUBLISH_RELEASE:-true}" != "true" ]; then
  log "PUBLISH_RELEASE is not true; skipping release upload. Signed pkg at: $PKG"
  exit 0
fi

log "Ensuring release exists..."
EXISTING_RELEASE=$(curl -fsSL \
  -H "Accept: application/vnd.github+json" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  "https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/releases/tags/${RELEASE_TAG}" || true)

RELEASE_ID=$(echo "${EXISTING_RELEASE}" | jq -r '.id' 2>/dev/null || echo "null")
if [ -z "$RELEASE_ID" ] || [ "$RELEASE_ID" = "null" ]; then
  log "Creating new release ${RELEASE_TAG}..."
  RESPONSE=$(curl -fsSL \
    -X POST \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/releases" \
    -d @release.json)
  RELEASE_ID=$(echo "$RESPONSE" | jq -r '.id')
  if [ -z "$RELEASE_ID" ] || [ "$RELEASE_ID" = "null" ]; then
    echo "Failed to create release: $RESPONSE" >&2
    exit 1
  fi
  log "Created release ID: $RELEASE_ID"
else
  log "Found existing release ID: $RELEASE_ID"
fi

# Delete existing asset with same name if present
ASSETS=$(curl -fsSL \
  -H "Accept: application/vnd.github+json" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  "https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/releases/${RELEASE_ID}/assets")
EXISTING_ASSET_ID=$(echo "$ASSETS" | jq -r ".[] | select(.name==\"${ASSET_NAME}\") | .id")
if [ -n "$EXISTING_ASSET_ID" ] && [ "$EXISTING_ASSET_ID" != "null" ]; then
  log "Deleting existing asset ${ASSET_NAME} (ID: ${EXISTING_ASSET_ID})"
  curl -fsSL -X DELETE \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/releases/assets/${EXISTING_ASSET_ID}" >/dev/null
fi

log "Uploading signed package ${ASSET_NAME}..."
curl -fsSL \
  -X POST \
  -H "Accept: application/vnd.github+json" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  -H "Content-Type: application/octet-stream" \
  "https://uploads.github.com/repos/${REPO_OWNER}/${REPO_NAME}/releases/${RELEASE_ID}/assets?name=${ASSET_NAME}" \
  --data-binary "@${PKG}" >/dev/null

log "Upload complete. Signed pkg: $PKG"
