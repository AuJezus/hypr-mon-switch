#!/bin/bash
set -euo pipefail

# Update system installation with new configuration format
echo "=== Updating hypr-mon-switch system installation ==="

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "This script must be run as root (use sudo)"
    exit 1
fi

# Update the monitor hotplug script
echo "Updating monitor hotplug script..."
cp acpi/monitor-hotplug.sh /etc/acpi/monitor-hotplug.sh
chmod +x /etc/acpi/monitor-hotplug.sh

# Update the hypr-utils script
echo "Updating hypr-utils script..."
cp acpi/hypr-utils.sh /etc/acpi/hypr-utils.sh
chmod +x /etc/acpi/hypr-utils.sh

# Update the config parser
echo "Updating config parser..."
cp scripts/config-parser.sh /etc/hypr-mon-switch/config-parser.sh
chmod +x /etc/hypr-mon-switch/config-parser.sh

# Update the configuration files
echo "Updating configuration files..."
cp configs/example-config.yaml /etc/hypr-mon-switch/config.yaml
cp configs/default-config.yaml /etc/hypr-mon-switch/default-config.yaml

# Set proper permissions
echo "Setting permissions..."
chown -R root:root /etc/hypr-mon-switch/
chmod -R 755 /etc/hypr-mon-switch/

echo "=== System installation updated successfully! ==="
echo "You can now test the automation with:"
echo "  sudo -u aujezus /etc/acpi/monitor-hotplug.sh"
