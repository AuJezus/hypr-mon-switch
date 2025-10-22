#!/bin/bash
set -euo pipefail

# Small handler to react to monitor hotplug events (udev drm change)
# Chooses layout based on currently connected monitors:
# - two externals -> use both externals, disable laptop
# - one external  -> external + laptop (dual)
# - none          -> laptop only

sleep 0.3
. /etc/acpi/hypr-utils.sh || exit 0
log "Hotplug event: evaluating monitor layout."

if ! export_hypr_env; then
  log "Hyprland not found, exiting."
  exit 0
fi

# Give the kernel/userspace a brief moment to enumerate changes
sleep 0.5

# Try to detect current state
detect_two_external_monitors || true
detect_external_monitor || true

if two_externals_connected; then
  log "Detected two external monitors. Applying two-externals-only layout."
  set_two_externals_only
  sleep 0.25
  move_ws_to_monitor "$EXTERNAL_MONITOR" ${EXTERNAL1_WS:-1 2 3 4 5}
  sleep 0.10
  move_ws_to_monitor "$EXTERNAL2_MONITOR" ${EXTERNAL2_WS:-6 7 8 9 10}
  notify "Display" "Hotplug: two externals active; laptop disabled"
elif external_connected; then
  log "Detected single external monitor. Applying dual layout."
  set_dual_layout
  sleep 0.25
  move_ws_to_monitor "$EXTERNAL_MONITOR" ${EXTERNAL_WS:-1 2 3 4 5}
  sleep 0.10
  move_ws_to_monitor "$LAPTOP_MONITOR" ${LAPTOP_WS:-6 7 8 9 10}
  notify "Display" "Hotplug: external + laptop (dual)"
else
  log "No external monitors detected. Applying laptop-only layout."
  set_laptop_only
  notify "Display" "Hotplug: laptop-only layout"
fi

# Ensure displays are awake after layout switch
sleep 0.25
hypr dispatch dpms on || true

log "Hotplug layout evaluation complete."





