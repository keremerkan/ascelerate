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

curl -fsSL "$DOWNLOAD_URL" -o "$TMPDIR/ascelerate.tar.gz" || error "Download failed."
tar xzf "$TMPDIR/ascelerate.tar.gz" -C "$TMPDIR"

[[ -f "$TMPDIR/$BINARY" ]] || error "Download failed."

# Only a binary signed with ascelerate's Developer ID (AKE Software GmbH, team GH4CGS3B5H)
REQUIREMENT='anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] exists and certificate leaf[field.1.2.840.113635.100.6.1.13] exists and certificate leaf[subject.OU] = "GH4CGS3B5H"'
codesign --verify --strict -R="$REQUIREMENT" "$TMPDIR/$BINARY" 2>/dev/null \
    || error "The download isn't signed with ascelerate's Developer ID, so it wasn't installed."

# Install (a fresh macOS has no /usr/local/bin yet)
if [[ -d "$INSTALL_DIR" && -w "$INSTALL_DIR" ]]; then
    install -m 755 "$TMPDIR/$BINARY" "$INSTALL_DIR/$BINARY"
else
    info "Installing to $INSTALL_DIR (requires sudo)..."
    sudo mkdir -p "$INSTALL_DIR"
    sudo install -m 755 "$TMPDIR/$BINARY" "$INSTALL_DIR/$BINARY"
fi

# Verify
VERSION=$("$INSTALL_DIR/$BINARY" version 2>/dev/null || echo "unknown")
success "ascelerate $VERSION installed to $INSTALL_DIR/$BINARY"

echo ""
info "Next steps:"
echo "  ascelerate configure          # Set up API credentials"
echo "  ascelerate install-completions  # Enable tab completion"
echo "  ascelerate --help             # See all commands"
