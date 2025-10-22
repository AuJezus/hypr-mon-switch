#!/bin/bash
set -euo pipefail

# Configuration-based startup lid state checker
# Applies the best matching configuration on Hyprland startup

# Wait for compositor to initialize sockets and for DRM to settle
sleep 3
. /etc/acpi/hypr-utils.sh || exit 0
log "Startup lid state check beginning."

if ! export_hypr_env; then
  log "Hyprland env not ready, skipping startup layout."
  exit 0
fi

# Apply the best matching configuration
if apply_best_config; then
  notify "Display" "Startup: monitor layout applied"
else
  log "Failed to apply configuration on startup"
  notify "Display" "Startup: monitor layout update failed"
fi

log "Startup lid state check complete."
