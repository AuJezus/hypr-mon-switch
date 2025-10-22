#!/bin/bash
set -euo pipefail
sleep 0.3
. /etc/acpi/hypr-utils.sh || exit 0
log "Lid close event received."

if ! export_hypr_env; then
  log "Hyprland not found, exiting."
  exit 0
fi

# Let Hyprland settle after env export
sleep 0.5
detect_external_monitor || true

# Prefer two externals when available
if two_externals_connected; then
  log "Two external monitors detected on lid close. Applying two-externals-only layout."
  set_two_externals_only
  sleep 0.35
  move_ws_to_monitor "$EXTERNAL_MONITOR" $EXTERNAL1_WS
  sleep 0.15
  move_ws_to_monitor "$EXTERNAL2_MONITOR" $EXTERNAL2_WS
  notify "Display" "Lid closed: using two external monitors"
  sleep 0.25
  hypr dispatch dpms on
  log "Two-externals-only layout applied."
  exit 0
fi

if external_connected_retry 40 0.10; then
  log "External ${EXTERNAL_MONITOR} connected. Applying external-only layout."
  set_external_only
  sleep 0.35
  move_ws_to_monitor "$EXTERNAL_MONITOR" 1 2 3 4 5 6 7 8 9 10
  notify "Display" "Lid closed: using external monitor only"
  # Ensure external monitor is awake
  sleep 0.25
  hypr dispatch dpms on
  sleep 0.10
  log "External-only layout applied and workspaces moved."
else
  log "No external monitor detected. Keeping laptop-only layout."
  set_laptop_only
fi
