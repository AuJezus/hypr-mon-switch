#!/bin/bash
set -euo pipefail

echo "=== Monitor Detection Debug ==="

echo "1. hyprctl monitors (active only):"
hyprctl monitors | grep -E "(Monitor|description|disabled)" | head -6

echo -e "\n2. hyprctl monitors all (all monitors):"
hyprctl monitors all | grep -E "(Monitor|description|disabled)" | head -8

echo -e "\n3. Config parser get_connected_monitors:"
# Source the config parser to use its functions
source ./scripts/config-parser.sh
get_connected_monitors | while IFS='|' read -r connector description; do
    echo "  Connector: $connector, Description: $description"
done

echo -e "\n4. Config parser get_active_monitors:"
get_active_monitors | while IFS='|' read -r connector description; do
    echo "  Connector: $connector, Description: $description"
done
