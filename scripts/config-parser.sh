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
    
    # Get monitors from hyprctl (all monitors, including disabled)
    if command -v hyprctl >/dev/null 2>&1; then
        local hypr_user
        hypr_user=$(ps -o user= -C Hyprland | head -n1 || true)
        if [ -n "$hypr_user" ]; then
            local hypr_output
            hypr_output=$(sudo -E -u "$hypr_user" hyprctl monitors all 2>/dev/null || true)
            if [ -n "$hypr_output" ]; then
                # Extract monitor info using a simpler approach
                local temp_file="/tmp/hypr_monitors_$$"
                echo "$hypr_output" | grep -A 20 "Monitor.*(" | while read -r line; do
                    if [[ "$line" =~ ^Monitor[[:space:]]+([^[:space:]]+)[[:space:]]+\(ID ]]; then
                        connector="${BASH_REMATCH[1]}"
                        # Look for description in the next few lines
                        for i in {1..10}; do
                            read -r desc_line || break
                            if [[ "$desc_line" =~ ^[[:space:]]*description:[[:space:]]+(.+) ]]; then
                                description="${BASH_REMATCH[1]}"
                                # Remove any parenthetical info
                                description="${description% (*}"
                                echo "$connector|$description"
                                break
                            fi
                        done
                    fi
                done > "$temp_file"
                
                # Read the results into the array
                while IFS='|' read -r connector description; do
                    monitors+=("$connector|$description")
                done < "$temp_file"
                rm -f "$temp_file"
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
    
    # Get monitors from hyprctl (all monitors, then filter for active ones)
    if command -v hyprctl >/dev/null 2>&1; then
        local hypr_user
        hypr_user=$(ps -o user= -C Hyprland | head -n1 || true)
        if [ -n "$hypr_user" ]; then
            local hypr_output
            hypr_output=$(sudo -E -u "$hypr_user" hyprctl monitors all 2>/dev/null || true)
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
    
    # Match by connector if provided (supports patterns like !eDP-* and desc:monitor)
    if [ -n "$target_connector" ]; then
        if [[ "$target_connector" =~ ^desc: ]]; then
            # Match by description: desc:monitor_name
            local desc_pattern="${target_connector#desc:}"
            if [ -n "$description" ] && echo "$description" | grep -qi "$desc_pattern"; then
                return 0
            fi
        elif [[ "$target_connector" =~ ^! ]]; then
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
    mapfile -t connected_monitors < <(get_connected_monitors)
    
    log "Current state: lid=$current_lid_state, monitors=${#connected_monitors[@]}"
    
    # Get number of configurations
    local config_count
    if [ "$major_version" -ge 4 ]; then
        config_count=$(yq eval '.configurations | length' "$YAML_PARSED_FILE" 2>/dev/null || echo "0")
    else
        config_count=$(yq '.configurations | length' "$YAML_PARSED_FILE" 2>/dev/null || echo "0")
    fi
    
    log "Found $config_count configurations to check"
    # Check each configuration and find the best match
    local best_match=""
    local best_match_count=0
    
    for ((i=0; i<config_count; i++)); do
        local config_name
        if [ "$major_version" -ge 4 ]; then
            config_name=$(yq eval ".configurations[$i].name" "$YAML_PARSED_FILE" 2>/dev/null)
        else
            config_name=$(yq ".configurations[$i].name" "$YAML_PARSED_FILE" 2>/dev/null)
        fi
        
        log "Checking configuration $i: $config_name"
        
        # Check lid state condition (optional)
        local required_lid_state
        if [ "$major_version" -ge 4 ]; then
            required_lid_state=$(yq eval ".configurations[$i].conditions.lid_state // \"\"" "$YAML_PARSED_FILE" 2>/dev/null)
        else
            required_lid_state=$(yq ".configurations[$i].conditions.lid_state // \"\"" "$YAML_PARSED_FILE" 2>/dev/null || echo "")
        fi
        # Remove quotes from yq output
        required_lid_state=$(echo "$required_lid_state" | sed 's/^"//;s/"$//')
        if [ -n "$required_lid_state" ] && [ "$current_lid_state" != "$required_lid_state" ]; then
            log "Skipping $config_name due to lid state mismatch"
            continue
        fi
        
        # Check monitor conditions (enabled monitors)
        local required_monitors=()
        if [ "$major_version" -ge 4 ]; then
            mapfile -t required_monitors < <(yq eval ".configurations[$i].conditions.monitors[]? | .name + \"|\" + (.connector // \"\")" "$YAML_PARSED_FILE" 2>/dev/null || true)
        else
            # For yq v3, we need to use a different approach
            local names=()
            local connectors=()
            mapfile -t names < <(yq ".configurations[$i].conditions.monitors[].name" "$YAML_PARSED_FILE" 2>/dev/null || true)
            mapfile -t connectors < <(yq ".configurations[$i].conditions.monitors[].connector" "$YAML_PARSED_FILE" 2>/dev/null || true)
            for j in "${!names[@]}"; do
                required_monitors+=("${names[j]}|${connectors[j]}")
            done
        fi
        
        # Check disabled monitors (they should also be connected)
        local disabled_monitors=()
        if [ "$major_version" -ge 4 ]; then
            mapfile -t disabled_monitors < <(yq eval ".configurations[$i].layout.disabled_monitors[]? | .connector" "$YAML_PARSED_FILE" 2>/dev/null || true)
        else
            mapfile -t disabled_monitors < <(yq ".configurations[$i].layout.disabled_monitors[].connector" "$YAML_PARSED_FILE" 2>/dev/null || true)
        fi
        
        # Combine enabled and disabled monitors for connection check
        local all_required_monitors=("${required_monitors[@]}")
        for disabled_monitor in "${disabled_monitors[@]}"; do
            # Remove quotes from disabled monitor connector
            disabled_monitor=$(echo "$disabled_monitor" | sed 's/^"//;s/"$//')
            all_required_monitors+=("disabled|$disabled_monitor")
        done
        
        log "Checking config $config_name: enabled_monitors=${#required_monitors[@]}, disabled_monitors=${#disabled_monitors[@]}, total_required=${#all_required_monitors[@]}, connected_monitors=${#connected_monitors[@]}"
        log "Required monitors: ${required_monitors[*]}"
        log "Disabled monitors: ${disabled_monitors[*]}"
        log "All required monitors: ${all_required_monitors[*]}"
        
        local all_monitors_match=true
        for required_monitor in "${all_required_monitors[@]}"; do
            local name connector
            IFS='|' read -r name connector <<< "$required_monitor"
            # Remove quotes from name and connector
            name=$(echo "$name" | sed 's/^"//;s/"$//')
            connector=$(echo "$connector" | sed 's/^"//;s/"$//')
            
            log "  Required: name='$name', connector='$connector'"
            
            local monitor_found=false
            for connected_monitor in "${connected_monitors[@]}"; do
                log "    Checking against: $connected_monitor"
                if monitor_matches "$connected_monitor" "$name" "" "$connector"; then
                    log "    MATCH FOUND!"
                    monitor_found=true
                    break
                fi
            done
            
            if [ "$monitor_found" = false ]; then
                log "  No match found for required monitor: $name ($connector)"
                all_monitors_match=false
                break
            fi
        done
        
        if [ "$all_monitors_match" = true ]; then
            local total_required=${#all_required_monitors[@]}
            log "Found matching configuration: $config_name (requires $total_required monitors)"
            
            # Prefer configurations that require more monitors (more specific)
            if [ "$total_required" -gt "$best_match_count" ]; then
                best_match="$config_name"
                best_match_count=$total_required
                log "New best match: $config_name (requires $total_required monitors)"
            fi
        fi
    done
    
    if [ -n "$best_match" ]; then
        log "Selected best matching configuration: $best_match (requires $best_match_count monitors)"
        echo "$best_match"
        return 0
    else
        log "No matching configuration found"
        return 1
    fi
}

# Apply a specific configuration
apply_config() {
    local config_file="$1"
    local config_name="$2"
    
    if ! parse_config "$config_file"; then
        return 1
    fi
    
    # Get yq version for compatibility
    local yq_version
    yq_version=$(yq --version 2>&1 | grep -o '[0-9]\+\.[0-9]\+' | head -1)
    local major_version
    major_version=$(echo "$yq_version" | cut -d. -f1)
    
    # Find the configuration index
    local config_count
    if [ "$major_version" -ge 4 ]; then
        config_count=$(yq eval '.configurations | length' "$YAML_PARSED_FILE" 2>/dev/null || echo "0")
    else
        config_count=$(yq '.configurations | length' "$YAML_PARSED_FILE" 2>/dev/null || echo "0")
    fi
    
    local config_index=-1
    for ((i=0; i<config_count; i++)); do
        local name
        if [ "$major_version" -ge 4 ]; then
            name=$(yq eval ".configurations[$i].name" "$YAML_PARSED_FILE" 2>/dev/null)
        else
            name=$(yq ".configurations[$i].name" "$YAML_PARSED_FILE" 2>/dev/null)
        fi
        # Remove quotes from name if present
        name=$(echo "$name" | sed 's/^"//;s/"$//')
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
    if [ "$major_version" -ge 4 ]; then
        enabled_count=$(yq eval ".configurations[$config_index].layout.enabled_monitors | length" "$YAML_PARSED_FILE" 2>/dev/null || echo "0")
    else
        enabled_count=$(yq ".configurations[$config_index].layout.enabled_monitors | length" "$YAML_PARSED_FILE" 2>/dev/null || echo "0")
    fi
    
    for ((i=0; i<enabled_count; i++)); do
        local monitor_name monitor_resolution monitor_position monitor_scale monitor_transform monitor_workspaces
        
        if [ "$major_version" -ge 4 ]; then
            monitor_name=$(yq eval ".configurations[$config_index].layout.enabled_monitors[$i].name" "$YAML_PARSED_FILE" 2>/dev/null)
            monitor_resolution=$(yq eval ".configurations[$config_index].layout.enabled_monitors[$i].resolution" "$YAML_PARSED_FILE" 2>/dev/null)
            monitor_position=$(yq eval ".configurations[$config_index].layout.enabled_monitors[$i].position" "$YAML_PARSED_FILE" 2>/dev/null)
            monitor_scale=$(yq eval ".configurations[$config_index].layout.enabled_monitors[$i].scale" "$YAML_PARSED_FILE" 2>/dev/null)
            monitor_transform=$(yq eval ".configurations[$config_index].layout.enabled_monitors[$i].transform // 0" "$YAML_PARSED_FILE" 2>/dev/null)
            mapfile -t monitor_workspaces < <(yq eval ".configurations[$config_index].layout.enabled_monitors[$i].workspaces[]?" "$YAML_PARSED_FILE" 2>/dev/null || true)
        else
            monitor_name=$(yq ".configurations[$config_index].layout.enabled_monitors[$i].name" "$YAML_PARSED_FILE" 2>/dev/null)
            monitor_resolution=$(yq ".configurations[$config_index].layout.enabled_monitors[$i].resolution" "$YAML_PARSED_FILE" 2>/dev/null)
            monitor_position=$(yq ".configurations[$config_index].layout.enabled_monitors[$i].position" "$YAML_PARSED_FILE" 2>/dev/null)
            monitor_scale=$(yq ".configurations[$config_index].layout.enabled_monitors[$i].scale" "$YAML_PARSED_FILE" 2>/dev/null)
            monitor_transform=$(yq ".configurations[$config_index].layout.enabled_monitors[$i].transform // 0" "$YAML_PARSED_FILE" 2>/dev/null)
            mapfile -t monitor_workspaces < <(yq ".configurations[$config_index].layout.enabled_monitors[$i].workspaces[]?" "$YAML_PARSED_FILE" 2>/dev/null || true)
        fi
        
        # Remove quotes from monitor name if present
        monitor_name=$(echo "$monitor_name" | sed 's/^"//;s/"$//')
        
        # Find the corresponding connector from conditions
        local monitor_connector=""
        local conditions_monitors
        if [ "$major_version" -ge 4 ]; then
            mapfile -t conditions_monitors < <(yq eval ".configurations[$config_index].conditions.monitors[]? | .name + \"|\" + (.connector // \"\")" "$YAML_PARSED_FILE" 2>/dev/null || true)
        else
            mapfile -t conditions_monitors < <(yq ".configurations[$config_index].conditions.monitors[]? | .name + \"|\" + (.connector // \"\")" "$YAML_PARSED_FILE" 2>/dev/null || true)
        fi
        
        for condition_monitor in "${conditions_monitors[@]}"; do
            local cond_name cond_connector
            IFS='|' read -r cond_name cond_connector <<< "$condition_monitor"
            # Remove quotes from name and connector if present
            cond_name=$(echo "$cond_name" | sed 's/^"//;s/"$//')
            cond_connector=$(echo "$cond_connector" | sed 's/^"//;s/"$//')
            if [ "$cond_name" = "$monitor_name" ]; then
                monitor_connector="$cond_connector"
                break
            fi
        done
        
        # Use the connector as-is (it can be port name or desc:monitor)
        local monitor_ident="$monitor_connector"
        
        # Apply monitor configuration
        local hypr_cmd="monitor $monitor_ident,$monitor_resolution,$monitor_position,$monitor_scale"
        if [ "$monitor_transform" != "0" ]; then
            hypr_cmd="$hypr_cmd,transform,$monitor_transform"
        fi
        
        log "Enabling monitor: $monitor_name ($monitor_ident)"
        echo "hyprctl keyword $hypr_cmd"
        
        # Move workspaces if specified
        for workspace in "${monitor_workspaces[@]}"; do
            if [ -n "$workspace" ]; then
                log "Assigning workspace $workspace to $monitor_ident"
                echo "hyprctl keyword workspace $workspace,monitor:$monitor_ident"
            fi
        done
    done
    
    # Disable monitors
    local disabled_count
    if [ "$major_version" -ge 4 ]; then
        disabled_count=$(yq eval ".configurations[$config_index].layout.disabled_monitors | length" "$YAML_PARSED_FILE" 2>/dev/null || echo "0")
    else
        disabled_count=$(yq ".configurations[$config_index].layout.disabled_monitors | length" "$YAML_PARSED_FILE" 2>/dev/null || echo "0")
    fi
    
    for ((i=0; i<disabled_count; i++)); do
        local monitor_connector
        
        if [ "$major_version" -ge 4 ]; then
            monitor_connector=$(yq eval ".configurations[$config_index].layout.disabled_monitors[$i].connector" "$YAML_PARSED_FILE" 2>/dev/null)
        else
            monitor_connector=$(yq ".configurations[$config_index].layout.disabled_monitors[$i].connector" "$YAML_PARSED_FILE" 2>/dev/null)
        fi
        
        log "Disabling monitor: $monitor_connector"
        echo "hyprctl keyword monitor $monitor_connector,disable"
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
            local apply_config_file="${3:-$CONFIG_FILE}"
            if [ -z "$config_name" ]; then
                echo "Usage: $0 apply <config_name> [config_file]" >&2
                exit 1
            fi
            apply_config "$apply_config_file" "$config_name"
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
