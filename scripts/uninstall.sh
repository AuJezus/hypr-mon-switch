#!/usr/bin/env bash
set -euo pipefail

# Hyprland Monitor Auto-Switch Uninstaller
# Removes all files installed by the hypr-mon-switch package

# Defaults
DEST_DIR="/etc/acpi"
EVENTS_DIR="/etc/acpi/events"
CONFIG_DIR="/etc/hypr-mon-switch"
UDEV_RULE="/etc/udev/rules.d/99-monitor-hotplug.rules"
LOG_FILE="/var/log/hypr-mon-switch.log"
NO_BACKUP=0
DRY_RUN=0

usage() {
  cat <<EOF
Usage: sudo $(basename "$0") [options]

Options:
  -n, --dry-run            Print what would be removed, do not actually remove
      --no-backup          Do not create backup of configuration files
  -h, --help               Show this help and exit

Examples:
  sudo $(basename "$0")                    # Uninstall with backup
  sudo $(basename "$0") --no-backup        # Uninstall without backup
  sudo $(basename "$0") -n                 # Dry run (show what would be removed)
EOF
}

parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      -n|--dry-run)
        DRY_RUN=1; shift ;;
      --no-backup)
        NO_BACKUP=1; shift ;;
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

remove_file() {
  local file="$1"
  local description="${2:-$file}"
  
  if [ -f "$file" ] || [ -L "$file" ]; then
    if [ "$DRY_RUN" = 1 ]; then
      say "Would remove: $description"
    else
      rm -f "$file"
      say "Removed: $description"
    fi
  else
    if [ "$DRY_RUN" = 1 ]; then
      say "Would remove: $description (not found)"
    fi
  fi
}

remove_directory() {
  local dir="$1"
  local description="${2:-$dir}"
  
  if [ -d "$dir" ]; then
    if [ "$DRY_RUN" = 1 ]; then
      say "Would remove directory: $description"
    else
      rm -rf "$dir"
      say "Removed directory: $description"
    fi
  else
    if [ "$DRY_RUN" = 1 ]; then
      say "Would remove directory: $description (not found)"
    fi
  fi
}

backup_config() {
  if [ "$NO_BACKUP" = 1 ]; then
    return
  fi
  
  local backup_dir="/tmp/hypr-mon-switch-backup-$(date +%Y%m%d-%H%M%S)"
  
  if [ -d "$CONFIG_DIR" ]; then
    if [ "$DRY_RUN" = 1 ]; then
      say "Would create backup: $backup_dir"
    else
      mkdir -p "$backup_dir"
      cp -r "$CONFIG_DIR" "$backup_dir/"
      say "Configuration backed up to: $backup_dir"
    fi
  fi
}

remove_acpi_scripts() {
  say "Removing ACPI scripts..."
  remove_file "$DEST_DIR/hypr-utils.sh" "ACPI script: hypr-utils.sh"
  remove_file "$DEST_DIR/monitor-hotplug.sh" "ACPI script: monitor-hotplug.sh"
  remove_file "$DEST_DIR/monitor-hotplug-config.sh" "ACPI script: monitor-hotplug-config.sh"
  remove_file "$DEST_DIR/config-parser.sh" "ACPI script: config-parser.sh"
  remove_file "$DEST_DIR/lid-open.sh" "ACPI script: lid-open.sh"
  remove_file "$DEST_DIR/lid-close.sh" "ACPI script: lid-close.sh"
  remove_file "$DEST_DIR/check-lid-on-startup.sh" "ACPI script: check-lid-on-startup.sh"
}

remove_acpi_events() {
  say "Removing ACPI events..."
  remove_file "$EVENTS_DIR/lid-open" "ACPI event: lid-open"
  remove_file "$EVENTS_DIR/lid-close" "ACPI event: lid-close"
}

remove_udev_rules() {
  say "Removing udev rules..."
  remove_file "$UDEV_RULE" "Udev rule: 99-monitor-hotplug.rules"
}

remove_configuration() {
  say "Removing configuration files..."
  remove_directory "$CONFIG_DIR" "Configuration directory: $CONFIG_DIR"
}

remove_log_file() {
  say "Removing log file..."
  remove_file "$LOG_FILE" "Log file: $LOG_FILE"
}

reload_udev_rules() {
  if [ "$DRY_RUN" = 1 ]; then
    say "Would reload udev rules"
  else
    if command -v udevadm >/dev/null 2>&1; then
      udevadm control --reload-rules 2>/dev/null || true
      say "Reloaded udev rules"
    fi
  fi
}

remove_hyprland_hooks() {
  say "Removing Hyprland hooks..."
  
  # Note: We don't automatically remove hooks from user config files
  # as they might have been modified by the user
  say "Note: Hyprland hooks in user config files are not automatically removed."
  say "You may need to manually remove these lines from your Hyprland config:"
  say "  exec-once = /etc/acpi/check-lid-on-startup.sh"
  say "  exec = /etc/acpi/check-lid-on-startup.sh"
}

main() {
  parse_args "$@"
  
  if [ "$DRY_RUN" != 1 ]; then
    need_sudo
  fi
  
  say "=== Hyprland Monitor Auto-Switch Uninstaller ==="
  
  if [ "$DRY_RUN" = 1 ]; then
    say "DRY RUN MODE - Nothing will actually be removed"
    say ""
  fi
  
  backup_config
  remove_acpi_scripts
  remove_acpi_events
  remove_udev_rules
  remove_configuration
  remove_log_file
  reload_udev_rules
  remove_hyprland_hooks
  
  say ""
  if [ "$DRY_RUN" = 1 ]; then
    say "=== Dry Run Complete ==="
    say "Run without --dry-run to actually remove files"
  else
    say "=== Uninstall Complete ==="
    say "Hyprland Monitor Auto-Switch has been completely removed."
    if [ "$NO_BACKUP" = 0 ]; then
      say "Configuration files have been backed up."
    fi
  fi
}

main "$@"
