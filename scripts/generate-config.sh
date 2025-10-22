#!/bin/bash
set -euo pipefail

# Configuration generator for hypr-mon-switch
# This script helps users create configuration files by detecting their monitors

CONFIG_FILE="${1:-/etc/hypr-mon-switch/config.yaml}"
TEMP_CONFIG="/tmp/hypr-mon-switch-config-$$.yaml"

log() {
    echo "[generate-config] $*" >&2
}

# Check if yq is available
if ! command -v yq >/dev/null 2>&1; then
    log "Error: yq is required for configuration generation but not installed"
    log "Install with: pacman -S yq (Arch) or your package manager"
    exit 1
fi

# Get Hyprland user
get_hypr_user() {
    local u
    u=$(ps -o user= -C Hyprland | head -n1 || true)
    if [ -z "$u" ]; then
        u=$(ps aux | grep -E '[Hh]yprland' | awk '{print $1}' | head -n1 || true)
    fi
    echo "$u"
}

# Get monitor information
get_monitor_info() {
    local hypr_user
    hypr_user=$(get_hypr_user)
    
    if [ -z "$hypr_user" ]; then
        log "Hyprland not running, cannot detect monitors"
        return 1
    fi
    
    # Get monitor information from hyprctl
    local hypr_output
    hypr_output=$(sudo -u "$hypr_user" hyprctl monitors 2>/dev/null || true)
    
    if [ -z "$hypr_output" ]; then
        log "Failed to get monitor information from hyprctl"
        return 1
    fi
    
    echo "$hypr_output"
}

# Detect laptop monitor
detect_laptop_monitor() {
    local monitor_info="$1"
    
    # Look for eDP connector (typical laptop display)
    echo "$monitor_info" | awk '
        $1=="Monitor" && $2!="(ID" { 
            name=$2
            getline
            if ($1=="description:") {
                desc=$0
                sub(/^\s*description: /, "", desc)
                sub(/ \(.*/, "", desc)
                if (name ~ /^eDP/) {
                    print name "|" desc
                    exit
                }
            }
        }
    '
}

# Detect external monitors
detect_external_monitors() {
    local monitor_info="$1"
    
    echo "$monitor_info" | awk '
        $1=="Monitor" && $2!="(ID" { 
            name=$2
            getline
            if ($1=="description:") {
                desc=$0
                sub(/^\s*description: /, "", desc)
                sub(/ \(.*/, "", desc)
                if (name !~ /^eDP/) {
                    print name "|" desc
                }
            }
        }
    '
}

# Generate configuration
generate_config() {
    local monitor_info="$1"
    local laptop_monitor="$2"
    local external_monitors="$3"
    
    cat > "$TEMP_CONFIG" << 'EOF'
# Generated configuration for hypr-mon-switch
# Edit this file to customize your monitor layouts

global:
  default_workspaces:
    external: [1, 2, 3, 4, 5]
    laptop: [6, 7, 8, 9, 10]
  detection:
    max_attempts: 40
    delay: 0.10
  notifications:
    enabled: true
    timeout: 5000

configurations:
EOF

    # Add laptop-only configuration
    if [ -n "$laptop_monitor" ]; then
        local laptop_connector laptop_desc
        IFS='|' read -r laptop_connector laptop_desc <<< "$laptop_monitor"
        
        cat >> "$TEMP_CONFIG" << EOF

  # Laptop only configuration
  - name: "laptop-only"
    conditions:
      monitors:
        - name: "laptop"
          description: "$laptop_desc"
          connector: "$laptop_connector"
    layout:
      enabled_monitors:
        - name: "laptop"
          description: "$laptop_desc"
          connector: "$laptop_connector"
          resolution: "1920x1200@59.99"
          position: "0x0"
          scale: 1.25
          transform: 0
          workspaces: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
EOF
    fi

    # Add configurations for each external monitor
    local external_count=0
    while IFS= read -r external_monitor; do
        [ -n "$external_monitor" ] || continue
        
        local external_connector external_desc
        IFS='|' read -r external_connector external_desc <<< "$external_monitor"
        
        external_count=$((external_count + 1))
        
        # Laptop closed with external
        cat >> "$TEMP_CONFIG" << EOF

  # Laptop closed with external monitor $external_count
  - name: "laptop-closed-external$external_count"
    conditions:
      lid_state: "closed"
      monitors:
        - name: "external$external_count"
          description: "$external_desc"
          connector: "$external_connector"
    layout:
      enabled_monitors:
        - name: "external$external_count"
          description: "$external_desc"
          connector: "$external_connector"
          resolution: "1920x1080@60"
          position: "0x0"
          scale: 1.0
          transform: 0
          workspaces: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
      disabled_monitors:
        - name: "laptop"
          description: "$laptop_desc"
          connector: "$laptop_connector"
EOF

        # Dual monitor configuration
        if [ -n "$laptop_monitor" ]; then
            cat >> "$TEMP_CONFIG" << EOF

  # Dual monitor configuration (laptop + external $external_count)
  - name: "dual-laptop-external$external_count"
    conditions:
      lid_state: "open"
      monitors:
        - name: "external$external_count"
          description: "$external_desc"
          connector: "$external_connector"
        - name: "laptop"
          description: "$laptop_desc"
          connector: "$laptop_connector"
    layout:
      enabled_monitors:
        - name: "external$external_count"
          description: "$external_desc"
          connector: "$external_connector"
          resolution: "1920x1080@60"
          position: "0x0"
          scale: 1.0
          transform: 0
          workspaces: [1, 2, 3, 4, 5]
        - name: "laptop"
          description: "$laptop_desc"
          connector: "$laptop_connector"
          resolution: "1920x1200@59.99"
          position: "2300x0"
          scale: 1.25
          transform: 0
          workspaces: [6, 7, 8, 9, 10]
EOF
        fi
    done <<< "$external_monitors"

    # Add dual external configuration if we have multiple externals
    if [ "$external_count" -gt 1 ]; then
        local external1 external2
        external1=$(echo "$external_monitors" | head -n1)
        external2=$(echo "$external_monitors" | head -n2 | tail -n1)
        
        local ext1_connector ext1_desc ext2_connector ext2_desc
        IFS='|' read -r ext1_connector ext1_desc <<< "$external1"
        IFS='|' read -r ext2_connector ext2_desc <<< "$external2"
        
        cat >> "$TEMP_CONFIG" << EOF

  # Dual external monitors configuration
  - name: "dual-external"
    conditions:
      monitors:
        - name: "external1"
          description: "$ext1_desc"
          connector: "$ext1_connector"
        - name: "external2"
          description: "$ext2_desc"
          connector: "$ext2_connector"
    layout:
      enabled_monitors:
        - name: "external1"
          description: "$ext1_desc"
          connector: "$ext1_connector"
          resolution: "1920x1080@60"
          position: "0x0"
          scale: 1.0
          transform: 0
          workspaces: [1, 2, 3, 4, 5, 6, 7]
        - name: "external2"
          description: "$ext2_desc"
          connector: "$ext2_connector"
          resolution: "1920x1080@60"
          position: "1920x0"
          scale: 1.0
          transform: 0
          workspaces: [8, 9, 10]
      disabled_monitors:
        - name: "laptop"
          description: "$laptop_desc"
          connector: "$laptop_connector"
EOF
    fi
}

# Main function
main() {
    log "Detecting monitors..."
    
    local monitor_info
    monitor_info=$(get_monitor_info) || {
        log "Failed to detect monitors"
        exit 1
    }
    
    local laptop_monitor
    laptop_monitor=$(detect_laptop_monitor "$monitor_info")
    
    local external_monitors
    external_monitors=$(detect_external_monitors "$monitor_info")
    
    log "Found laptop monitor: ${laptop_monitor:-'none'}"
    log "Found external monitors:"
    echo "$external_monitors" | while IFS= read -r monitor; do
        [ -n "$monitor" ] && log "  $monitor"
    done
    
    log "Generating configuration..."
    generate_config "$monitor_info" "$laptop_monitor" "$external_monitors"
    
    log "Configuration generated: $TEMP_CONFIG"
    log "Review and edit the configuration, then install it:"
    log "  sudo cp $TEMP_CONFIG $CONFIG_FILE"
    log "  sudo /etc/acpi/hypr-utils-config.sh apply"
    
    # Show the generated configuration
    echo
    echo "Generated configuration:"
    echo "========================"
    cat "$TEMP_CONFIG"
}

# Cleanup function
cleanup() {
    rm -f "$TEMP_CONFIG" 2>/dev/null || true
}
trap cleanup EXIT

main "$@"
