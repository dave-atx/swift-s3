#!/bin/bash
set -euo pipefail

# Pinned minio version for reproducible tests
# Override with MINIO_VERSION env var for testing newer versions
DEFAULT_MINIO_VERSION="RELEASE.2025-09-07T16-13-09Z"
MINIO_VERSION="${MINIO_VERSION:-$DEFAULT_MINIO_VERSION}"

# Detect platform and architecture
OS=$(uname -s)
ARCH=$(uname -m)

# Map to minio platform names
case "$OS" in
    Darwin)
        case "$ARCH" in
            arm64) PLATFORM="darwin-arm64" ;;
            x86_64) PLATFORM="darwin-amd64" ;;
            *) echo "Unsupported architecture: $ARCH"; exit 1 ;;
        esac
        ;;
    Linux)
        case "$ARCH" in
            x86_64) PLATFORM="linux-amd64" ;;
            aarch64) PLATFORM="linux-arm64" ;;
            *) echo "Unsupported architecture: $ARCH"; exit 1 ;;
        esac
        ;;
    *)
        echo "Unsupported OS: $OS"
        exit 1
        ;;
esac

# Setup paths
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
MINIO_DIR="$PROJECT_DIR/.minio"
MINIO_PATH="$MINIO_DIR/minio"
VERSION_FILE="$MINIO_DIR/.version"

# Check if correct version already exists
if [ -f "$MINIO_PATH" ] && [ -f "$VERSION_FILE" ]; then
    INSTALLED_VERSION=$(cat "$VERSION_FILE")
    if [ "$INSTALLED_VERSION" = "$MINIO_VERSION" ]; then
        echo "minio $MINIO_VERSION already installed at $MINIO_PATH"
        "$MINIO_PATH" --version
        exit 0
    else
        echo "Installed version ($INSTALLED_VERSION) differs from requested ($MINIO_VERSION)"
        echo "Re-downloading..."
        rm -f "$MINIO_PATH" "$VERSION_FILE"
    fi
fi

# Create directory
mkdir -p "$MINIO_DIR"

# Download minio (versioned URL)
DOWNLOAD_URL="https://dl.min.io/server/minio/release/${PLATFORM}/archive/minio.${MINIO_VERSION}"

echo "Downloading minio $MINIO_VERSION for $PLATFORM..."
curl -fSL "$DOWNLOAD_URL" -o "$MINIO_PATH"
chmod +x "$MINIO_PATH"

# Save version for future checks
echo "$MINIO_VERSION" > "$VERSION_FILE"

echo "minio installed successfully"
"$MINIO_PATH" --version
