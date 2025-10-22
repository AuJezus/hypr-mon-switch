#!/bin/bash
set -euo pipefail

# Configuration-based monitor hotplug handler
# Reacts to monitor hotplug events and applies the best matching configuration

sleep 0.3
# Source hypr-utils.sh from the same directory as this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${SCRIPT_DIR}/hypr-utils.sh" || exit 0

# Set the config file to the development version if we're running from development
if [ -f "${SCRIPT_DIR}/../configs/example-config.yaml" ]; then
  export HYPR_MON_CONFIG="${SCRIPT_DIR}/../configs/example-config.yaml"
fi
log "Hotplug event: evaluating monitor layout with configuration system."

if ! export_hypr_env; then
  log "Hyprland not found, exiting."
  exit 0
fi

# Give the kernel/userspace a brief moment to enumerate changes
sleep 0.5

# Apply the best matching configuration
if apply_best_config; then
  notify "Display" "Monitor layout updated"
else
  log "Failed to apply configuration"
  notify "Display" "Monitor layout update failed"
fi

log "Hotplug layout evaluation complete."
