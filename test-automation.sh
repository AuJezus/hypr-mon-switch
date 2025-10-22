#!/bin/bash
set -euo pipefail

# Test script for hypr-mon-switch automation
# This script tests the automation without permission issues

echo "=== Testing hypr-mon-switch Automation ==="

# Test 1: Configuration Parser
echo "1. Testing configuration parser..."
./scripts/config-parser.sh list configs/example-config.yaml

# Test 2: Configuration Matching
echo -e "\n2. Testing configuration matching..."
./scripts/config-parser.sh find configs/example-config.yaml

# Test 3: Configuration Application (dry run)
echo -e "\n3. Testing configuration application (dry run)..."
echo "Commands that would be executed:"
./scripts/config-parser.sh apply dual-external configs/example-config.yaml | head -5

# Test 4: Test with actual execution
echo -e "\n4. Testing actual configuration application..."
echo "Applying dual-external configuration..."

# Execute the configuration
./scripts/config-parser.sh apply dual-external configs/example-config.yaml | while IFS= read -r cmd; do
    if [ -n "$cmd" ]; then
        echo "Executing: $cmd"
        eval "$cmd" || echo "Warning: Command failed: $cmd"
        sleep 0.1
    fi
done

echo -e "\n=== Automation Test Complete ==="
echo "Check your monitor layout - it should have changed!"
