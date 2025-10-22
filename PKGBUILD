# Maintainer: Augustas Vaivada <https://github.com/aujezus>
pkgname=hypr-mon-switch-git
pkgver=r1.0.0
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
    
    # Install ACPI scripts
    install -Dm755 acpi/hypr-utils.sh "$pkgdir/usr/share/hypr-mon-switch/acpi/hypr-utils.sh"
    install -Dm755 acpi/lid-open.sh "$pkgdir/usr/share/hypr-mon-switch/acpi/lid-open.sh"
    install -Dm755 acpi/lid-close.sh "$pkgdir/usr/share/hypr-mon-switch/acpi/lid-close.sh"
    install -Dm755 acpi/monitor-hotplug.sh "$pkgdir/usr/share/hypr-mon-switch/acpi/monitor-hotplug.sh"
    install -Dm755 acpi/check-lid-on-startup.sh "$pkgdir/usr/share/hypr-mon-switch/acpi/check-lid-on-startup.sh"
    
    # Install utility scripts
    install -Dm755 scripts/config-parser.sh "$pkgdir/usr/share/hypr-mon-switch/scripts/config-parser.sh"
    install -Dm755 scripts/install.sh "$pkgdir/usr/share/hypr-mon-switch/scripts/install.sh"
    install -Dm755 scripts/generate-config.sh "$pkgdir/usr/share/hypr-mon-switch/scripts/generate-config.sh"
    
    # Install configuration files
    install -Dm644 configs/default-config.yaml "$pkgdir/usr/share/hypr-mon-switch/configs/default-config.yaml"
    install -Dm644 configs/example-config.yaml "$pkgdir/usr/share/hypr-mon-switch/configs/example-config.yaml"
    
    # Install documentation
    install -Dm644 README.md "$pkgdir/usr/share/doc/hypr-mon-switch/README.md"
    install -Dm644 LICENSE "$pkgdir/usr/share/licenses/hypr-mon-switch-git/LICENSE"
    
    # Install systemd service file
    install -Dm644 hypr-mon-switch.service "$pkgdir/usr/lib/systemd/system/hypr-mon-switch.service"
    
    # Install udev rules
    install -Dm644 udev/99-monitor-hotplug.rules "$pkgdir/usr/lib/udev/rules.d/99-monitor-hotplug.rules"
}
