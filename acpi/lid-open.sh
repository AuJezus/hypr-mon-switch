#!/bin/bash
set -euo pipefail

# Configuration-based lid open handler
# Applies the best matching configuration when laptop lid is opened

sleep 0.3
. /etc/acpi/hypr-utils.sh || exit 0
log "Lid open event received."

if ! export_hypr_env; then
  log "Hyprland not found, exiting."
  exit 0
fi

# Let Hyprland settle after env export
sleep 0.5

# Apply the best matching configuration
if apply_best_config; then
  notify "Display" "Lid opened: monitor layout updated"
else
  log "Failed to apply configuration for lid open"
  notify "Display" "Lid opened: monitor layout update failed"
fi

log "Lid open layout evaluation complete."
