#!/bin/bash
set -euo pipefail

# Configuration-based lid close handler
# Applies the best matching configuration when laptop lid is closed

sleep 0.3
. /etc/acpi/hypr-utils.sh || exit 0
log "Lid close event received."

if ! export_hypr_env; then
  log "Hyprland not found, exiting."
  exit 0
fi

# Let Hyprland settle after env export
sleep 0.5

# Apply the best matching configuration
if apply_best_config; then
  notify "Display" "Lid closed: monitor layout updated"
else
  log "Failed to apply configuration for lid close"
  notify "Display" "Lid closed: monitor layout update failed"
fi

log "Lid close layout evaluation complete."
