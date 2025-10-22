#!/bin/bash
set -euo pipefail

# Test script for hypr-mon-switch configuration system
# This script tests the configuration parser and utilities

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
CONFIG_PARSER="$REPO_ROOT/scripts/config-parser.sh"
TEST_CONFIG="$REPO_ROOT/configs/example-config.yaml"

log() {
    echo "[test-config] $*"
}

# Test configuration parser
test_config_parser() {
    log "Testing configuration parser..."
    
    if [ ! -f "$CONFIG_PARSER" ]; then
        log "ERROR: Configuration parser not found: $CONFIG_PARSER"
        return 1
    fi
    
    if [ ! -f "$TEST_CONFIG" ]; then
        log "ERROR: Test configuration not found: $TEST_CONFIG"
        return 1
    fi
    
    # Check if yq is available
    if ! command -v yq >/dev/null 2>&1; then
        log "ERROR: yq is required for YAML parsing but not installed"
        log "Install with: pacman -S yq (Arch) or your package manager"
        return 1
    fi
    
    # Test listing configurations
    log "Testing configuration listing..."
    local configs
    configs=$("$CONFIG_PARSER" list "$TEST_CONFIG" 2>/dev/null)
    if [ -z "$configs" ]; then
        log "ERROR: Failed to list configurations"
        return 1
    fi
    log "Found configurations:"
    echo "$configs" | while IFS= read -r config; do
        log "  - $config"
    done
    
    # Test finding matching configuration
    log "Testing configuration matching..."
    local matching_config
    matching_config=$("$CONFIG_PARSER" find "$TEST_CONFIG" 2>/dev/null)
    if [ -n "$matching_config" ]; then
        log "Found matching configuration: $matching_config"
    else
        log "No matching configuration found (this may be normal)"
    fi
    
    # Test applying a specific configuration
    log "Testing configuration application..."
    local first_config
    first_config=$(echo "$configs" | head -n1)
    if [ -n "$first_config" ]; then
        log "Testing application of: $first_config"
        local apply_output
        apply_output=$("$CONFIG_PARSER" apply "$TEST_CONFIG" "$first_config" 2>/dev/null)
        if [ -n "$apply_output" ]; then
            log "Configuration application test passed"
        else
            log "WARNING: Configuration application returned no output"
        fi
    fi
    
    log "Configuration parser tests completed"
    return 0
}

# Test hypr-utils-config
test_hypr_utils() {
    log "Testing hypr-utils..."
    
    local hypr_utils="$REPO_ROOT/acpi/hypr-utils.sh"
    if [ ! -f "$hypr_utils" ]; then
        log "ERROR: hypr-utils.sh not found: $hypr_utils"
        return 1
    fi
    
    # Check if yq is available
    if ! command -v yq >/dev/null 2>&1; then
        log "ERROR: yq is required for YAML parsing but not installed"
        log "Install with: pacman -S yq (Arch) or your package manager"
        return 1
    fi
    
    # Test listing configurations
    log "Testing hypr-utils list..."
    local configs
    configs=$(HYPR_MON_CONFIG="$TEST_CONFIG" "$hypr_utils" list 2>/dev/null)
    if [ -z "$configs" ]; then
        log "ERROR: Failed to list configurations with hypr-utils"
        return 1
    fi
    log "Hypr-utils found configurations:"
    echo "$configs" | while IFS= read -r config; do
        log "  - $config"
    done
    
    # Test finding configuration
    log "Testing hypr-utils find..."
    local matching_config
    matching_config=$(HYPR_MON_CONFIG="$TEST_CONFIG" "$hypr_utils" find 2>/dev/null)
    if [ -n "$matching_config" ]; then
        log "Hypr-utils found matching configuration: $matching_config"
    else
        log "Hypr-utils found no matching configuration (this may be normal)"
    fi
    
    log "Hypr-utils tests completed"
    return 0
}

# Test configuration generation
test_config_generation() {
    log "Testing configuration generation..."
    
    local generate_script="$REPO_ROOT/scripts/generate-config.sh"
    if [ ! -f "$generate_script" ]; then
        log "ERROR: Configuration generator not found: $generate_script"
        return 1
    fi
    
    # Check if yq is available
    if ! command -v yq >/dev/null 2>&1; then
        log "ERROR: yq is required for YAML parsing but not installed"
        log "Install with: pacman -S yq (Arch) or your package manager"
        return 1
    fi
    
    # Test configuration generation (dry run)
    log "Testing configuration generation (dry run)..."
    local temp_config="/tmp/hypr-mon-switch-test-config.yaml"
    if "$generate_script" "$temp_config" 2>/dev/null; then
        if [ -f "$temp_config" ]; then
            log "Configuration generation test passed"
            log "Generated configuration preview:"
            head -n 20 "$temp_config"
            rm -f "$temp_config"
        else
            log "ERROR: Configuration generation failed to create file"
            return 1
        fi
    else
        log "WARNING: Configuration generation failed (may be normal if Hyprland not running)"
    fi
    
    log "Configuration generation tests completed"
    return 0
}

# Main test function
main() {
    log "Starting hypr-mon-switch configuration system tests..."
    
    local failed=0
    
    # Test configuration parser
    if ! test_config_parser; then
        failed=1
    fi
    
    # Test hypr-utils
    if ! test_hypr_utils; then
        failed=1
    fi
    
    # Test configuration generation
    if ! test_config_generation; then
        failed=1
    fi
    
    if [ $failed -eq 0 ]; then
        log "All tests passed!"
        exit 0
    else
        log "Some tests failed!"
        exit 1
    fi
}

main "$@"
