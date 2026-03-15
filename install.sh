#!/bin/bash
set -euo pipefail

REPO="keremerkan/asc-cli"
INSTALL_DIR="/usr/local/bin"
BINARY="asc"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BOLD='\033[1m'
NC='\033[0m'

info() { echo -e "${BOLD}$1${NC}"; }
success() { echo -e "${GREEN}$1${NC}"; }
warn() { echo -e "${YELLOW}$1${NC}"; }
error() { echo -e "${RED}Error: $1${NC}" >&2; exit 1; }

# Check macOS
[[ "$(uname)" == "Darwin" ]] || error "asc requires macOS."

# Check architecture
ARCH="$(uname -m)"
[[ "$ARCH" == "arm64" ]] || error "Pre-built binaries are available for Apple Silicon (arm64) only. Intel Mac users should build from source: https://github.com/$REPO#build-from-source"

# Get latest version
info "Fetching latest release..."
DOWNLOAD_URL="https://github.com/$REPO/releases/latest/download/asc-macos-arm64.tar.gz"

# Download and extract
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

curl -sL "$DOWNLOAD_URL" -o "$TMPDIR/asc.tar.gz"
tar xzf "$TMPDIR/asc.tar.gz" -C "$TMPDIR"

[[ -f "$TMPDIR/$BINARY" ]] || error "Download failed."

# Install
if [[ -w "$INSTALL_DIR" ]]; then
    mv "$TMPDIR/$BINARY" "$INSTALL_DIR/$BINARY"
else
    info "Installing to $INSTALL_DIR (requires sudo)..."
    sudo mv "$TMPDIR/$BINARY" "$INSTALL_DIR/$BINARY"
fi

chmod +x "$INSTALL_DIR/$BINARY"
xattr -d com.apple.quarantine "$INSTALL_DIR/$BINARY" 2>/dev/null || true

# Verify
VERSION=$("$INSTALL_DIR/$BINARY" version 2>/dev/null || echo "unknown")
success "asc $VERSION installed to $INSTALL_DIR/$BINARY"

echo ""
info "Next steps:"
echo "  asc configure          # Set up API credentials"
echo "  asc install-completions  # Enable tab completion"
echo "  asc --help             # See all commands"
