#!/bin/bash
set -euo pipefail

umask 022
PATH=/usr/local/bin:/usr/bin:/bin

# Configuration-based hypr-utils for hypr-mon-switch
# This script uses YAML configuration files to determine monitor layouts
# instead of hardcoded values.

# Configuration file path (can be overridden by environment variable)
CONFIG_FILE="${HYPR_MON_CONFIG:-/etc/hypr-mon-switch/config.yaml}"

# Script directory for finding config-parser
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_PARSER="${SCRIPT_DIR}/config-parser.sh"

log() {
  logger -t hypr-mon-switch "[$0] $*"
}

# Debounce: single instance at a time
exec 9>/var/run/hypr-mon-switch.lock || true
if command -v flock >/dev/null 2>&1; then
  flock -n 9 || { log "Another monitor switch instance running, exiting."; exit 0; }
fi

require_cmd() { command -v "$1" >/dev/null 2>&1 || { log "Missing command: $1"; exit 1; }; }
require_cmd hyprctl
require_cmd logger

# Check if config parser is available
if [ ! -f "$CONFIG_PARSER" ]; then
  log "Configuration parser not found: $CONFIG_PARSER"
  exit 1
fi

get_hypr_user() {
  local u
  u=$(ps -o user= -C Hyprland | head -n1 || true)
  if [ -z "$u" ]; then
    u=$(ps aux | grep -E '[Hh]yprland' | awk '{print $1}' | head -n1 || true)
  fi
  echo "$u"
}

export_hypr_env() {
  HYPR_USER="${HYPR_USER:-$(get_hypr_user)}"
  if [ -z "$HYPR_USER" ]; then
    log "Hyprland user not found."
    return 1
  fi
  local pid
  pid=$(pgrep -u "$HYPR_USER" -x Hyprland | head -n1 || true)
  if [ -z "$pid" ]; then
    pid=$(pgrep -u "$HYPR_USER" -f '[Hh]yprland' | head -n1 || true)
  fi
  if [ -z "$pid" ]; then
    log "Hyprland PID not found for user $HYPR_USER."
    return 1
  fi
  
  # Get XDG_RUNTIME_DIR from the process environment
  XDG_RUNTIME_DIR=$(cat /proc/"$pid"/environ | tr '\0' '\n' | awk -F= '$1=="XDG_RUNTIME_DIR"{print $2}')
  if [ -z "$XDG_RUNTIME_DIR" ]; then
    XDG_RUNTIME_DIR="/run/user/$(id -u "$HYPR_USER")"
  fi
  
  # Try to get HYPRLAND_INSTANCE_SIGNATURE from the process environment
  HYPR_SIG=$(cat /proc/"$pid"/environ | tr '\0' '\n' | awk -F= '$1=="HYPRLAND_INSTANCE_SIGNATURE"{print $2}')
  
  # If not found (e.g., UWSM managed), try to find the most recent socket directory
  if [ -z "$HYPR_SIG" ]; then
    # Look for the most recent Hyprland socket directory
    local latest_socket=""
    local latest_time=0
    for socket_dir in "$XDG_RUNTIME_DIR"/hypr/*/; do
      if [ -d "$socket_dir" ] && [ -S "${socket_dir}/.socket.sock" ]; then
        local mtime=$(stat -c %Y "$socket_dir" 2>/dev/null || echo 0)
        if [ "$mtime" -gt "$latest_time" ]; then
          latest_time="$mtime"
          latest_socket="$socket_dir"
        fi
      fi
    done
    if [ -n "$latest_socket" ]; then
      HYPR_SIG=$(basename "$latest_socket")
    fi
  fi
  
  if [ -z "$XDG_RUNTIME_DIR" ]; then
    log "Could not determine XDG_RUNTIME_DIR for user $HYPR_USER."
    return 1
  fi
  
  # We can proceed even without HYPR_SIG as hyprctl might work without it
  export HYPR_USER HYPR_SIG XDG_RUNTIME_DIR
  log "Hyprland env: user=$HYPR_USER, XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR, sig=${HYPR_SIG:-'(auto-detect)'}"
}

run_as_hypr() {
  if [ -n "$HYPR_SIG" ]; then
    if command -v runuser >/dev/null 2>&1; then
      runuser -u "$HYPR_USER" -- env HYPRLAND_INSTANCE_SIGNATURE="$HYPR_SIG" XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" "$@"
    else
      sudo -u "$HYPR_USER" env HYPRLAND_INSTANCE_SIGNATURE="$HYPR_SIG" XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" "$@"
    fi
  else
    # Try without HYPR_SIG, let hyprctl auto-detect
    if command -v runuser >/dev/null 2>&1; then
      runuser -u "$HYPR_USER" -- env XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" "$@"
    else
      sudo -u "$HYPR_USER" env XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" "$@"
    fi
  fi
}

hypr() {
  run_as_hypr hyprctl "$@"
}

# Find and apply the best matching configuration
apply_best_config() {
  log "Finding best configuration for current state..."
  
  if [ ! -f "$CONFIG_FILE" ]; then
    log "Configuration file not found: $CONFIG_FILE"
    log "Please create a configuration file or set HYPR_MON_CONFIG environment variable"
    return 1
  fi
  
  # Find matching configuration
  local config_name
  config_name=$("$CONFIG_PARSER" find "$CONFIG_FILE" 2>/dev/null)
  
  if [ -z "$config_name" ]; then
    log "No matching configuration found for current state"
    return 1
  fi
  
  log "Applying configuration: $config_name"
  
  # Apply the configuration
  local config_commands
  config_commands=$("$CONFIG_PARSER" apply "$CONFIG_FILE" "$config_name" 2>/dev/null)
  
  if [ -z "$config_commands" ]; then
    log "Failed to generate configuration commands"
    return 1
  fi
  
  # Execute the configuration commands
  echo "$config_commands" | while IFS= read -r cmd; do
    if [ -n "$cmd" ]; then
      log "Executing: $cmd"
      eval "$cmd" || log "Warning: Command failed: $cmd"
      sleep 0.1
    fi
  done
  
  # Ensure displays are awake after configuration
  sleep 0.25
  hypr dispatch dpms on || true
  
  log "Configuration applied successfully: $config_name"
  return 0
}

# Apply a specific configuration by name
apply_config() {
  local config_name="$1"
  
  if [ -z "$config_name" ]; then
    log "No configuration name provided"
    return 1
  fi
  
  if [ ! -f "$CONFIG_FILE" ]; then
    log "Configuration file not found: $CONFIG_FILE"
    return 1
  fi
  
  log "Applying specific configuration: $config_name"
  
  # Apply the configuration
  local config_commands
  config_commands=$("$CONFIG_PARSER" apply "$CONFIG_FILE" "$config_name" 2>/dev/null)
  
  if [ -z "$config_commands" ]; then
    log "Failed to generate configuration commands for: $config_name"
    return 1
  fi
  
  # Execute the configuration commands
  echo "$config_commands" | while IFS= read -r cmd; do
    if [ -n "$cmd" ]; then
      log "Executing: $cmd"
      eval "$cmd" || log "Warning: Command failed: $cmd"
      sleep 0.1
    fi
  done
  
  # Ensure displays are awake after configuration
  sleep 0.25
  hypr dispatch dpms on || true
  
  log "Configuration applied successfully: $config_name"
  return 0
}

# List available configurations
list_configs() {
  if [ ! -f "$CONFIG_FILE" ]; then
    log "Configuration file not found: $CONFIG_FILE"
    return 1
  fi
  
  "$CONFIG_PARSER" list "$CONFIG_FILE" 2>/dev/null
}

# Notify user about display changes
notify() {
  if command -v notify-send >/dev/null 2>&1; then
    run_as_hypr notify-send "$@"
  fi
}

# Main function for command-line usage
main() {
  local action="${1:-apply}"
  
  case "$action" in
    "apply")
      if [ $# -gt 1 ]; then
        apply_config "$2"
      else
        apply_best_config
      fi
      ;;
    "list")
      list_configs
      ;;
    "find")
      "$CONFIG_PARSER" find "$CONFIG_FILE"
      ;;
    *)
      echo "Usage: $0 {apply [config_name]|list|find}" >&2
      echo "  apply [config_name] - Apply best matching or specific configuration" >&2
      echo "  list               - List available configurations" >&2
      echo "  find               - Find best matching configuration" >&2
      exit 1
      ;;
  esac
}

# If script is run directly, execute main function
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  main "$@"
fi
