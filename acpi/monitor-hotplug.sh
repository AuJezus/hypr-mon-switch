#!/bin/bash
set -uo pipefail

# Configuration-based monitor hotplug handler
# Reacts to monitor hotplug events and applies the best matching configuration

sleep 0.3

# Get the Hyprland user
get_hypr_user() {
  local u
  u=$(ps -o user= -C Hyprland | head -n1 || true)
  if [ -z "$u" ]; then
    u=$(ps aux | grep -E '[Hh]yprland' | awk '{print $1}' | head -n1 || true)
  fi
  echo "$u"
}

# Get Hyprland environment
get_hypr_env() {
  local user="$1"
  local pid
  pid=$(pgrep -u "$user" -x Hyprland | head -n1 || true)
  if [ -z "$pid" ]; then
    pid=$(pgrep -u "$user" -f '[Hh]yprland' | head -n1 || true)
  fi
  if [ -z "$pid" ]; then
    return 1
  fi
  
  # Get XDG_RUNTIME_DIR from the process environment
  local xdg_runtime_dir
  if [ -r "/proc/$pid/environ" ]; then
    xdg_runtime_dir=$(cat /proc/"$pid"/environ | tr '\0' '\n' | awk -F= '$1=="XDG_RUNTIME_DIR"{print $2}')
  fi
  if [ -z "$xdg_runtime_dir" ]; then
    xdg_runtime_dir="/run/user/$(id -u "$user")"
  fi
  
  # Get HYPRLAND_INSTANCE_SIGNATURE from the process environment
  local hypr_sig
  if [ -r "/proc/$pid/environ" ]; then
    hypr_sig=$(cat /proc/"$pid"/environ | tr '\0' '\n' | awk -F= '$1=="HYPRLAND_INSTANCE_SIGNATURE"{print $2}')
  fi
  
  # If not found, try to find the most recent socket directory
  if [ -z "$hypr_sig" ]; then
    local latest_socket=""
    local latest_time=0
    for socket_dir in "$xdg_runtime_dir"/hypr/*/; do
      if [ -d "$socket_dir" ] && [ -S "${socket_dir}/.socket.sock" ]; then
        local mtime=$(stat -c %Y "$socket_dir" 2>/dev/null || echo 0)
        if [ "$mtime" -gt "$latest_time" ]; then
          latest_time="$mtime"
          latest_socket="$socket_dir"
        fi
      fi
    done
    if [ -n "$latest_socket" ]; then
      hypr_sig=$(basename "$latest_socket")
    fi
  fi
  
  echo "$user|$xdg_runtime_dir|$hypr_sig"
}

# Log function
log() {
  logger -t hypr-mon-switch "[$0] $*"
}

log "Hotplug event: evaluating monitor layout with configuration system."

# Get Hyprland user
HYPR_USER=$(get_hypr_user)
log "Detected Hyprland user: $HYPR_USER"
if [ -z "$HYPR_USER" ]; then
  log "Hyprland not found, exiting."
  exit 0
fi

# Get Hyprland environment
HYPR_ENV=$(get_hypr_env "$HYPR_USER")
log "Hyprland environment: $HYPR_ENV"
if [ -z "$HYPR_ENV" ]; then
  log "Could not get Hyprland environment for user $HYPR_USER"
  exit 0
fi

# Parse environment
IFS='|' read -r HYPR_USER XDG_RUNTIME_DIR HYPR_SIG <<< "$HYPR_ENV"

log "Hyprland env: user=$HYPR_USER, XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR, sig=${HYPR_SIG:-'(auto-detect)'}"

# Give the kernel/userspace a brief moment to enumerate changes
sleep 0.5

# Run the configuration system as the Hyprland user
log "Running as user: $(whoami), target user: $HYPR_USER"

# Check if we're already running as the target user (udev rule runs us as the user)
if [ "$(whoami)" = "$HYPR_USER" ]; then
  log "Already running as target user, executing directly"
  # Already running as the target user, just execute directly
  if [ -n "$HYPR_SIG" ]; then
    log "Running with signature: $HYPR_SIG"
    env HYPR_USER="$HYPR_USER" HYPRLAND_INSTANCE_SIGNATURE="$HYPR_SIG" XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" /etc/acpi/hypr-utils.sh apply
  else
    log "Running without signature"
    env HYPR_USER="$HYPR_USER" XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" /etc/acpi/hypr-utils.sh apply
  fi
else
  log "Need to switch to user $HYPR_USER"
  # Need to switch user (this shouldn't happen with udev rule)
  if [ -n "$HYPR_SIG" ]; then
    if command -v runuser >/dev/null 2>&1; then
      runuser -u "$HYPR_USER" -- env HYPRLAND_INSTANCE_SIGNATURE="$HYPR_SIG" XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" /etc/acpi/hypr-utils.sh apply
    else
      sudo -u "$HYPR_USER" env HYPRLAND_INSTANCE_SIGNATURE="$HYPR_SIG" XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" /etc/acpi/hypr-utils.sh apply
    fi
  else
    if command -v runuser >/dev/null 2>&1; then
      runuser -u "$HYPR_USER" -- env XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" /etc/acpi/hypr-utils.sh apply
    else
      sudo -u "$HYPR_USER" env XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" /etc/acpi/hypr-utils.sh apply
    fi
  fi
fi

log "Hotplug layout evaluation complete."
