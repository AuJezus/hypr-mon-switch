# Hyprland Monitor Auto-Switch

A configuration-based monitor switching system for Hyprland that automatically adjusts monitor layouts based on lid state and connected displays.

## Todo

- [ ] Add support for monitor connectors like eDP-*
- [ ] Make the switching faster
- [ ] Refactor code

## Features

- **Configuration-based**: Define monitor layouts using YAML configuration files
- **Conditional matching**: Automatically select the best configuration based on:
  - Laptop lid state (open/closed)
  - Connected monitors (by name, description, or connector)
- **Flexible monitor detection**: Works with monitor names, descriptions, or connectors
- **Workspace management**: Automatically distributes workspaces across monitors
- **Hotplug support**: Responds to monitor connect/disconnect events
- **ACPI integration**: Handles laptop lid open/close events

## Installation

### AUR Installation (Recommended)

```bash
# Install from AUR
yay -S hypr-mon-switch-git
# or
paru -S hypr-mon-switch-git

# Complete setup after package installation
sudo /usr/share/hypr-mon-switch/scripts/install.sh
```

### Manual Installation

```bash
# Clone the repository
git clone https://github.com/aujezus/hypr-mon-switch.git
cd hypr-mon-switch

# Install with default configuration
sudo ./scripts/install.sh

# Or install with a specific configuration
sudo ./scripts/install.sh --config example-config.yaml
```

### Uninstallation

```bash
# If installed from AUR
yay -R hypr-mon-switch-git
# or
paru -R hypr-mon-switch-git

# Manual uninstall
sudo /usr/share/hypr-mon-switch/scripts/uninstall.sh
```

## Configuration

The configuration system uses YAML files to define monitor layouts. Configuration files are located in `/etc/hypr-mon-switch/` by default.

### Configuration File Structure

```yaml
global:
  # Default workspace distribution
  default_workspaces:
    external: [1, 2, 3, 4, 5]
    laptop: [6, 7, 8, 9, 10]
  
  # Retry settings for monitor detection
  detection:
    max_attempts: 40
    delay: 0.10
  
  # Notification settings
  notifications:
    enabled: true
    timeout: 5000

configurations:
  - name: "laptop-closed-samsung"
    conditions:
      lid_state: "closed"
      monitors:
        - name: "Samsung"
          description: "Samsung Electric Company C24FG7x"
          connector: "DP-1"
    layout:
      enabled_monitors:
        - name: "Samsung"
          description: "Samsung Electric Company C24FG7x"
          connector: "DP-1"
          resolution: "1920x1080@60"
          position: "0x0"
          scale: 1.0
          transform: 0
          workspaces: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
      disabled_monitors:
        - name: "laptop"
          description: "BOE 0x0A3A"
          connector: "eDP-2"
```

### Configuration Options

#### Global Settings

- `default_workspaces`: Default workspace distribution for external and laptop monitors
- `detection.max_attempts`: Maximum attempts for monitor detection
- `detection.delay`: Delay between detection attempts (seconds)
- `notifications.enabled`: Enable desktop notifications
- `notifications.timeout`: Notification timeout (milliseconds)

#### Monitor Conditions

Each configuration can specify conditions that must be met:

- `lid_state`: "open" or "closed" (optional)
- `monitors`: List of required monitors with:
  - `name`: Monitor name (partial match in description)
  - `description`: Exact monitor description
  - `connector`: Monitor connector (e.g., "DP-1", "HDMI-A-1", "eDP-2")

#### Monitor Layout

For each enabled monitor, specify:

- `name`: Display name
- `description`: Monitor description (for identification)
- `connector`: Monitor connector
- `resolution`: Resolution and refresh rate (e.g., "1920x1080@60")
- `position`: Monitor position (e.g., "0x0", "2300x0")
- `scale`: Scaling factor (e.g., 1.0, 1.25)
- `transform`: Rotation/transform (0=normal, 1=90°, 2=180°, 3=270°, etc.)
- `workspaces`: List of workspaces to assign to this monitor

For disabled monitors, only `name`, `description`, and `connector` are needed.

## Usage

### Command Line

```bash
# Apply the best matching configuration
sudo /etc/acpi/hypr-utils.sh apply

# Apply a specific configuration
sudo /etc/acpi/hypr-utils.sh apply "laptop-closed-samsung"

# List available configurations
sudo /etc/acpi/hypr-utils.sh list

# Find the best matching configuration
sudo /etc/acpi/hypr-utils.sh find
```

### Configuration Parser

The configuration parser can be used directly:

```bash
# Find matching configuration
sudo /etc/acpi/config-parser.sh find /etc/hypr-mon-switch/config.yaml

# Apply specific configuration
sudo /etc/acpi/config-parser.sh apply /etc/hypr-mon-switch/config.yaml "laptop-closed-samsung"

# List configurations
sudo /etc/acpi/config-parser.sh list /etc/hypr-mon-switch/config.yaml
```

## Example Configurations

### Default Configuration

The `default-config.yaml` provides a generic configuration that works with most setups:

- Automatically detects external monitors
- Handles laptop lid open/closed states
- Provides sensible defaults for workspace distribution

### Example Configuration

The `example-config.yaml` shows advanced configuration features:

- Multiple monitor combinations
- Specific monitor descriptions and connectors
- Complex workspace distributions
- Demonstrates all available configuration options

## Troubleshooting

### Check Configuration

```bash
# Test configuration parsing
sudo /etc/acpi/config-parser.sh list /etc/hypr-mon-switch/config.yaml

# Check for matching configuration
sudo /etc/acpi/hypr-utils.sh find
```

### Monitor Detection

```bash
# List connected monitors
hyprctl monitors

# Check monitor descriptions
hyprctl monitors | grep description
```

### Logs

Check system logs for monitor switching events:

```bash
# View recent logs
journalctl -u acpid -f

# Or check the log file
tail -f /var/log/hypr-mon-switch.log
```

### Common Issues

1. **No matching configuration found**: Check that your monitor descriptions and connectors match the configuration
2. **Configuration not applied**: Ensure yq is installed (`pacman -S yq`)
3. **Monitors not detected**: Check that Hyprland is running and monitors are properly connected

## Dependencies

- `hyprctl` (part of Hyprland)
- `yq` (YAML processor)
- `acpid` (for ACPI events)
- `systemd` (for service management)

## File Structure

```
hypr-mon-switch/
├── acpi/                          # ACPI event scripts
│   ├── hypr-utils.sh             # Main configuration system
│   ├── lid-open.sh               # Lid open handler
│   ├── lid-close.sh              # Lid close handler
│   ├── monitor-hotplug.sh        # Hotplug handler
│   └── check-lid-on-startup.sh   # Startup handler
├── scripts/
│   ├── config-parser.sh          # Configuration parser
│   ├── install.sh                # Installation script
│   ├── generate-config.sh        # Configuration generator
│   └── test-config.sh            # Test script
├── configs/
│   ├── default-config.yaml       # Generic configuration (default)
│   └── example-config.yaml       # Comprehensive example
└── README.md                     # This file
```

## Configuration Setup

1. Generate a configuration for your setup:
   ```bash
   sudo ./scripts/generate-config.sh
   ```

2. Review and edit the generated configuration:
   ```bash
   sudo nano /etc/hypr-mon-switch/config.yaml
   ```

3. Test the configuration:
   ```bash
   sudo /etc/acpi/hypr-utils.sh apply
   ```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## License

This project is licensed under the MIT License - see the LICENSE file for details.
