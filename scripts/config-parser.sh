#!/bin/bash
set -euo pipefail

# Configuration parser for hypr-mon-switch
# This script parses YAML configuration files and provides functions to match
# and apply monitor configurations based on current system state.

# Default configuration file path
CONFIG_FILE="${HYPR_MON_CONFIG:-/etc/hypr-mon-switch/config.yaml}"

# Temporary files for processing
TEMP_DIR="/tmp/hypr-mon-switch-$$"
YAML_PARSED_FILE="$TEMP_DIR/parsed.yaml"

# Cleanup function
cleanup() {
    rm -rf "$TEMP_DIR" 2>/dev/null || true
}
trap cleanup EXIT

# Create temp directory
mkdir -p "$TEMP_DIR"

# Logging function
log() {
    echo "[config-parser] $*" >&2
}

# Check if yq is available for YAML parsing
check_yq() {
    if ! command -v yq >/dev/null 2>&1; then
        log "Error: yq is required for YAML parsing but not installed"
        log "Install with: pacman -S yq (Arch) or your package manager"
        return 1
    fi
    return 0
}

# Parse YAML configuration file
parse_config() {
    local config_file="$1"
    
    if [ ! -f "$config_file" ]; then
        log "Configuration file not found: $config_file"
        return 1
    fi
    
    if ! check_yq; then
        return 1
    fi
    
    # Parse YAML to a more shell-friendly format
    # Check yq version and use appropriate syntax
    local yq_version
    yq_version=$(yq --version 2>&1 | grep -o '[0-9]\+\.[0-9]\+' | head -1)
    local major_version
    major_version=$(echo "$yq_version" | cut -d. -f1)
    
    if [ "$major_version" -ge 4 ]; then
        # Go-based yq (version 4+)
        yq eval -o=json "$config_file" > "$YAML_PARSED_FILE" 2>/dev/null || {
            log "Error parsing YAML configuration file: $config_file"
            return 1
        }
    else
        # Python-based yq (version 3.x)
        yq -r '.' "$config_file" > "$YAML_PARSED_FILE" 2>/dev/null || {
            log "Error parsing YAML configuration file: $config_file"
            return 1
        }
    fi
    
    log "Configuration loaded from: $config_file"
    return 0
}

# Get current lid state
get_lid_state() {
    local lid_state="unknown"
    for f in /proc/acpi/button/lid/*/state; do
        if [ -r "$f" ]; then
            if grep -q closed "$f"; then
                lid_state="closed"
            else
                lid_state="open"
            fi
            break
        fi
    done
    echo "$lid_state"
}

# Get list of currently connected monitors
get_connected_monitors() {
    local monitors=()
    
    # Get monitors from hyprctl
    if command -v hyprctl >/dev/null 2>&1; then
        local hypr_user
        hypr_user=$(ps -o user= -C Hyprland | head -n1 || true)
        if [ -n "$hypr_user" ]; then
            local hypr_output
            hypr_output=$(sudo -E -u "$hypr_user" hyprctl monitors 2>/dev/null || true)
            if [ -n "$hypr_output" ]; then
                echo "$hypr_output" | awk '
                    $1=="Monitor" && $2!="(ID" { 
                        name=$2
                        getline
                        if ($1=="description:") {
                            desc=$0
                            sub(/^\s*description: /, "", desc)
                            sub(/ \(.*/, "", desc)
                            print name "|" desc
                        }
                    }
                ' | while IFS='|' read -r connector description; do
                    monitors+=("$connector|$description")
                done
            fi
        fi
    fi
    
    # Fallback to sysfs detection
    if [ ${#monitors[@]} -eq 0 ]; then
        for path in /sys/class/drm/card*-*/status; do
            [ -r "$path" ] || continue
            if grep -q '^connected' "$path"; then
                local connector
                connector=$(basename "$(dirname "$path")")
                connector="${connector#*-}"
                monitors+=("$connector|")
            fi
        done
    fi
    
    printf '%s\n' "${monitors[@]}"
}

# Get list of currently active (enabled) monitors only
get_active_monitors() {
    local monitors=()
    
    # Get monitors from hyprctl
    if command -v hyprctl >/dev/null 2>&1; then
        local hypr_user
        hypr_user=$(ps -o user= -C Hyprland | head -n1 || true)
        if [ -n "$hypr_user" ]; then
            local hypr_output
            hypr_output=$(sudo -E -u "$hypr_user" hyprctl monitors 2>/dev/null || true)
            if [ -n "$hypr_output" ]; then
                while IFS='|' read -r connector description; do
                    monitors+=("$connector|$description")
                done < <(echo "$hypr_output" | awk '
                    $1=="Monitor" && $2!="(ID" { 
                        name=$2
                        disabled=0
                        desc=""
                        getline
                        while (getline && $0 != "") {
                            if ($1=="disabled:" && $2=="true") {
                                disabled=1
                            }
                            if ($1=="description:") {
                                desc=$0
                                sub(/^\s*description: /, "", desc)
                                sub(/ \(.*/, "", desc)
                            }
                        }
                        if (!disabled && desc != "") {
                            print name "|" desc
                        }
                    }
                ')
            fi
        fi
    fi
    
    # Fallback to sysfs detection
    if [ ${#monitors[@]} -eq 0 ]; then
        for path in /sys/class/drm/card*-*/status; do
            [ -r "$path" ] || continue
            if grep -q '^connected' "$path"; then
                local connector
                connector=$(basename "$(dirname "$path")")
                connector="${connector#*-}"
                monitors+=("$connector|")
            fi
        done
    fi
    
    printf '%s\n' "${monitors[@]}"
}

# Check if a monitor matches the given criteria
monitor_matches() {
    local monitor_info="$1"
    local target_name="$2"
    local target_description="$3"
    local target_connector="$4"
    
    local connector description
    IFS='|' read -r connector description <<< "$monitor_info"
    
    # Match by connector if provided (supports patterns like !eDP-*)
    if [ -n "$target_connector" ]; then
        if [[ "$target_connector" =~ ^! ]]; then
            # Negative pattern: match if connector does NOT match the pattern after !
            local pattern="${target_connector#!}"
            # Convert * wildcards to .* for regex
            pattern="${pattern//\*/.*}"
            if [[ ! "$connector" =~ $pattern ]]; then
                return 0
            fi
        else
            # Positive pattern: exact match or wildcard match
            if [[ "$target_connector" == *"*" ]]; then
                if [[ "$connector" =~ ${target_connector//\*/.*} ]]; then
                    return 0
                fi
            elif [ "$connector" = "$target_connector" ]; then
                return 0
            fi
        fi
    fi
    
    # Match by description if provided
    if [ -n "$target_description" ] && [ -n "$description" ] && [ "$description" = "$target_description" ]; then
        return 0
    fi
    
    # Match by name if provided (partial match in description)
    if [ -n "$target_name" ] && [ -n "$description" ] && echo "$description" | grep -qi "$target_name"; then
        return 0
    fi
    
    return 1
}

# Find matching configuration based on current state
find_matching_config() {
    local config_file="$1"
    
    if ! parse_config "$config_file"; then
        return 1
    fi
    
    # Get yq version for compatibility
    local yq_version
    yq_version=$(yq --version 2>&1 | grep -o '[0-9]\+\.[0-9]\+' | head -1)
    local major_version
    major_version=$(echo "$yq_version" | cut -d. -f1)
    
    local current_lid_state
    current_lid_state=$(get_lid_state)
    
    local connected_monitors
    mapfile -t connected_monitors < <(get_active_monitors)
    
    log "Current state: lid=$current_lid_state, monitors=${#connected_monitors[@]}"
    
    # Get number of configurations
    local config_count
    if [ "$major_version" -ge 4 ]; then
        config_count=$(yq eval '.configurations | length' "$YAML_PARSED_FILE" 2>/dev/null || echo "0")
    else
        config_count=$(yq '.configurations | length' "$YAML_PARSED_FILE" 2>/dev/null || echo "0")
    fi
    
    # Check each configuration
    for ((i=0; i<config_count; i++)); do
        local config_name
        if [ "$major_version" -ge 4 ]; then
            config_name=$(yq eval ".configurations[$i].name" "$YAML_PARSED_FILE" 2>/dev/null)
        else
            config_name=$(yq ".configurations[$i].name" "$YAML_PARSED_FILE" 2>/dev/null)
        fi
        
        # Check lid state condition
        local required_lid_state
        if [ "$major_version" -ge 4 ]; then
            required_lid_state=$(yq eval ".configurations[$i].conditions.lid_state // \"\"" "$YAML_PARSED_FILE" 2>/dev/null)
        else
            required_lid_state=$(yq ".configurations[$i].conditions.lid_state // \"\"" "$YAML_PARSED_FILE" 2>/dev/null)
        fi
        if [ -n "$required_lid_state" ] && [ "$current_lid_state" != "$required_lid_state" ]; then
            continue
        fi
        
        # Check monitor conditions
        local required_monitors
        if [ "$major_version" -ge 4 ]; then
            mapfile -t required_monitors < <(yq eval ".configurations[$i].conditions.monitors[]? | .name + \"|\" + (.description // \"\") + \"|\" + (.connector // \"\")" "$YAML_PARSED_FILE" 2>/dev/null || true)
        else
            mapfile -t required_monitors < <(yq ".configurations[$i].conditions.monitors[]? | .name + \"|\" + (.description // \"\") + \"|\" + (.connector // \"\")" "$YAML_PARSED_FILE" 2>/dev/null || true)
        fi
        
        local all_monitors_match=true
        for required_monitor in "${required_monitors[@]}"; do
            local name desc connector
            IFS='|' read -r name desc connector <<< "$required_monitor"
            
            local monitor_found=false
            for connected_monitor in "${connected_monitors[@]}"; do
                if monitor_matches "$connected_monitor" "$name" "$desc" "$connector"; then
                    monitor_found=true
                    break
                fi
            done
            
            if [ "$monitor_found" = false ]; then
                all_monitors_match=false
                break
            fi
        done
        
        if [ "$all_monitors_match" = true ]; then
            log "Found matching configuration: $config_name"
            echo "$config_name"
            return 0
        fi
    done
    
    log "No matching configuration found"
    return 1
}

# Apply a specific configuration
apply_config() {
    local config_file="$1"
    local config_name="$2"
    
    if ! parse_config "$config_file"; then
        return 1
    fi
    
    # Find the configuration index
    local config_count
    config_count=$(yq eval '.configurations | length' "$YAML_PARSED_FILE" 2>/dev/null || echo "0")
    
    local config_index=-1
    for ((i=0; i<config_count; i++)); do
        local name
        name=$(yq eval ".configurations[$i].name" "$YAML_PARSED_FILE" 2>/dev/null)
        if [ "$name" = "$config_name" ]; then
            config_index=$i
            break
        fi
    done
    
    if [ "$config_index" -eq -1 ]; then
        log "Configuration not found: $config_name"
        return 1
    fi
    
    log "Applying configuration: $config_name"
    
    # Apply enabled monitors
    local enabled_count
    enabled_count=$(yq eval ".configurations[$config_index].layout.enabled_monitors | length" "$YAML_PARSED_FILE" 2>/dev/null || echo "0")
    
    for ((i=0; i<enabled_count; i++)); do
        local monitor_name monitor_desc monitor_connector monitor_resolution monitor_position monitor_scale monitor_transform monitor_workspaces
        
        monitor_name=$(yq eval ".configurations[$config_index].layout.enabled_monitors[$i].name" "$YAML_PARSED_FILE" 2>/dev/null)
        monitor_desc=$(yq eval ".configurations[$config_index].layout.enabled_monitors[$i].description // \"\"" "$YAML_PARSED_FILE" 2>/dev/null)
        monitor_connector=$(yq eval ".configurations[$config_index].layout.enabled_monitors[$i].connector" "$YAML_PARSED_FILE" 2>/dev/null)
        monitor_resolution=$(yq eval ".configurations[$config_index].layout.enabled_monitors[$i].resolution" "$YAML_PARSED_FILE" 2>/dev/null)
        monitor_position=$(yq eval ".configurations[$config_index].layout.enabled_monitors[$i].position" "$YAML_PARSED_FILE" 2>/dev/null)
        monitor_scale=$(yq eval ".configurations[$config_index].layout.enabled_monitors[$i].scale" "$YAML_PARSED_FILE" 2>/dev/null)
        monitor_transform=$(yq eval ".configurations[$config_index].layout.enabled_monitors[$i].transform // 0" "$YAML_PARSED_FILE" 2>/dev/null)
        monitor_workspaces=$(yq eval ".configurations[$config_index].layout.enabled_monitors[$i].workspaces[]?" "$YAML_PARSED_FILE" 2>/dev/null || true)
        
        # Build monitor identifier
        local monitor_ident
        if [ -n "$monitor_desc" ]; then
            monitor_ident="desc:$monitor_desc"
        else
            monitor_ident="$monitor_connector"
        fi
        
        # Apply monitor configuration
        local hypr_cmd="monitor $monitor_ident,$monitor_resolution,$monitor_position,$monitor_scale"
        if [ "$monitor_transform" != "0" ]; then
            hypr_cmd="$hypr_cmd,transform,$monitor_transform"
        fi
        
        log "Enabling monitor: $monitor_name ($monitor_ident)"
        echo "hyprctl keyword $hypr_cmd"
        
        # Move workspaces if specified
        if [ -n "$monitor_workspaces" ]; then
            echo "$monitor_workspaces" | while read -r workspace; do
                if [ -n "$workspace" ]; then
                    log "Moving workspace $workspace to $monitor_connector"
                    echo "hyprctl dispatch moveworkspacetomonitor $workspace $monitor_connector"
                fi
            done
        fi
    done
    
    # Disable monitors
    local disabled_count
    disabled_count=$(yq eval ".configurations[$config_index].layout.disabled_monitors | length" "$YAML_PARSED_FILE" 2>/dev/null || echo "0")
    
    for ((i=0; i<disabled_count; i++)); do
        local monitor_desc monitor_connector
        
        monitor_desc=$(yq eval ".configurations[$config_index].layout.disabled_monitors[$i].description // \"\"" "$YAML_PARSED_FILE" 2>/dev/null)
        monitor_connector=$(yq eval ".configurations[$config_index].layout.disabled_monitors[$i].connector" "$YAML_PARSED_FILE" 2>/dev/null)
        
        local monitor_ident
        if [ -n "$monitor_desc" ]; then
            monitor_ident="desc:$monitor_desc"
        else
            monitor_ident="$monitor_connector"
        fi
        
        log "Disabling monitor: $monitor_connector ($monitor_ident)"
        echo "hyprctl keyword monitor $monitor_ident,disable"
    done
    
    return 0
}

# Main function for command-line usage
main() {
    local action="${1:-}"
    local config_file="${2:-$CONFIG_FILE}"
    
    case "$action" in
        "find")
            find_matching_config "$config_file"
            ;;
        "apply")
            local config_name="$2"
            if [ -z "$config_name" ]; then
                echo "Usage: $0 apply <config_name> [config_file]" >&2
                exit 1
            fi
            apply_config "$config_file" "$config_name"
            ;;
        "list")
            if ! parse_config "$config_file"; then
                exit 1
            fi
            # Get yq version for compatibility
            local yq_version
            yq_version=$(yq --version 2>&1 | grep -o '[0-9]\+\.[0-9]\+' | head -1)
            local major_version
            major_version=$(echo "$yq_version" | cut -d. -f1)
            
            if [ "$major_version" -ge 4 ]; then
                yq eval '.configurations[].name' "$YAML_PARSED_FILE" 2>/dev/null
            else
                yq '.configurations[].name' "$YAML_PARSED_FILE" 2>/dev/null
            fi
            ;;
        *)
            echo "Usage: $0 {find|apply|list} [config_file]" >&2
            echo "  find  - Find matching configuration for current state" >&2
            echo "  apply - Apply specific configuration" >&2
            echo "  list  - List available configurations" >&2
            exit 1
            ;;
    esac
}

# If script is run directly, execute main function
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi
