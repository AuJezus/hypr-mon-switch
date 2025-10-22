#!/bin/bash
# Test AUR package build and installation
# Run this script from the project directory

set -euo pipefail

echo "=== Testing AUR Package Build and Installation ==="
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
echo "4. Installing package..."
sudo pacman -U --noconfirm hypr-mon-switch-git-*.pkg.tar.zst

echo ""
echo "5. Testing package installation..."

# Check if files are installed correctly
echo "Checking installed files:"
if [ -f "/etc/acpi/hypr-utils.sh" ]; then
    echo "✓ hypr-utils.sh"
else
    echo "✗ hypr-utils.sh missing"
fi

if [ -f "/etc/acpi/monitor-hotplug.sh" ]; then
    echo "✓ monitor-hotplug.sh"
else
    echo "✗ monitor-hotplug.sh missing"
fi

if [ -f "/etc/acpi/monitor-hotplug-config.sh" ]; then
    echo "✓ monitor-hotplug-config.sh"
else
    echo "✗ monitor-hotplug-config.sh missing"
fi

if [ -f "/etc/hypr-mon-switch/config.yaml" ]; then
    echo "✓ config.yaml"
else
    echo "✗ config.yaml missing"
fi

if [ -f "/usr/share/hypr-mon-switch/scripts/install.sh" ]; then
    echo "✓ install.sh in /usr/share"
else
    echo "✗ install.sh missing from /usr/share"
fi

if [ -f "/usr/share/hypr-mon-switch/scripts/uninstall.sh" ]; then
    echo "✓ uninstall.sh in /usr/share"
else
    echo "✗ uninstall.sh missing from /usr/share"
fi

echo ""
echo "6. Testing setup script..."
sudo /usr/share/hypr-mon-switch/scripts/install.sh

echo ""
echo "7. Verifying setup..."
if [ -f "/etc/udev/rules.d/99-monitor-hotplug.rules" ]; then
    echo "✓ udev rules created"
else
    echo "✗ udev rules missing"
fi

if [ -L "/etc/acpi/monitor-hotplug-config.sh" ]; then
    echo "✓ symlink created"
else
    echo "✗ symlink missing"
fi

echo ""
echo "8. Testing uninstall script..."
sudo /usr/share/hypr-mon-switch/scripts/uninstall.sh --dry-run

echo ""
echo "9. Removing package (testing post_remove hook)..."
sudo pacman -R --noconfirm hypr-mon-switch-git

echo ""
echo "10. Verifying complete removal..."
if [ ! -f "/etc/acpi/hypr-utils.sh" ]; then
    echo "✓ hypr-utils.sh removed"
else
    echo "✗ hypr-utils.sh still exists"
fi

if [ ! -f "/etc/udev/rules.d/99-monitor-hotplug.rules" ]; then
    echo "✓ udev rules removed"
else
    echo "✗ udev rules still exist"
fi

if [ ! -d "/etc/hypr-mon-switch" ]; then
    echo "✓ config directory removed"
else
    echo "✗ config directory still exists"
fi

if [ ! -f "/usr/share/hypr-mon-switch/scripts/install.sh" ]; then
    echo "✓ package files removed"
else
    echo "✗ package files still exist"
fi

echo ""
echo "=== AUR Package Test Complete! ==="
echo ""
echo "The package build, installation, setup, and removal process has been tested."
echo "All components should work correctly for AUR users."
