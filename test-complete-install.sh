#!/bin/bash
# Test complete installation from scratch
# Run this script as root (use sudo)

echo "=== Testing Complete Installation Process ==="
echo "This will test the install script to ensure it works correctly out of the box"
echo ""

# Remove current installation
echo "1. Removing current installation..."
rm -f /etc/udev/rules.d/99-monitor-hotplug.rules
rm -f /etc/acpi/hypr-utils.sh
rm -f /etc/acpi/monitor-hotplug.sh
rm -f /etc/acpi/monitor-hotplug-config.sh
rm -f /etc/acpi/config-parser.sh
rm -f /etc/acpi/lid-open.sh
rm -f /etc/acpi/lid-close.sh
rm -f /etc/acpi/check-lid-on-startup.sh
rm -f /etc/acpi/events/lid-open
rm -f /etc/acpi/events/lid-close
rm -rf /etc/hypr-mon-switch
udevadm control --reload-rules 2>/dev/null || true
echo "✓ Current installation removed"

# Change to project directory
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# Install using the updated script
echo ""
echo "2. Installing with updated script..."
./scripts/install.sh

echo ""
echo "3. Verifying installation..."

# Check if all files are installed correctly
echo "Checking installed files..."
if [ -f "/etc/acpi/monitor-hotplug-config.sh" ]; then
    echo "✓ monitor-hotplug-config.sh installed (symlink)"
else
    echo "✗ monitor-hotplug-config.sh missing"
fi

if [ -f "/etc/acpi/hypr-utils.sh" ]; then
    echo "✓ hypr-utils.sh installed"
else
    echo "✗ hypr-utils.sh missing"
fi

if [ -f "/etc/acpi/config-parser.sh" ]; then
    echo "✓ config-parser.sh installed"
else
    echo "✗ config-parser.sh missing"
fi

if [ -f "/etc/hypr-mon-switch/config.yaml" ]; then
    echo "✓ config.yaml installed"
else
    echo "✗ config.yaml missing"
fi

if [ -f "/etc/udev/rules.d/99-monitor-hotplug.rules" ]; then
    echo "✓ udev rules installed"
else
    echo "✗ udev rules missing"
fi

# Test configuration
echo ""
echo "Testing configuration..."
if [ -f "/etc/acpi/config-parser.sh" ]; then
    echo "Available configurations:"
    /etc/acpi/config-parser.sh list /etc/hypr-mon-switch/config.yaml 2>/dev/null || true
    echo ""
    echo "Note: Configuration matching requires running as the Hyprland user."
    echo "Testing as current user (should work if Hyprland is running):"
    /etc/acpi/config-parser.sh find /etc/hypr-mon-switch/config.yaml 2>/dev/null || echo "No match found (this is normal if running as root)"
fi

echo ""
echo "=== Installation Test Complete! ==="
echo "The install script should now work correctly out of the box."
echo "No manual fixes should be required after installation."
