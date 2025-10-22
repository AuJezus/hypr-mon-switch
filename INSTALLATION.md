# hypr-mon-switch Installation Guide

This guide covers installing and configuring hypr-mon-switch for system-wide hotplug functionality.

## Prerequisites

- **Hyprland**: Running Hyprland compositor
- **yq**: YAML processor (version 3.x or 4.x)
- **bash**: Bash shell (version 4.0+)
- **sudo**: Root privileges for system installation

## Installation Steps

### 1. Install Dependencies

```bash
# Install yq (if not already installed)
# For Arch Linux:
sudo pacman -S yq

# For Ubuntu/Debian:
sudo apt install yq

# For other distributions, check: https://github.com/mikefarah/yq
```

### 2. System Installation

```bash
# Navigate to the project directory
cd /path/to/hypr-mon-switch

# Create system directories
sudo mkdir -p /etc/hypr-mon-switch /etc/acpi

# Install scripts
sudo cp acpi/monitor-hotplug.sh /etc/acpi/monitor-hotplug.sh
sudo cp acpi/hypr-utils.sh /etc/acpi/hypr-utils.sh
sudo cp scripts/config-parser.sh /etc/hypr-mon-switch/config-parser.sh

# Install configuration files
sudo cp configs/example-config.yaml /etc/hypr-mon-switch/config.yaml
sudo cp configs/default-config.yaml /etc/hypr-mon-switch/default-config.yaml

# Set proper permissions
sudo chmod +x /etc/acpi/monitor-hotplug.sh
sudo chmod +x /etc/acpi/hypr-utils.sh
sudo chmod +x /etc/hypr-mon-switch/config-parser.sh
sudo chown -R root:root /etc/hypr-mon-switch/
```

### 3. Configure ACPI Events

Create the ACPI event rule:

```bash
# Create udev rule for monitor hotplug events
sudo tee /etc/udev/rules.d/99-monitor-hotplug.rules > /dev/null << 'EOF'
# Monitor hotplug detection
SUBSYSTEM=="drm", ACTION=="change", RUN+="/etc/acpi/monitor-hotplug.sh"
EOF

# Reload udev rules
sudo udevadm control --reload-rules
sudo udevadm trigger
```

### 4. Configure Your Monitor Setup

Edit the configuration file to match your monitor setup:

```bash
sudo nano /etc/hypr-mon-switch/config.yaml
```

The configuration file uses YAML format with the following structure:

```yaml
# Global settings
global:
  detection:
    max_attempts: 40
    delay: 0.10
  notifications:
    enabled: true
    timeout: 5000

# Monitor configurations
configurations:
  - name: "your-config-name"
    conditions:
      lid_state: "open"  # optional: "open" or "closed"
      monitors:
        - name: "Monitor1"
          connector: "desc:Monitor Description"
        - name: "Monitor2"
          connector: "DP-1"  # or port name
    layout:
      enabled_monitors:
        - name: "Monitor1"
          resolution: "1920x1080@60"
          position: "0x0"
          scale: 1.0
          transform: 0
          workspaces: [1, 2, 3]
        - name: "Monitor2"
          resolution: "1920x1080@60"
          position: "1920x0"
          scale: 1.0
          transform: 0
          workspaces: [4, 5, 6]
      disabled_monitors:
        - connector: "desc:Laptop Monitor"
```

### 5. Test the Installation

Test the hotplug system:

```bash
# Test configuration detection
sudo /etc/acpi/hypr-utils.sh find

# Test specific configuration
sudo /etc/acpi/hypr-utils.sh apply "your-config-name"

# Test hotplug script
sudo /etc/acpi/monitor-hotplug.sh
```

### 6. Monitor Logs

Check system logs for debugging:

```bash
# View hypr-mon-switch logs
journalctl -t hypr-mon-switch -f

# View recent logs
journalctl -t hypr-mon-switch --since "1 hour ago"
```

## Configuration Examples

### Laptop + External Monitor (Lid Open)
```yaml
- name: "laptop-external"
  conditions:
    lid_state: "open"
    monitors:
      - name: "External"
        connector: "desc:Your External Monitor"
      - name: "Laptop"
        connector: "desc:Your Laptop Monitor"
  layout:
    enabled_monitors:
      - name: "External"
        resolution: "1920x1080@60"
        position: "0x0"
        workspaces: [1, 2, 3, 4, 5]
      - name: "Laptop"
        resolution: "1920x1200@60"
        position: "1920x0"
        workspaces: [6, 7, 8, 9, 10]
```

### Dual External Monitors (Laptop Disabled)
```yaml
- name: "dual-external"
  conditions:
    monitors:
      - name: "Monitor1"
        connector: "desc:First External Monitor"
      - name: "Monitor2"
        connector: "desc:Second External Monitor"
  layout:
    enabled_monitors:
      - name: "Monitor1"
        resolution: "1920x1080@60"
        position: "0x0"
        workspaces: [1, 2, 3, 4, 5, 6, 7]
      - name: "Monitor2"
        resolution: "1920x1080@60"
        position: "1920x-420"
        transform: 1  # 90-degree rotation
        workspaces: [8, 9, 10]
    disabled_monitors:
      - connector: "desc:Laptop Monitor"
```

## Troubleshooting

### Common Issues

1. **"Configuration parser not found"**
   - Ensure `/etc/hypr-mon-switch/config-parser.sh` exists and is executable
   - Check file permissions: `ls -la /etc/hypr-mon-switch/`

2. **"Configuration not found"**
   - Verify configuration name matches exactly (case-sensitive)
   - Check YAML syntax with: `yq eval . /etc/hypr-mon-switch/config.yaml`

3. **"Hyprland not found"**
   - Ensure Hyprland is running
   - Check if user has proper permissions

4. **Monitor not detected**
   - Check monitor connections: `hyprctl monitors all`
   - Verify connector names match configuration

### Debug Mode

Enable debug logging by modifying the configuration:

```yaml
global:
  debug: true
```

### Manual Testing

Test individual components:

```bash
# Test configuration parser
/etc/hypr-mon-switch/config-parser.sh find /etc/hypr-mon-switch/config.yaml

# Test specific configuration
/etc/hypr-mon-switch/config-parser.sh apply "config-name" /etc/hypr-mon-switch/config.yaml

# Test hypr-utils
sudo /etc/acpi/hypr-utils.sh apply
```

## Uninstallation

To remove hypr-mon-switch:

```bash
# Remove system files
sudo rm -rf /etc/hypr-mon-switch/
sudo rm -f /etc/acpi/monitor-hotplug.sh
sudo rm -f /etc/acpi/hypr-utils.sh
sudo rm -f /etc/udev/rules.d/99-monitor-hotplug.rules

# Reload udev rules
sudo udevadm control --reload-rules
```

## Development Mode

For development and testing, you can run the system from the source directory:

```bash
# Set environment variable to use development config
export HYPR_MON_CONFIG="/path/to/hypr-mon-switch/configs/example-config.yaml"

# Run hotplug script
./acpi/monitor-hotplug.sh

# Run simple test
./simple-test.sh
```

## Support

For issues and questions:
1. Check the logs: `journalctl -t hypr-mon-switch`
2. Verify configuration syntax
3. Test individual components
4. Check file permissions and paths
