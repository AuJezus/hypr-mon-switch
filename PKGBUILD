# Maintainer: Augustas Vaivada <https://github.com/aujezus>
pkgname=hypr-mon-switch-git
pkgver=r3.e0498d8
pkgrel=1
pkgdesc="Configuration-based monitor switching system for Hyprland"
arch=('any')
url="https://github.com/aujezus/hypr-mon-switch"
license=('MIT')
depends=('hyprland' 'yq' 'acpid' 'systemd')
makedepends=('git')
source=("$pkgname::git+$url.git")
sha256sums=('SKIP')

pkgver() {
    cd "$pkgname"
    printf "r%s.%s" "$(git rev-list --count HEAD)" "$(git rev-parse --short HEAD)"
}

package() {
    cd "$pkgname"
    
    # Install ACPI scripts to system location
    install -Dm755 acpi/hypr-utils.sh "$pkgdir/etc/acpi/hypr-utils.sh"
    install -Dm755 acpi/lid-open.sh "$pkgdir/etc/acpi/lid-open.sh"
    install -Dm755 acpi/lid-close.sh "$pkgdir/etc/acpi/lid-close.sh"
    install -Dm755 acpi/monitor-hotplug.sh "$pkgdir/etc/acpi/monitor-hotplug.sh"
    install -Dm755 acpi/check-lid-on-startup.sh "$pkgdir/etc/acpi/check-lid-on-startup.sh"
    
    # Install config parser to system location
    install -Dm755 scripts/config-parser.sh "$pkgdir/etc/acpi/config-parser.sh"
    
    # Install utility scripts to /usr/share for user access
    install -Dm755 scripts/install.sh "$pkgdir/usr/share/hypr-mon-switch/scripts/install.sh"
    install -Dm755 scripts/generate-config.sh "$pkgdir/usr/share/hypr-mon-switch/scripts/generate-config.sh"
    install -Dm755 scripts/test-config.sh "$pkgdir/usr/share/hypr-mon-switch/scripts/test-config.sh"
    
    # Install configuration files to system location
    install -Dm644 configs/default-config.yaml "$pkgdir/etc/hypr-mon-switch/config.yaml"
    install -Dm644 configs/example-config.yaml "$pkgdir/etc/hypr-mon-switch/example-config.yaml"
    
    # Install documentation
    install -Dm644 README.md "$pkgdir/usr/share/doc/hypr-mon-switch/README.md"
    install -Dm644 LICENSE "$pkgdir/usr/share/licenses/hypr-mon-switch-git/LICENSE"
    
    # Install systemd service file
    install -Dm644 hypr-mon-switch.service "$pkgdir/usr/lib/systemd/system/hypr-mon-switch.service"
    
    # Install udev rules
    install -Dm644 udev/99-monitor-hotplug.rules "$pkgdir/usr/lib/udev/rules.d/99-monitor-hotplug.rules"
    
    # Install ACPI event files
    install -Dm644 /dev/stdin "$pkgdir/etc/acpi/events/lid-close" << 'EOF'
event=button/lid.*close
action=/etc/acpi/lid-close.sh
EOF
    install -Dm644 /dev/stdin "$pkgdir/etc/acpi/events/lid-open" << 'EOF'
event=button/lid.*open
action=/etc/acpi/lid-open.sh
EOF
}

post_install() {
    echo "Enabling services..."
    systemctl daemon-reload
    systemctl enable acpid
    udevadm control --reload
    udevadm trigger -s drm
    
    echo ""
    echo "hypr-mon-switch-git has been installed!"
    echo "Configuration: /etc/hypr-mon-switch/config.yaml"
    echo "Test: sudo /etc/acpi/hypr-utils.sh apply"
    echo "Generate config: /usr/share/hypr-mon-switch/scripts/generate-config.sh"
}
