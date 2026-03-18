#!/bin/bash
set -euo pipefail

REPO="keremerkan/ascelerate"
INSTALL_DIR="/usr/local/bin"
BINARY="ascelerate"

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
[[ "$(uname)" == "Darwin" ]] || error "ascelerate requires macOS."

# Check architecture
ARCH="$(uname -m)"
[[ "$ARCH" == "arm64" ]] || error "Pre-built binaries are available for Apple Silicon (arm64) only. Intel Mac users should build from source: https://github.com/$REPO#build-from-source"

# Get latest version
info "Fetching latest release..."
DOWNLOAD_URL="https://github.com/$REPO/releases/latest/download/ascelerate-macos-arm64.tar.gz"

# Download and extract
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

curl -sL "$DOWNLOAD_URL" -o "$TMPDIR/ascelerate.tar.gz"
tar xzf "$TMPDIR/ascelerate.tar.gz" -C "$TMPDIR"

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
success "ascelerate $VERSION installed to $INSTALL_DIR/$BINARY"

echo ""
info "Next steps:"
echo "  ascelerate configure          # Set up API credentials"
echo "  ascelerate install-completions  # Enable tab completion"
echo "  ascelerate --help             # See all commands"
