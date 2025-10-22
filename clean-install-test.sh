#!/bin/bash
# Clean install and test script
# Run this script as root (use sudo)

echo "=== Clean Install and Test ==="
echo "This will completely remove the current installation and install fresh"
echo ""

# Step 1: Remove current installation
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

# Step 2: Change to project directory and install
echo ""
echo "2. Installing fresh version..."
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
./scripts/install.sh

echo ""
echo "3. Verifying installation..."
echo "Checking installed files:"
if [ -f "/etc/acpi/monitor-hotplug-config.sh" ]; then
    echo "✓ monitor-hotplug-config.sh (symlink)"
else
    echo "✗ monitor-hotplug-config.sh missing"
fi

if [ -f "/etc/acpi/hypr-utils.sh" ]; then
    echo "✓ hypr-utils.sh"
else
    echo "✗ hypr-utils.sh missing"
fi

if [ -f "/etc/acpi/config-parser.sh" ]; then
    echo "✓ config-parser.sh"
else
    echo "✗ config-parser.sh missing"
fi

if [ -f "/etc/hypr-mon-switch/config.yaml" ]; then
    echo "✓ config.yaml"
else
    echo "✗ config.yaml missing"
fi

if [ -f "/etc/udev/rules.d/99-monitor-hotplug.rules" ]; then
    echo "✓ udev rules"
else
    echo "✗ udev rules missing"
fi

echo ""
echo "4. Testing configuration parser..."
echo "Available configurations:"
/etc/acpi/config-parser.sh list /etc/hypr-mon-switch/config.yaml 2>/dev/null || true

echo ""
echo "5. Testing as user (should work if Hyprland is running):"
/etc/acpi/config-parser.sh find /etc/hypr-mon-switch/config.yaml 2>/dev/null || echo "No match found (normal if running as root)"

echo ""
echo "6. Current monitor state:"
echo "Note: hyprctl requires running as the Hyprland user."
echo "Testing as current user (should work if Hyprland is running):"
hyprctl monitors all | grep -E "(Monitor|description|disabled)" | head -8 2>/dev/null || echo "Cannot access Hyprland (normal if running as root)"

echo ""
echo "=== Clean Install Complete! ==="
echo ""
echo "The system is now installed and ready to use."
echo ""
echo "To test automatic switching:"
echo "1. Connect/disconnect your AOC monitor"
echo "2. Check logs with: journalctl -t hypr-mon-switch --since '1 minute ago'"
echo "3. Test manually with: /etc/acpi/monitor-hotplug-config.sh"
echo ""
echo "Expected behavior:"
echo "- When AOC connected: dual-external (Samsung + AOC enabled, laptop disabled)"
echo "- When AOC disconnected: laptop-external (Samsung + laptop enabled)"
