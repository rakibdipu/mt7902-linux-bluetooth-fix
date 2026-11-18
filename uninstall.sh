#!/bin/bash
set -euo pipefail

if [ "$EUID" -ne 0 ]; then
    echo "Please run with sudo: sudo ./uninstall.sh"
    exit 1
fi

KVER="$(uname -r)"

echo "==> Removing mt7902-bluetooth DKMS module..."
dkms remove mt7902-bluetooth/git --all 2>/dev/null || true
rm -rf /usr/src/mt7902-bluetooth-git

echo "==> Removing initramfs hook, modprobe config, and udev rule..."
rm -f /etc/initramfs-tools/hooks/mt7902-firmware
rm -f /etc/modprobe.d/btusb-nosuspend.conf
rm -f /etc/udev/rules.d/70-bt-mt7902.rules

udevadm control --reload-rules 2>/dev/null || true
depmod -a "${KVER}"

if command -v update-initramfs >/dev/null 2>&1; then
    echo "==> Updating initramfs..."
    update-initramfs -u -k "${KVER}"
fi

echo "==> Reloading stock Bluetooth modules..."
systemctl stop bluetooth 2>/dev/null || true
modprobe -r btusb btmtk 2>/dev/null || true
modprobe btmtk 2>/dev/null || true
modprobe btusb 2>/dev/null || true
systemctl start bluetooth 2>/dev/null || true

echo "Uninstall complete."
