#!/bin/bash
# Test package build only
# Run this script from the project directory

set -euo pipefail

echo "=== Testing Package Build ==="
echo ""

# Change to project directory
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

echo "1. Cleaning previous builds..."
rm -f *.pkg.tar.zst
rm -rf pkg/ src/

echo "2. Building package..."
makepkg -f

echo ""
echo "3. Checking package contents..."
echo "Package files:"
tar -tf hypr-mon-switch-git-*.pkg.tar.zst | head -20
echo "..."
echo "Total files: $(tar -tf hypr-mon-switch-git-*.pkg.tar.zst | wc -l)"

echo ""
echo "=== Package Build Test Complete! ==="
echo ""
echo "Package built successfully: hypr-mon-switch-git-*.pkg.tar.zst"
echo ""
echo "To install and test:"
echo "  sudo pacman -U hypr-mon-switch-git-*.pkg.tar.zst"
echo "  sudo /usr/share/hypr-mon-switch/scripts/install.sh"
echo ""
echo "To uninstall:"
echo "  sudo pacman -R hypr-mon-switch-git"
