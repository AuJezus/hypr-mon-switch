# Maintainer: Augustas Vaivada <https://github.com/aujezus>
pkgname=hypr-mon-switch-git
pkgver=r5.28e3fd9
pkgrel=1
pkgdesc="Configuration-based monitor switching system for Hyprland with YAML configuration support"
arch=('any')
url="https://github.com/aujezus/hypr-mon-switch"
license=('MIT')
depends=('hyprland' 'yq' 'bash' 'systemd')
makedepends=('git')
source=("$pkgname::git+$url.git")
sha256sums=('SKIP')

pkgver() {
    cd "$pkgname"
    printf "r%s.%s" "$(git rev-list --count HEAD)" "$(git rev-parse --short HEAD)"
}

package() {
    cd "$pkgname"
    
    # Create system directories
    install -d "$pkgdir/etc/hypr-mon-switch"
    install -d "$pkgdir/usr/share/hypr-mon-switch/scripts"
    install -d "$pkgdir/usr/share/doc/hypr-mon-switch"
    
    # Install ACPI scripts to system location
    install -Dm755 acpi/hypr-utils.sh "$pkgdir/etc/acpi/hypr-utils.sh"
    install -Dm755 acpi/monitor-hotplug.sh "$pkgdir/etc/acpi/monitor-hotplug.sh"
    install -Dm755 acpi/check-lid-on-startup.sh "$pkgdir/etc/acpi/check-lid-on-startup.sh"
    
    # Install config parser to correct system location
    install -Dm755 scripts/config-parser.sh "$pkgdir/etc/hypr-mon-switch/config-parser.sh"
    
    # Install utility scripts to /usr/share for user access
    install -Dm755 scripts/install.sh "$pkgdir/usr/share/hypr-mon-switch/scripts/install.sh"
    install -Dm755 scripts/generate-config.sh "$pkgdir/usr/share/hypr-mon-switch/scripts/generate-config.sh"
    install -Dm755 scripts/test-config.sh "$pkgdir/usr/share/hypr-mon-switch/scripts/test-config.sh"
    
    # Install test script
    install -Dm755 simple-test.sh "$pkgdir/usr/share/hypr-mon-switch/simple-test.sh"
    
    # Install configuration files to system location
    install -Dm644 configs/default-config.yaml "$pkgdir/etc/hypr-mon-switch/config.yaml"
    install -Dm644 configs/example-config.yaml "$pkgdir/etc/hypr-mon-switch/example-config.yaml"
    
    # Install documentation
    install -Dm644 README.md "$pkgdir/usr/share/doc/hypr-mon-switch/README.md"
    install -Dm644 INSTALLATION.md "$pkgdir/usr/share/doc/hypr-mon-switch/INSTALLATION.md"
    install -Dm644 LICENSE "$pkgdir/usr/share/licenses/hypr-mon-switch-git/LICENSE"
    
    # Install systemd service file
    install -Dm644 hypr-mon-switch.service "$pkgdir/usr/lib/systemd/system/hypr-mon-switch.service"
    
    # Install udev rules
    install -Dm644 udev/99-monitor-hotplug.rules "$pkgdir/usr/lib/udev/rules.d/99-monitor-hotplug.rules"
}

post_install() {
    echo "Enabling services..."
    systemctl daemon-reload
    udevadm control --reload
    udevadm trigger -s drm
    
    echo ""
    echo "hypr-mon-switch-git has been installed!"
    echo ""
    echo "Configuration: /etc/hypr-mon-switch/config.yaml"
    echo "Example config: /etc/hypr-mon-switch/example-config.yaml"
    echo "Documentation: /usr/share/doc/hypr-mon-switch/INSTALLATION.md"
    echo ""
    echo "Quick start:"
    echo "  Test: sudo /etc/acpi/hypr-utils.sh apply"
    echo "  Generate config: /usr/share/hypr-mon-switch/scripts/generate-config.sh"
    echo "  Manual test: /usr/share/hypr-mon-switch/simple-test.sh"
    echo ""
    echo "The system will automatically detect monitor changes and apply the best matching configuration."
}
