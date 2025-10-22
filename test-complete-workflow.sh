#!/bin/bash
set -euo pipefail

echo "=== Complete AUR Package Workflow Test ==="
echo "This script will:"
echo "1. Clean previous builds and installations"
echo "2. Build the AUR package"
echo "3. Install the package"
echo "4. Run the install script"
echo "5. Test monitor switching"
echo ""

# Create build directory
BUILD_DIR="$HOME/builds/hypr-mon-switch-test"
echo "Building in: $BUILD_DIR"

# Function to run commands with error handling
run_step() {
    local step_name="$1"
    local command="$2"
    
    echo ""
    echo "=== $step_name ==="
    if eval "$command"; then
        echo "✅ $step_name completed successfully"
    else
        echo "❌ $step_name failed"
        exit 1
    fi
}

# Step 1: Clean previous builds and installations
run_step "Cleaning previous builds" "
    echo 'Removing previous build directory...'
    rm -rf '$BUILD_DIR'
    echo 'Removing previous package installations...'
    pacman -R hypr-mon-switch-git --noconfirm 2>/dev/null || true
    echo 'Cleaning up system integration files...'
    sudo rm -f /etc/udev/rules.d/99-monitor-hotplug.rules
    sudo rm -f /etc/acpi/events/lid-open
    sudo rm -f /etc/acpi/events/lid-close
    sudo rm -f /var/log/hypr-mon-switch.log
    sudo rm -f /etc/acpi/monitor-hotplug-config.sh
    echo 'Cleanup completed'
"

# Step 2: Build the package
run_step "Building AUR package" "
    echo 'Creating build directory...'
    mkdir -p '$BUILD_DIR'
    cd '$BUILD_DIR'
    
    echo 'Copying project files (excluding .git)...'
    for item in /home/aujezus/Dev/Personal/hypr-mon-switch/*; do
        if [[ ! \$(basename \"\$item\") =~ ^(\.git|pkg|src|.*\.pkg\.tar\.zst)$ ]]; then
            cp -r \"\$item\" .
        fi
    done
    
    echo 'Building package with makepkg...'
    makepkg -s --noconfirm
    echo 'Package built successfully'
"

# Step 3: Install the package
run_step "Installing package" "
    cd '$BUILD_DIR'
    echo 'Installing package with pacman...'
    sudo pacman -U hypr-mon-switch-git-*.pkg.tar.zst --noconfirm
    echo 'Package installed successfully'
"

# Step 4: Run the install script
run_step "Running install script" "
    echo 'Running system integration setup...'
    sudo /usr/share/hypr-mon-switch/scripts/install.sh
    echo 'System integration setup completed'
"

# Step 5: Verify installation
run_step "Verifying installation" "
    echo 'Checking installed files...'
    ls -la /etc/acpi/events/
    ls -la /etc/udev/rules.d/99-monitor-hotplug.rules
    ls -la /etc/hypr-mon-switch/
    echo 'Checking system integration...'
    systemctl is-active acpid
    systemctl is-active systemd-udevd
    echo 'Installation verification completed'
"

# Step 6: Test monitor switching
run_step "Testing monitor switching" "
    echo 'Testing monitor hotplug script...'
    HYPRLAND_INSTANCE_SIGNATURE=\"\$(ps -o cmd= -C Hyprland | grep -o 'HYPRLAND_INSTANCE_SIGNATURE=[^ ]*' | cut -d= -f2 || echo '')\"
    XDG_RUNTIME_DIR=\"/run/user/\$(id -u)\"
    echo \"Using signature: \$HYPRLAND_INSTANCE_SIGNATURE\"
    echo \"Using runtime dir: \$XDG_RUNTIME_DIR\"
    
    if [ -n \"\$HYPRLAND_INSTANCE_SIGNATURE\" ]; then
        HYPRLAND_INSTANCE_SIGNATURE=\"\$HYPRLAND_INSTANCE_SIGNATURE\" XDG_RUNTIME_DIR=\"\$XDG_RUNTIME_DIR\" /etc/acpi/monitor-hotplug-config.sh
    else
        XDG_RUNTIME_DIR=\"\$XDG_RUNTIME_DIR\" /etc/acpi/monitor-hotplug-config.sh
    fi
    echo 'Monitor switching test completed'
"

echo ""
echo "🎉 Complete workflow test completed successfully!"
echo ""
echo "The package is now installed and ready to use."
echo "Monitor switching will work automatically when you connect/disconnect displays."
echo ""
echo "To test manually:"
echo "  /etc/acpi/monitor-hotplug-config.sh"
echo ""
echo "To uninstall:"
echo "  sudo pacman -R hypr-mon-switch-git"
echo "  sudo /usr/share/hypr-mon-switch/scripts/uninstall.sh"