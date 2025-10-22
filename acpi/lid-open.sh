#!/bin/bash
set -euo pipefail
sleep 0.3
. /etc/acpi/hypr-utils.sh || exit 0
log "Lid open event received."

if ! export_hypr_env; then
  log "Hyprland not found, exiting."
  exit 0
fi

# Let Hyprland settle after env export
sleep 0.5
detect_external_monitor || true

# Prefer two externals when available
if two_externals_connected; then
  log "Two external monitors detected on lid open. Applying two-externals-only layout."
  set_two_externals_only
  sleep 0.35
  move_ws_to_monitor "$EXTERNAL_MONITOR" $EXTERNAL1_WS
  sleep 0.15
  move_ws_to_monitor "$EXTERNAL2_MONITOR" $EXTERNAL2_WS
  notify "Display" "Lid opened: using two external monitors"
  sleep 0.25
  hypr dispatch dpms on
  reassert_primary_external
  log "Two-externals-only layout applied."
  exit 0
fi

if external_connected_retry 40 0.10; then
  log "External ${EXTERNAL_MONITOR} connected. Applying dual layout."
  set_dual_layout
  sleep 0.35
  move_ws_to_monitor "$EXTERNAL_MONITOR" $EXTERNAL_WS
  sleep 0.15
  move_ws_to_monitor "$LAPTOP_MONITOR" $LAPTOP_WS
  notify "Display" "Lid opened: dual display layout set"
  # Ensure monitors are awake
  sleep 0.25
  hypr dispatch dpms on
  # Delayed re-assert for slow-waking docks; make sure focus/workspace are correct
  reassert_primary_external
  log "Dual layout applied and workspace split enforced."
else
  log "No external monitor detected. Applying laptop-only."
  set_laptop_only
fi
