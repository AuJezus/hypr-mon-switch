#!/bin/bash
# Test AUR package build and installation
# Run this script from the project directory

set -euo pipefail

echo "=== Testing AUR Package Build and Installation ==="
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
echo "3. Installing package..."
sudo pacman -U --noconfirm hypr-mon-switch-git-*.pkg.tar.zst

echo ""
echo "4. Testing package installation..."

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
echo "5. Testing setup script..."
sudo /usr/share/hypr-mon-switch/scripts/install.sh

echo ""
echo "6. Verifying setup..."
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
echo "7. Testing uninstall script..."
sudo /usr/share/hypr-mon-switch/scripts/uninstall.sh --dry-run

echo ""
echo "8. Removing package (testing post_remove hook)..."
sudo pacman -R --noconfirm hypr-mon-switch-git

echo ""
echo "9. Verifying complete removal..."
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
