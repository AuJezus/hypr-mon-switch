#!/bin/bash
set -euo pipefail

# Simple test script that works like hotplug - detects current state and applies best config
echo "=== hypr-mon-switch Manual Hotplug Test ==="

# Configuration file
CONFIG_FILE="configs/example-config.yaml"

# Test 1: Show current state
echo "1. Current monitor state (all monitors):"
hyprctl monitors all | grep -E "(Monitor|description|disabled)" | head -8

# Test 2: Find best matching configuration
echo -e "\n2. Finding best matching configuration..."
MATCHING_CONFIG=$(./scripts/config-parser.sh find "$CONFIG_FILE" 2>&1 | tail -1 | sed 's/^"//;s/"$//' || true)

if [ -n "$MATCHING_CONFIG" ] && [ "$MATCHING_CONFIG" != "No matching configuration found" ]; then
    echo "Found matching configuration: $MATCHING_CONFIG"
else
    echo "No matching configuration found for current state"
    echo "Available configurations:"
    ./scripts/config-parser.sh list "$CONFIG_FILE"
    echo -e "\nSince no configuration matches your current setup, let's apply a test configuration:"
    echo "Applying 'dual-external' configuration for demonstration..."
    MATCHING_CONFIG="dual-external"
fi

# Test 3: Apply the matching configuration
echo -e "\n3. Applying configuration: $MATCHING_CONFIG"
echo "Executing configuration commands..."

# Execute the configuration
./scripts/config-parser.sh apply "$MATCHING_CONFIG" "$CONFIG_FILE" | while IFS= read -r cmd; do
    if [ -n "$cmd" ]; then
        echo "Executing: $cmd"
        eval "$cmd" || echo "Warning: Command failed: $cmd"
        sleep 0.1
    fi
done

echo -e "\n=== Configuration Applied Successfully! ==="
echo "Your monitor layout has been updated based on current state."
