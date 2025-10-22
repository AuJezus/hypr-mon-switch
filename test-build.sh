#!/bin/bash
# Test package build only
# Run this script from the project directory

set -euo pipefail

echo "=== Testing Package Build ==="
echo ""

# Create build directory
BUILD_DIR="$HOME/builds/hypr-mon-switch-test"
mkdir -p "$BUILD_DIR"
echo "Building in: $BUILD_DIR"

# Copy project files to build directory (excluding .git)
echo "1. Copying project files..."
for item in *; do
  if [ "$item" != ".git" ] && [ "$item" != "pkg" ] && [ "$item" != "src" ] && [[ ! "$item" =~ \.pkg\.tar\.zst$ ]]; then
    cp -r "$item" "$BUILD_DIR/"
  fi
done
cd "$BUILD_DIR"

echo "2. Cleaning previous builds..."
rm -f *.pkg.tar.zst
rm -rf pkg/ src/

echo "3. Building package..."
makepkg -f

echo ""
echo "4. Checking package contents..."
echo "Package files:"
tar -tf hypr-mon-switch-git-*.pkg.tar.zst | head -20 || true
echo "..."
echo "Total files: $(tar -tf hypr-mon-switch-git-*.pkg.tar.zst | wc -l)"

echo ""
echo "=== Package Build Test Complete! ==="
echo ""
echo "Package built successfully: $BUILD_DIR/hypr-mon-switch-git-*.pkg.tar.zst"
echo ""
echo "To install and test:"
echo "  sudo pacman -U $BUILD_DIR/hypr-mon-switch-git-*.pkg.tar.zst"
echo "  sudo /usr/share/hypr-mon-switch/scripts/install.sh"
echo ""
echo "To uninstall:"
echo "  sudo pacman -R hypr-mon-switch-git"
