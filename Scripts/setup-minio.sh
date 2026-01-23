#!/bin/bash
set -euo pipefail

# Detect platform and architecture
OS=$(uname -s)
ARCH=$(uname -m)

# Map to minio download names
case "$OS" in
    Darwin)
        case "$ARCH" in
            arm64) MINIO_BINARY="minio-darwin-arm64" ;;
            x86_64) MINIO_BINARY="minio-darwin-amd64" ;;
            *) echo "Unsupported architecture: $ARCH"; exit 1 ;;
        esac
        ;;
    Linux)
        case "$ARCH" in
            x86_64) MINIO_BINARY="minio-linux-amd64" ;;
            aarch64) MINIO_BINARY="minio-linux-arm64" ;;
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

# Check if already exists
if [ -f "$MINIO_PATH" ]; then
    echo "minio already installed at $MINIO_PATH"
    "$MINIO_PATH" --version
    exit 0
fi

# Create directory
mkdir -p "$MINIO_DIR"

# Download minio
DOWNLOAD_URL="https://dl.min.io/server/minio/release/${OS,,}/${ARCH,,}/minio"
# Use platform-specific URL format
case "$OS" in
    Darwin)
        case "$ARCH" in
            arm64) DOWNLOAD_URL="https://dl.min.io/server/minio/release/darwin-arm64/minio" ;;
            x86_64) DOWNLOAD_URL="https://dl.min.io/server/minio/release/darwin-amd64/minio" ;;
        esac
        ;;
    Linux)
        case "$ARCH" in
            x86_64) DOWNLOAD_URL="https://dl.min.io/server/minio/release/linux-amd64/minio" ;;
            aarch64) DOWNLOAD_URL="https://dl.min.io/server/minio/release/linux-arm64/minio" ;;
        esac
        ;;
esac

echo "Downloading minio from $DOWNLOAD_URL..."
curl -fSL "$DOWNLOAD_URL" -o "$MINIO_PATH"
chmod +x "$MINIO_PATH"

echo "minio installed successfully"
"$MINIO_PATH" --version
