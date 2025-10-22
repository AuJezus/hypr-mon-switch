#!/bin/bash
set -euo pipefail

umask 022
PATH=/usr/local/bin:/usr/bin:/bin

log() {
  logger -t lid-events "[$0] $*"
}

# ========== CONFIGURATION SECTION ==========
# Customize these values based on your hardware
# You can identify monitors by connector names (e.g., DP-1, HDMI-A-1, eDP-1)
# or by description strings (e.g., "Chimei Innolux Corporation 0x150C").
# If a *_DESC is provided (non-empty), it will be preferred when applying
# monitor layouts via hypr keywords. Workspace moves still use connector names.
LAPTOP_MONITOR="eDP-2"                    # Your laptop display name
LAPTOP_DESC="BOE 0x0A3A"            # Optional: laptop description (exact, up to before the port in hyprctl)
EXTERNAL_MONITOR="DP-1"                   # Your external display name
EXTERNAL_DESC="Samsung Electric Company C24FG7x HTHK700065"        # Optional: first external description
EXTERNAL_RESOLUTION="1920x1080@60"        # External monitor resolution@refresh
LAPTOP_RESOLUTION="1920x1200@59.99"          # Laptop monitor resolution@refresh
EXTERNAL_SCALE="1"                     # External monitor scaling factor
LAPTOP_SCALE="1.25"                           # Laptop monitor scaling factor
EXTERNAL_POSITION="0x0"                   # External monitor position
LAPTOP_POSITION_DUAL="2300x0"            # Laptop position in dual mode
LAPTOP_POSITION_SOLO="0x0"               # Laptop position when alone
# Optional: monitor rotation/transform (0=normal, 1=90°, 2=180°, 3=270°, 4=flipped, 5=flipped+90°, 6=flipped+180°, 7=flipped+270°)
LAPTOP_TRANSFORM="0"
EXTERNAL_TRANSFORM="${EXTERNAL_TRANSFORM:-0}"
# Workspace distribution
EXTERNAL_WS="${EXTERNAL_WS:-1 2 3 4 5}"  # Workspaces for external monitor
LAPTOP_WS="${LAPTOP_WS:-6 7 8 9 10}"     # Workspaces for laptop monitor
# Optional: second external monitor settings (used when two externals connected)
EXTERNAL2_MONITOR="${EXTERNAL2_MONITOR:-}"       # Auto-detected if empty
EXTERNAL2_DESC="AOC 24G2W1G5 0x0000220C"      # Optional: second external description
EXTERNAL2_RESOLUTION="${EXTERNAL2_RESOLUTION:-1920x1080@60}"
EXTERNAL2_SCALE="1"
EXTERNAL2_POSITION="1920x-420"
EXTERNAL2_TRANSFORM="1"
# Workspace distribution for two externals
EXTERNAL1_WS="${EXTERNAL1_WS:-1 2 3 4 5 6 7}"
EXTERNAL2_WS="${EXTERNAL2_WS:-8 9 10}"
# ========== END CONFIGURATION SECTION ==========

# Debounce: single instance at a time
exec 9>/run/lid-switch.lock || true
if command -v flock >/dev/null 2>&1; then
  flock -n 9 || { log "Another lid handler instance running, exiting."; exit 0; }
fi

require_cmd() { command -v "$1" >/dev/null 2>&1 || { log "Missing command: $1"; exit 1; }; }
require_cmd hyprctl
require_cmd logger

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

monitor_connected_sysfs() {
  local connector="$1" path
  for path in /sys/class/drm/card*-"$connector"/status; do
    [ -r "$path" ] && grep -q '^connected' "$path" && return 0
  done
  return 1
}

monitor_connected_hypr() {
  local connector="$1"
  hypr monitors 2>/dev/null | awk -v name="$connector" '$1=="Monitor" && $2==name {found=1} END {exit !found}'
}

# Returns 0 if a monitor with the given description (up to before the portname)
# exists in `hyprctl monitors` output.
monitor_connected_hypr_desc() {
  local desc="$1"
  hypr monitors 2>/dev/null | awk -v d="$desc" '
    $1=="Monitor" && $2!="(ID" {cur=$2}
    $1=="description:" {
      line=$0
      sub(/^\s*description: /, "", line)
      sub(/ \(.*/, "", line)
      if (line==d) {found=1}
    }
    END {exit !found}
  '
}

monitor_connected() {
  local ident="$1"
  if printf '%s' "$ident" | grep -q '^desc:'; then
    local d=${ident#desc:}
    monitor_connected_hypr_desc "$d"
  else
    monitor_connected_sysfs "$ident" || monitor_connected_hypr "$ident"
  fi
}

# Resolve a connector name from a description; prints connector or empty if not found
connector_from_desc() {
  local desc="$1"
  hypr monitors 2>/dev/null | awk -v d="$desc" '
    $1=="Monitor" {name=$2}
    $1=="description:" {
      line=$0
      sub(/^\s*description: /, "", line)
      sub(/ \(.*/, "", line)
      if (line==d) {print name; exit 0}
    }
  '
}

# Return identifier to use in hypr keyword (desc:... if desc provided, else connector)
monitor_identifier() {
  local connector="$1"; local desc="$2"
  if [ -n "$desc" ]; then
    printf 'desc:%s' "$desc"
  else
    printf '%s' "$connector"
  fi
}

detect_external_monitor() {
  # Keep configured monitor if already connected
  if [ -n "${EXTERNAL_DESC:-}" ] && monitor_connected "desc:${EXTERNAL_DESC}"; then
    log "Using configured external by description: ${EXTERNAL_DESC}"
    # Try to resolve connector for workspace moves
    local conn
    conn=$(connector_from_desc "${EXTERNAL_DESC}" || true)
    if [ -n "$conn" ]; then EXTERNAL_MONITOR="$conn"; export EXTERNAL_MONITOR; fi
    return 0
  fi
  if [ -n "${EXTERNAL_MONITOR:-}" ] && monitor_connected "$EXTERNAL_MONITOR"; then
    log "Using configured external monitor: ${EXTERNAL_MONITOR}"
    return 0
  fi

  local path connector
  for path in /sys/class/drm/card*-DP-*/status; do
    [ -r "$path" ] || continue
    if grep -q '^connected' "$path"; then
      connector=$(basename "$(dirname "$path")")
      connector="${connector#*-}"
      EXTERNAL_MONITOR="$connector"
      export EXTERNAL_MONITOR
      log "Auto-detected external monitor via sysfs: ${EXTERNAL_MONITOR}"
      return 0
    fi
  done

  for path in /sys/class/drm/card*-HDMI-*/status; do
    [ -r "$path" ] || continue
    if grep -q '^connected' "$path"; then
      connector=$(basename "$(dirname "$path")")
      connector="${connector#*-}"
      EXTERNAL_MONITOR="$connector"
      export EXTERNAL_MONITOR
      log "Auto-detected external monitor via HDMI sysfs: ${EXTERNAL_MONITOR}"
      return 0
    fi
  done

  local hypr_candidate
  hypr_candidate=$(hypr monitors 2>/dev/null | awk -v skip="$LAPTOP_MONITOR" '$1=="Monitor" && $2!=skip {print $2; exit}')
  if [ -n "$hypr_candidate" ]; then
    EXTERNAL_MONITOR="$hypr_candidate"
    export EXTERNAL_MONITOR
    log "Auto-detected external monitor via hyprctl: ${EXTERNAL_MONITOR}"
    return 0
  fi

  log "Auto-detect failed: no connected external monitor found."
  return 1
}

# Discover two external monitors (names placed into EXTERNAL_MONITOR and EXTERNAL2_MONITOR)
detect_two_external_monitors() {
  local found=()
  local path connector

  # If descriptions are provided for both externals and they are present, resolve connectors and return
  if [ -n "${EXTERNAL_DESC:-}" ] && [ -n "${EXTERNAL2_DESC:-}" ]; then
    if monitor_connected "desc:${EXTERNAL_DESC}" && monitor_connected "desc:${EXTERNAL2_DESC}"; then
      local c1 c2
      c1=$(connector_from_desc "${EXTERNAL_DESC}" || true)
      c2=$(connector_from_desc "${EXTERNAL2_DESC}" || true)
      if [ -n "$c1" ] && [ -n "$c2" ]; then
        EXTERNAL_MONITOR="$c1"; EXTERNAL2_MONITOR="$c2"
        export EXTERNAL_MONITOR EXTERNAL2_MONITOR
        log "Resolved two externals by description: ${EXTERNAL_DESC}=>${EXTERNAL_MONITOR}, ${EXTERNAL2_DESC}=>${EXTERNAL2_MONITOR}"
        return 0
      fi
    fi
  fi

  # Prefer DP, then HDMI; gather up to two, skipping laptop panel
  for path in /sys/class/drm/card*-DP-*/status; do
    [ -r "$path" ] || continue
    if grep -q '^connected' "$path"; then
      connector=$(basename "$(dirname "$path")")
      connector="${connector#*-}"
      [ "$connector" = "$LAPTOP_MONITOR" ] && continue
      found+=("$connector")
    fi
  done

  if [ "${#found[@]}" -lt 2 ]; then
    for path in /sys/class/drm/card*-HDMI-*/status; do
      [ -r "$path" ] || continue
      if grep -q '^connected' "$path"; then
        connector=$(basename "$(dirname "$path")")
        connector="${connector#*-}"
        [ "$connector" = "$LAPTOP_MONITOR" ] && continue
        # Avoid duplicates
        if ! printf '%s\n' "${found[@]}" | grep -qx "$connector"; then
          found+=("$connector")
        fi
      fi
    done
  fi

  if [ "${#found[@]}" -ge 2 ]; then
    EXTERNAL_MONITOR="${found[0]}"
    EXTERNAL2_MONITOR="${found[1]}"
    export EXTERNAL_MONITOR EXTERNAL2_MONITOR
    log "Auto-detected two externals via sysfs: ${EXTERNAL_MONITOR}, ${EXTERNAL2_MONITOR}"
    return 0
  fi

  # Fallback to hyprctl monitor list
  local hypr_list
  hypr_list=$(hypr monitors 2>/dev/null | awk -v skip="$LAPTOP_MONITOR" '$1=="Monitor" && $2!=skip {print $2}')
  if [ -n "$hypr_list" ]; then
    EXTERNAL_MONITOR="$(printf '%s\n' $hypr_list | sed -n '1p')"
    EXTERNAL2_MONITOR="$(printf '%s\n' $hypr_list | sed -n '2p')"
  fi
  if [ -n "${EXTERNAL_MONITOR:-}" ] && [ -n "${EXTERNAL2_MONITOR:-}" ]; then
    export EXTERNAL_MONITOR EXTERNAL2_MONITOR
    log "Auto-detected two externals via hyprctl: ${EXTERNAL_MONITOR}, ${EXTERNAL2_MONITOR}"
    return 0
  fi

  return 1
}

two_externals_connected() {
  # Ensure env contains two external names if available
  [ -n "${EXTERNAL_MONITOR:-}" ] && [ -n "${EXTERNAL2_MONITOR:-}" ] || detect_two_external_monitors || true
  if [ -n "${EXTERNAL_MONITOR:-}" ] && [ -n "${EXTERNAL2_MONITOR:-}" ]; then
    monitor_connected "${EXTERNAL_MONITOR}" && monitor_connected "${EXTERNAL2_MONITOR}"
    return $?
  fi
  return 1
}

external_connected() {
  [ -n "${EXTERNAL_MONITOR:-}" ] || detect_external_monitor
  monitor_connected "${EXTERNAL_MONITOR:-}"
}

# Retry wrapper: wait for external to enumerate (docks/cables can be slow)
external_connected_retry() {
  local attempts="${1:-30}"
  local delay="${2:-0.15}"
  local i=0
  detect_external_monitor || true
  while [ "$i" -lt "$attempts" ]; do
    if external_connected; then
      return 0
    fi
    detect_external_monitor || true
    sleep "$delay"
    i=$((i+1))
  done
  return 1
}

move_ws_to_monitor() {
  local dest="$1"
  shift
  local ws
  for ws in "$@"; do
    hypr dispatch moveworkspacetomonitor "$ws" "$dest" >/dev/null 2>&1 || true
    sleep 0.05
  done
}

set_external_only() {
  # Enable external and disable laptop using configured values
  local ident
  ident=$(monitor_identifier "${EXTERNAL_MONITOR}" "${EXTERNAL_DESC}")
  if [ "${EXTERNAL_TRANSFORM:-0}" != "0" ]; then
    hypr keyword monitor "${ident},${EXTERNAL_RESOLUTION},${EXTERNAL_POSITION},${EXTERNAL_SCALE},transform,${EXTERNAL_TRANSFORM}"
  else
    hypr keyword monitor "${ident},${EXTERNAL_RESOLUTION},${EXTERNAL_POSITION},${EXTERNAL_SCALE}"
  fi
  sleep 0.25
  ident=$(monitor_identifier "${LAPTOP_MONITOR}" "${LAPTOP_DESC}")
  hypr keyword monitor "${ident},disable"
  sleep 0.25
}

set_two_externals_only() {
  # Enable both externals and disable laptop
  local ident1 ident2 identl
  ident1=$(monitor_identifier "${EXTERNAL_MONITOR}" "${EXTERNAL_DESC}")
  ident2=$(monitor_identifier "${EXTERNAL2_MONITOR}" "${EXTERNAL2_DESC}")
  identl=$(monitor_identifier "${LAPTOP_MONITOR}" "${LAPTOP_DESC}")
  if [ "${EXTERNAL_TRANSFORM:-0}" != "0" ]; then
    hypr keyword monitor "${ident1},${EXTERNAL_RESOLUTION},${EXTERNAL_POSITION},${EXTERNAL_SCALE},transform,${EXTERNAL_TRANSFORM}"
  else
    hypr keyword monitor "${ident1},${EXTERNAL_RESOLUTION},${EXTERNAL_POSITION},${EXTERNAL_SCALE}"
  fi
  sleep 0.25
  if [ "${EXTERNAL2_TRANSFORM:-0}" != "0" ]; then
    hypr keyword monitor "${ident2},${EXTERNAL2_RESOLUTION},${EXTERNAL2_POSITION},${EXTERNAL2_SCALE},transform,${EXTERNAL2_TRANSFORM}"
  else
    hypr keyword monitor "${ident2},${EXTERNAL2_RESOLUTION},${EXTERNAL2_POSITION},${EXTERNAL2_SCALE}"
  fi
  sleep 0.25
  hypr keyword monitor "${identl},disable"
  sleep 0.25
}

set_dual_layout() {
  # External and laptop both enabled, positions/scales from config
  local idente identl
  idente=$(monitor_identifier "${EXTERNAL_MONITOR}" "${EXTERNAL_DESC}")
  identl=$(monitor_identifier "${LAPTOP_MONITOR}" "${LAPTOP_DESC}")
  if [ "${EXTERNAL_TRANSFORM:-0}" != "0" ]; then
    hypr keyword monitor "${idente},${EXTERNAL_RESOLUTION},${EXTERNAL_POSITION},${EXTERNAL_SCALE},transform,${EXTERNAL_TRANSFORM}"
  else
    hypr keyword monitor "${idente},${EXTERNAL_RESOLUTION},${EXTERNAL_POSITION},${EXTERNAL_SCALE}"
  fi
  sleep 0.25
  if [ "${LAPTOP_TRANSFORM:-0}" != "0" ]; then
    hypr keyword monitor "${identl},${LAPTOP_RESOLUTION},${LAPTOP_POSITION_DUAL},${LAPTOP_SCALE},transform,${LAPTOP_TRANSFORM}"
  else
    hypr keyword monitor "${identl},${LAPTOP_RESOLUTION},${LAPTOP_POSITION_DUAL},${LAPTOP_SCALE}"
  fi
  sleep 0.25
}

set_laptop_only() {
  local idente identl
  idente=$(monitor_identifier "${EXTERNAL_MONITOR}" "${EXTERNAL_DESC}")
  identl=$(monitor_identifier "${LAPTOP_MONITOR}" "${LAPTOP_DESC}")
  hypr keyword monitor "${idente},disable"
  sleep 0.25
  if [ "${LAPTOP_TRANSFORM:-0}" != "0" ]; then
    hypr keyword monitor "${identl},${LAPTOP_RESOLUTION},${LAPTOP_POSITION_SOLO},${LAPTOP_SCALE},transform,${LAPTOP_TRANSFORM}"
  else
    hypr keyword monitor "${identl},${LAPTOP_RESOLUTION},${LAPTOP_POSITION_SOLO},${LAPTOP_SCALE}"
  fi
  sleep 0.25
}

reassert_primary_external() {
  sleep 0.60
  hypr dispatch focusmonitor "${EXTERNAL_MONITOR}"
  hypr dispatch workspace 1
  sleep 0.10
}

notify() {
  if command -v notify-send >/dev/null 2>&1; then
    run_as_hypr notify-send "$@"
  fi
}
