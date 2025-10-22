#!/bin/bash
set -euo pipefail
# Wait for compositor to initialize sockets and for DRM to settle
sleep 3
. /etc/acpi/hypr-utils.sh || exit 0
log "Startup lid state check beginning."

need_reassert=0

if ! export_hypr_env; then
  log "Hyprland env not ready, skipping startup layout."
  exit 0
fi

detect_external_monitor || true

# If two externals are present, prefer using them and disable laptop
if two_externals_connected; then
  log "Two external monitors detected at startup. Applying two-externals-only layout."
  set_two_externals_only
  move_ws_to_monitor "$EXTERNAL_MONITOR" $EXTERNAL1_WS
  move_ws_to_monitor "$EXTERNAL2_MONITOR" $EXTERNAL2_WS
  notify "Display" "Startup: two externals detected, laptop disabled"
  need_reassert=1
fi

LID_STATE="unknown"
for f in /proc/acpi/button/lid/*/state; do
  if [ -r "$f" ]; then
    if grep -q closed "$f"; then LID_STATE="closed"; else LID_STATE="open"; fi
    break
  fi
done

if [ "$LID_STATE" = "closed" ] && two_externals_connected; then
  log "Lid closed and two externals connected. Using externals only."
  set_two_externals_only
  move_ws_to_monitor "$EXTERNAL_MONITOR" $EXTERNAL1_WS
  move_ws_to_monitor "$EXTERNAL2_MONITOR" $EXTERNAL2_WS
  notify "Display" "Startup: lid closed, two externals only"
  need_reassert=1
elif [ "$LID_STATE" = "closed" ] && external_connected; then
  log "Boot with lid closed and external connected. Applying external-only."
  set_external_only
  move_ws_to_monitor "$EXTERNAL_MONITOR" 1 2 3 4 5 6 7 8 9 10
  notify "Display" "Startup: lid closed, using external monitor only"
  need_reassert=1
elif two_externals_connected; then
  log "Boot with lid open and two externals. Laptop disabled, spread workspaces."
  set_two_externals_only
  move_ws_to_monitor "$EXTERNAL_MONITOR" $EXTERNAL1_WS
  move_ws_to_monitor "$EXTERNAL2_MONITOR" $EXTERNAL2_WS
  notify "Display" "Startup: two externals active"
  need_reassert=1
elif external_connected; then
  log "Boot with lid open and external connected. Applying dual layout."
  set_dual_layout
  move_ws_to_monitor "$EXTERNAL_MONITOR" $EXTERNAL_WS
  move_ws_to_monitor "$LAPTOP_MONITOR" $LAPTOP_WS
  notify "Display" "Startup: dual layout applied"
  need_reassert=1
else
  log "Boot without external. Applying laptop-only."
  set_laptop_only
  notify "Display" "Startup: laptop-only layout"
fi

# Ensure all monitors are awake after configuration
hypr dispatch dpms on
if [ "$need_reassert" -eq 1 ]; then
  reassert_primary_external
fi
log "Startup lid state check complete."
