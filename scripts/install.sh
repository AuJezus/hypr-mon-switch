#!/usr/bin/env bash
set -euo pipefail

# Monitor Auto-Switch Installer
# Installs the configuration-based monitor switching system for Hyprland

# Defaults (can be overridden by flags)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

# Detect if running from package installation
if [ -d "/usr/share/hypr-mon-switch" ] && [ -f "/etc/acpi/hypr-utils.sh" ] && [ -f "/etc/acpi/config-parser.sh" ]; then
  # Running from package installation
  REPO_ACPI_DIR="/etc/acpi"
  REPO_CONFIGS_DIR="/etc/hypr-mon-switch"
else
  # Running from development directory
  REPO_ACPI_DIR="${REPO_ROOT}/acpi"
  REPO_CONFIGS_DIR="${REPO_ROOT}/configs"
fi
DEST_DIR="/etc/acpi"
EVENTS_DIR="/etc/acpi/events"
CONFIG_DIR="/etc/hypr-mon-switch"
LOG_FILE="/var/log/hypr-mon-switch.log"
NO_RESTART=0
DRY_RUN=0
CONFIG_FILE=""

usage() {
  cat <<EOF
Usage: sudo $(basename "$0") [options]

Options:
  -s, --src DIR            Source directory containing ACPI scripts (default: auto-detect)
  -d, --dest DIR           Destination directory for scripts (default: /etc/acpi)
      --events-dir DIR     Destination directory for ACPI events (default: /etc/acpi/events)
      --config-dir DIR     Destination directory for config files (default: /etc/hypr-mon-switch)
  -c, --config FILE        Configuration file to install (default: default-config.yaml)
  -n, --dry-run            Print what would be done, do not write
      --no-restart         Do not restart acpid after installing
  -h, --help               Show this help and exit

Examples:
  sudo $(basename "$0")                                    # Install with specific config
  sudo $(basename "$0") --config default-config.yaml      # Install with default config
  sudo $(basename "$0") -n                                # dry-run
EOF
}

# Parse args early (before sudo checks so --help works without root)
parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      -s|--src)
        REPO_ACPI_DIR="${2:-}"; shift 2 || { echo "Missing value for $1" >&2; exit 2; };
        ;;
      -d|--dest)
        DEST_DIR="${2:-}"; shift 2 || { echo "Missing value for $1" >&2; exit 2; };
        ;;
      --events-dir)
        EVENTS_DIR="${2:-}"; shift 2 || { echo "Missing value for $1" >&2; exit 2; };
        ;;
      --config-dir)
        CONFIG_DIR="${2:-}"; shift 2 || { echo "Missing value for $1" >&2; exit 2; };
        ;;
      -c|--config)
        CONFIG_FILE="${2:-}"; shift 2 || { echo "Missing value for $1" >&2; exit 2; };
        ;;
      -n|--dry-run)
        DRY_RUN=1; shift ;;
      --no-restart)
        NO_RESTART=1; shift ;;
      -h|--help)
        usage; exit 0 ;;
      *)
        echo "Unknown option: $1" >&2
        usage
        exit 2
        ;;
    esac
  done
}

need_sudo() {
  if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    echo "Please run as root: sudo $0 [options]" >&2
    exit 1
  fi
}

say() { printf '%s\n' "$*"; }

run_as_user() {
  local user="$1"; shift
  if command -v runuser >/dev/null 2>&1; then
    runuser -u "$user" -- "$@"
  else
    sudo -u "$user" "$@"
  fi
}

backup_if_changed() {
  local src="$1" dest="$2"
  if [ -f "$dest" ] && ! cmp -s "$src" "$dest"; then
    if [ "$DRY_RUN" = 1 ]; then
      say "Would back up $dest -> ${dest}.backup"
    else
      cp -av "$dest" "${dest}.backup"
    fi
  fi
}

install_file() {
  local src="$1" dest="$2" mode="$3"
  if [ "$DRY_RUN" = 1 ]; then
    say "Would install $src -> $dest (mode $mode)"
  else
    install -m "$mode" -o root -g root "$src" "$dest"
  fi
}

install_system() {
  mkdir -p "$DEST_DIR" "$EVENTS_DIR" "$CONFIG_DIR"

  # Check if running from package installation (files already in /etc/acpi/)
  if [ -f "$DEST_DIR/hypr-utils.sh" ] && [ -f "$DEST_DIR/monitor-hotplug.sh" ]; then
    say "ACPI scripts already installed in $DEST_DIR"
    # Just create the symlink if it doesn't exist
    if [ ! -L "$DEST_DIR/monitor-hotplug-config.sh" ]; then
      if [ "$DRY_RUN" = 1 ]; then
        say "Would create symlink: $DEST_DIR/monitor-hotplug-config.sh -> $DEST_DIR/monitor-hotplug.sh"
      else
        ln -sf "$DEST_DIR/monitor-hotplug.sh" "$DEST_DIR/monitor-hotplug-config.sh"
      fi
    fi
    # Continue with the rest of the setup process even when files are already installed
  else
    # Running from development directory - install ACPI scripts
    backup_if_changed "$REPO_ACPI_DIR/hypr-utils.sh" "$DEST_DIR/hypr-utils.sh"
    install_file      "$REPO_ACPI_DIR/hypr-utils.sh" "$DEST_DIR/hypr-utils.sh" 0755

    backup_if_changed "$REPO_ACPI_DIR/lid-open.sh" "$DEST_DIR/lid-open.sh"
    install_file      "$REPO_ACPI_DIR/lid-open.sh"  "$DEST_DIR/lid-open.sh"  0755

    backup_if_changed "$REPO_ACPI_DIR/lid-close.sh" "$DEST_DIR/lid-close.sh"
    install_file      "$REPO_ACPI_DIR/lid-close.sh" "$DEST_DIR/lid-close.sh" 0755

    backup_if_changed "$REPO_ACPI_DIR/check-lid-on-startup.sh" "$DEST_DIR/check-lid-on-startup.sh"
    install_file      "$REPO_ACPI_DIR/check-lid-on-startup.sh" "$DEST_DIR/check-lid-on-startup.sh" 0755

    backup_if_changed "$REPO_ACPI_DIR/monitor-hotplug.sh" "$DEST_DIR/monitor-hotplug.sh"
    install_file      "$REPO_ACPI_DIR/monitor-hotplug.sh" "$DEST_DIR/monitor-hotplug.sh" 0755
    
    # Create symlink for monitor-hotplug-config.sh
    if [ "$DRY_RUN" = 1 ]; then
      say "Would create symlink: $DEST_DIR/monitor-hotplug-config.sh -> $DEST_DIR/monitor-hotplug.sh"
    else
      ln -sf "$DEST_DIR/monitor-hotplug.sh" "$DEST_DIR/monitor-hotplug-config.sh"
    fi
  fi

  # Install config parser to both locations for compatibility
  if [ -f "$DEST_DIR/config-parser.sh" ]; then
    say "Config parser already installed in $DEST_DIR"
  else
    backup_if_changed "$REPO_ROOT/scripts/config-parser.sh" "$DEST_DIR/config-parser.sh"
    install_file      "$REPO_ROOT/scripts/config-parser.sh" "$DEST_DIR/config-parser.sh" 0755
  fi
  
  # Also install to config directory for hypr-utils.sh compatibility
  if [ -f "$CONFIG_DIR/config-parser.sh" ]; then
    say "Config parser already installed in $CONFIG_DIR"
  else
    backup_if_changed "$REPO_ROOT/scripts/config-parser.sh" "$CONFIG_DIR/config-parser.sh"
    install_file      "$REPO_ROOT/scripts/config-parser.sh" "$CONFIG_DIR/config-parser.sh" 0755
  fi

  # Install configuration files
  if [ -f "$CONFIG_DIR/config.yaml" ]; then
    say "Configuration file already installed in $CONFIG_DIR"
  else
    local config_file="${CONFIG_FILE:-example-config.yaml}"
    if [ -f "$REPO_CONFIGS_DIR/$config_file" ]; then
      backup_if_changed "$REPO_CONFIGS_DIR/$config_file" "$CONFIG_DIR/config.yaml"
      install_file      "$REPO_CONFIGS_DIR/$config_file" "$CONFIG_DIR/config.yaml" 0644
    else
      say "Warning: Configuration file $config_file not found in $REPO_CONFIGS_DIR"
      say "Available configs:"
      ls -1 "$REPO_CONFIGS_DIR"/*.yaml 2>/dev/null || say "  (none found)"
    fi
  fi

  # Install all example configs
  for config in "$REPO_CONFIGS_DIR"/*.yaml; do
    [ -f "$config" ] || continue
    local basename_config
    basename_config=$(basename "$config")
    install_file "$config" "$CONFIG_DIR/$basename_config" 0644
  done
}

update_events() {
  if [ "$DRY_RUN" = 1 ]; then
    say "Would write $EVENTS_DIR/lid-close with event"
    say "Would write $EVENTS_DIR/lid-open with event"
  else
    install -m 0644 -o root -g root /dev/stdin "$EVENTS_DIR/lid-close" <<'EOF'
event=button/lid.*close
action=/etc/acpi/lid-close.sh
EOF
    install -m 0644 -o root -g root /dev/stdin "$EVENTS_DIR/lid-open" <<'EOF'
event=button/lid.*open
action=/etc/acpi/lid-open.sh
EOF
  fi
}

update_udev_rules() {
  local UDEV_RULE="/etc/udev/rules.d/99-monitor-hotplug.rules"
  local TARGET_USER="${SUDO_USER:-$(logname 2>/dev/null || echo "${USER:-}")}"

  if [ "$DRY_RUN" = 1 ]; then
    say "Would write $UDEV_RULE to trigger /etc/acpi/monitor-hotplug-config.sh on hotplug"
  else
    if [ -n "$TARGET_USER" ] && [ "$TARGET_USER" != "root" ]; then
      install -m 0644 -o root -g root /dev/stdin "$UDEV_RULE" <<EOF
# Monitor hotplug rule for hypr-mon-switch
# Triggers monitor layout changes when displays are connected/disconnected
ACTION=="change", SUBSYSTEM=="drm", RUN+="/bin/su $TARGET_USER -c '/etc/acpi/monitor-hotplug-config.sh'"
EOF
    else
      install -m 0644 -o root -g root /dev/stdin "$UDEV_RULE" <<'EOF'
# Monitor hotplug rule for hypr-mon-switch
# Triggers monitor layout changes when displays are connected/disconnected
ACTION=="change", SUBSYSTEM=="drm", RUN+="/etc/acpi/monitor-hotplug-config.sh"
EOF
    fi
  fi
  
  # Reload udev rules
  if command -v udevadm >/dev/null 2>&1; then
    if [ "$DRY_RUN" = 1 ]; then
      say "Would reload udev rules"
    else
      udevadm control --reload || true
      udevadm trigger -s drm || true
    fi
  fi
}

post_install() {
  # Ensure log file exists and is writable by both root and user sessions
  if [ "$DRY_RUN" = 1 ]; then
    say "Would touch $LOG_FILE and chmod 666"
  else
    touch "$LOG_FILE"
    chmod 666 "$LOG_FILE" || true
  fi

  if [ "$NO_RESTART" = 1 ]; then
    say "Skipping acpid restart (--no-restart)"
  else
    if [ "$DRY_RUN" = 1 ]; then
      say "Would restart acpid"
    else
      if command -v systemctl >/dev/null 2>&1; then
        systemctl restart acpid || {
          echo "Warning: could not restart acpid. Ensure it is installed and running." >&2
        }
      else
        echo "Note: systemctl not found; please restart acpid manually if needed." >&2
      fi
    fi
  fi

  # Install udev rule for DRM hotplug events
  local UDEV_RULE="/etc/udev/rules.d/99-monitor-hotplug.rules"
  local TARGET_USER="${SUDO_USER:-$(logname 2>/dev/null || echo "${USER:-}")}"
  
  if [ "$DRY_RUN" = 1 ]; then
    say "Would write $UDEV_RULE to trigger /etc/acpi/monitor-hotplug-config.sh on hotplug"
  else
    if [ -n "$TARGET_USER" ] && [ "$TARGET_USER" != "root" ]; then
      install -m 0644 -o root -g root /dev/stdin "$UDEV_RULE" <<EOF
# Monitor hotplug rule for hypr-mon-switch
# Triggers monitor layout changes when displays are connected/disconnected
ACTION=="change", SUBSYSTEM=="drm", RUN+="/bin/su $TARGET_USER -c '/etc/acpi/monitor-hotplug-config.sh'"
EOF
    else
      install -m 0644 -o root -g root /dev/stdin "$UDEV_RULE" <<'EOF'
# Monitor hotplug rule for hypr-mon-switch
# Triggers monitor layout changes when displays are connected/disconnected
ACTION=="change", SUBSYSTEM=="drm", RUN+="/etc/acpi/monitor-hotplug-config.sh"
EOF
    fi
  fi
    # Reload udev rules
    if command -v udevadm >/dev/null 2>&1; then
      udevadm control --reload || true
      udevadm trigger -s drm || true
    fi
}

ensure_hyprland_hooks() {
  local target_user
  target_user="${SUDO_USER:-$(logname 2>/dev/null || echo "${USER:-}")}"
  if [ -z "$target_user" ] || [ "$target_user" = "root" ]; then
    say "Skipping Hyprland hook: unable to determine non-root user context"
    return
  fi

  local target_home
  target_home=$(getent passwd "$target_user" | cut -d: -f6 2>/dev/null || true)
  if [ -z "$target_home" ]; then
    target_home=$(eval echo "~$target_user")
  fi
  if [ -z "$target_home" ]; then
    say "Skipping Hyprland hook: could not resolve home for $target_user"
    return
  fi

  local candidates=(
    "$target_home/.config/hypr/hyprland.conf"
    "$target_home/.config/omarchy/current/theme/hyprland.conf"
  )

  local updated=0
  for conf in "${candidates[@]}"; do
    [ -f "$conf" ] || continue
    if grep -Fq "/etc/acpi/check-lid-on-startup.sh" "$conf"; then
      say "Hyprland hook already present in $conf"
      continue
    fi

    if [ "$DRY_RUN" = 1 ]; then
      say "Would append Hyprland auto-switch hook to $conf"
    else
      say "Appending Hyprland auto-switch hook to $conf"
      run_as_user "$target_user" bash -c "cat <<'EOF' >> '$conf'

# Monitor auto-switch startup hook (managed by install.sh)
exec-once = /etc/acpi/check-lid-on-startup.sh
exec = /etc/acpi/check-lid-on-startup.sh
EOF"
    fi
    updated=1
  done

  if [ "$updated" -eq 0 ]; then
    say "Note: No Hyprland config files were updated automatically; add the exec hooks manually if needed."
  fi
}

invoke_startup_check() {
  if [ "$DRY_RUN" = 1 ]; then
    say "Would run ${DEST_DIR}/check-lid-on-startup.sh to synchronise layout immediately"
    return
  fi

  if ! command -v pgrep >/dev/null 2>&1; then
    say "pgrep not available; skipping immediate startup check"
    return
  fi

  if pgrep -x Hyprland >/dev/null 2>&1; then
    say "Hyprland detected; running ${DEST_DIR}/check-lid-on-startup.sh for immediate layout sync"
    if ! "${DEST_DIR}/check-lid-on-startup.sh"; then
      echo "Warning: ${DEST_DIR}/check-lid-on-startup.sh exited with a non-zero status." >&2
    fi
  else
    say "Hyprland not running; skipping immediate startup check"
  fi
}

validate_src() {
  local missing=0
  for f in hypr-utils.sh lid-open.sh lid-close.sh check-lid-on-startup.sh monitor-hotplug.sh; do
    if [ ! -f "$REPO_ACPI_DIR/$f" ]; then
      echo "Missing: $REPO_ACPI_DIR/$f" >&2
      missing=1
    fi
  done
  if [ ! -f "$REPO_ACPI_DIR/config-parser.sh" ]; then
    echo "Missing: $REPO_ACPI_DIR/config-parser.sh" >&2
    missing=1
  fi
  if [ "$missing" = 1 ]; then
    echo "Source directory invalid. Use --src DIR to point at the directory containing the ACPI scripts." >&2
    exit 1
  fi
}

main() {
  parse_args "$@"

  # Allow --help without root
  if [ "$DRY_RUN" != 1 ]; then
    need_sudo
  fi

  validate_src
  install_system
  update_events
  update_udev_rules
  post_install
  ensure_hyprland_hooks
  invoke_startup_check

  say "Install complete."
  say "Configuration system installed. Edit $CONFIG_DIR/config.yaml to customize."
  say ""
  say "Testing installation..."
  if [ -f "${DEST_DIR}/config-parser.sh" ]; then
    say "Available configurations:"
    "${DEST_DIR}/config-parser.sh" list "$CONFIG_DIR/config.yaml" 2>/dev/null || true
    say ""
    say "Note: Configuration matching requires running as the Hyprland user."
    say "The system will work correctly when triggered by udev events."
  fi
  say ""
  say "Installation verified. The system is ready to use!"
  say "Monitor switching will work automatically when you connect/disconnect displays."
}

main "$@"