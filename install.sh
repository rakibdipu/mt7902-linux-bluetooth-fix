#!/bin/bash
set -euo pipefail

if [ "$EUID" -ne 0 ]; then
    echo "=========================================================="
    echo " Error: Please run this script with sudo:"
    echo "   sudo ./install.sh"
    echo "=========================================================="
    exit 1
fi

KVER="$(uname -r)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DKMS_SRC="${SCRIPT_DIR}/dkms"
FW_SRC="${SCRIPT_DIR}/firmware"
CFG_SRC="${SCRIPT_DIR}/config"
FW_DIR="/lib/firmware/mediatek"

echo "=========================================================="
echo " MediaTek MT7902 Linux Bluetooth Complete Fix"
echo " Kernel: ${KVER}"
echo "=========================================================="

# Check dependencies
if [ ! -d "/lib/modules/${KVER}/build" ]; then
    echo "Error: Kernel headers for ${KVER} not found."
    echo "Install them with: sudo apt install linux-headers-${KVER} build-essential dkms zstd"
    exit 1
fi

if ! command -v dkms >/dev/null 2>&1; then
    echo "Error: dkms is not installed."
    echo "Install it with: sudo apt install dkms build-essential zstd"
    exit 1
fi

echo "==> [1/6] Installing MediaTek MT7902 Bluetooth firmware..."
mkdir -p "${FW_DIR}"
install -m 644 "${FW_SRC}/BT_RAM_CODE_MT7902_1_1_hdr.bin" "${FW_DIR}/"
install -m 644 "${FW_SRC}/BT_RAM_CODE_MT7902_1_1_hdr.bin.zst" "${FW_DIR}/"
echo "    Installed firmware to ${FW_DIR}/"

echo "==> [2/6] Building and installing mt7902-bluetooth via DKMS..."
rm -rf /usr/src/mt7902-bluetooth-git
cp -r "${DKMS_SRC}" /usr/src/mt7902-bluetooth-git
dkms remove mt7902-bluetooth/git --all 2>/dev/null || true
dkms add -m mt7902-bluetooth -v git
dkms build -m mt7902-bluetooth -v git -k "${KVER}"
dkms install -m mt7902-bluetooth -v git -k "${KVER}" --force
depmod -a "${KVER}"
echo "    DKMS installed for kernel ${KVER} (auto-rebuilds on kernel updates)."

echo "==> [3/6] Installing initramfs hook to embed MT7902 firmware in boot ramdisk..."
if [ -d "/etc/initramfs-tools/hooks" ]; then
    install -m 755 "${CFG_SRC}/mt7902-firmware.hook" /etc/initramfs-tools/hooks/mt7902-firmware
    update-initramfs -u -k "${KVER}"
    echo "    Initramfs updated for ${KVER}."
else
    echo "    Skipping initramfs-tools hook (/etc/initramfs-tools/hooks not found)."
fi

echo "==> [4/6] Disabling USB autosuspend for MT7902 Bluetooth..."
install -m 644 "${CFG_SRC}/btusb-nosuspend.conf" /etc/modprobe.d/btusb-nosuspend.conf
install -m 644 "${CFG_SRC}/70-bt-mt7902.rules" /etc/udev/rules.d/70-bt-mt7902.rules
udevadm control --reload-rules 2>/dev/null || true
udevadm trigger --subsystem-match=usb 2>/dev/null || true

# Wake up the USB device immediately if present
for dev in /sys/bus/usb/devices/*; do
    if [ -f "$dev/idVendor" ] && [ "$(cat "$dev/idVendor" 2>/dev/null)" = "13d3" ]; then
        pid="$(cat "$dev/idProduct" 2>/dev/null || true)"
        case "$pid" in
            3579|3580|3594|3596)
                [ -f "$dev/power/control" ] && echo "on" > "$dev/power/control" || true
                [ -f "$dev/power/autosuspend_delay_ms" ] && echo "-1" > "$dev/power/autosuspend_delay_ms" || true
                echo "    Woke up USB device 13d3:${pid} at ${dev}"
                ;;
        esac
    fi
done

echo "==> [5/6] Reloading Bluetooth kernel modules and restarting bluetooth.service..."
systemctl stop bluetooth 2>/dev/null || true
modprobe -r btusb btmtk 2>/dev/null || true
sleep 1
modprobe btmtk
modprobe btusb
# Wait for MT7902 firmware upload (~3-4 seconds)
sleep 4
systemctl start bluetooth
sleep 1
rfkill unblock bluetooth 2>/dev/null || true
bluetoothctl power on 2>/dev/null || true
bluetoothctl pairable on 2>/dev/null || true

echo "==> [6/6] Verification:"
echo "----------------------------------------------------------"
bluetoothctl show || true
echo "----------------------------------------------------------"
echo "Done! MediaTek MT7902 Bluetooth fix installed permanently."
