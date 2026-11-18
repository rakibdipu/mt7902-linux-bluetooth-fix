#!/bin/bash
set -euo pipefail

# ANSI Color Codes
BOLD='\033[1m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Handle optional flags
if [ "${1:-}" = "-s" ] || [ "${1:-}" = "--status" ]; then
    exec "${SCRIPT_DIR}/status.sh"
fi

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    echo -e "${BOLD}${CYAN}MediaTek MT7902 Linux Bluetooth Fix${NC}"
    echo "Usage:"
    echo "  sudo ./install.sh          Install driver, firmware, initramfs hook, & autosuspend fix"
    echo "  ./install.sh --status      Diagnose and check current Bluetooth status"
    echo "  sudo ./uninstall.sh        Revert changes and restore stock modules"
    exit 0
fi

if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}${BOLD}==========================================================${NC}"
    echo -e "${RED}${BOLD} Error: This installer must be run as root (with sudo).${NC}"
    echo -e " Please run: ${BOLD}sudo ./install.sh${NC}"
    echo -e "${RED}${BOLD}==========================================================${NC}"
    exit 1
fi

KVER="$(uname -r)"
DKMS_SRC="${SCRIPT_DIR}/dkms"
FW_SRC="${SCRIPT_DIR}/firmware"
CFG_SRC="${SCRIPT_DIR}/config"
FW_DIR="/lib/firmware/mediatek"

echo -e "${BOLD}${CYAN}==========================================================${NC}"
echo -e "${BOLD}${CYAN} MediaTek MT7902 Linux Bluetooth Automated Fix${NC}"
echo -e "${BOLD}${CYAN}==========================================================${NC}"
echo -e "${BOLD}Target Kernel:${NC} ${KVER} ($(uname -m))"
echo -e "${BOLD}Detected OS:${NC}   $(grep -m1 '^PRETTY_NAME=' /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '\"' || uname -s)"
echo ""

# Hardware check
echo -e "${BOLD}${BLUE}[Pre-flight] Checking hardware...${NC}"
if lspci -nn 2>/dev/null | grep -qi "14c3:7902"; then
    echo -e "  ${GREEN}✓${NC} Detected MediaTek MT7902 Wireless Card (14c3:7902)"
else
    echo -e "  ${YELLOW}!${NC} 14c3:7902 not seen on PCIe bus (continuing anyway)"
fi

# Dependency check & helpful package hints
MISSING_DEPS=()
if [ ! -d "/lib/modules/${KVER}/build" ]; then
    MISSING_DEPS+=("kernel-headers-${KVER}")
fi
if ! command -v dkms >/dev/null 2>&1; then
    MISSING_DEPS+=("dkms")
fi
if ! command -v zstd >/dev/null 2>&1; then
    MISSING_DEPS+=("zstd")
fi
if ! command -v make >/dev/null 2>&1; then
    MISSING_DEPS+=("make/build-essential")
fi

if [ ${#MISSING_DEPS[@]} -gt 0 ]; then
    echo -e "  ${RED}✗ Missing required build tools: ${MISSING_DEPS[*]}${NC}"
    echo ""
    echo "Install them using your package manager:"
    if command -v apt >/dev/null 2>&1; then
        echo -e "  ${BOLD}sudo apt update && sudo apt install -y build-essential dkms zstd linux-headers-${KVER}${NC}"
    elif command -v dnf >/dev/null 2>&1; then
        echo -e "  ${BOLD}sudo dnf install -y kernel-devel kernel-headers dkms zstd make gcc${NC}"
    elif command -v pacman >/dev/null 2>&1; then
        echo -e "  ${BOLD}sudo pacman -S --needed base-devel dkms zstd linux-headers${NC}"
    fi
    exit 1
fi
echo -e "  ${GREEN}✓${NC} All build tools and kernel headers are present."

# Step 1: Firmware
echo ""
echo -e "${BOLD}${BLUE}==> [1/6] Installing MediaTek MT7902 Bluetooth firmware...${NC}"
mkdir -p "${FW_DIR}"
install -m 644 "${FW_SRC}/BT_RAM_CODE_MT7902_1_1_hdr.bin" "${FW_DIR}/"
install -m 644 "${FW_SRC}/BT_RAM_CODE_MT7902_1_1_hdr.bin.zst" "${FW_DIR}/"
echo -e "    ${GREEN}✓${NC} Firmware installed to ${FW_DIR}/"

# Step 2: DKMS
echo ""
echo -e "${BOLD}${BLUE}==> [2/6] Building and registering mt7902-bluetooth via DKMS...${NC}"
rm -rf /usr/src/mt7902-bluetooth-git
cp -r "${DKMS_SRC}" /usr/src/mt7902-bluetooth-git
dkms remove mt7902-bluetooth/git --all 2>/dev/null || true
dkms add -m mt7902-bluetooth -v git
dkms build -m mt7902-bluetooth -v git -k "${KVER}"
dkms install -m mt7902-bluetooth -v git -k "${KVER}" --force
depmod -a "${KVER}"
echo -e "    ${GREEN}✓${NC} DKMS registered and built for ${KVER} (will auto-rebuild on future kernel upgrades)."

# Step 3: Initramfs protection
echo ""
echo -e "${BOLD}${BLUE}==> [3/6] Protecting boot ramdisk (initramfs) from missing firmware error...${NC}"
INITRAMFS_UPDATED=false

# Debian / Ubuntu (initramfs-tools)
if [ -d "/etc/initramfs-tools/hooks" ]; then
    install -m 755 "${CFG_SRC}/mt7902-firmware.hook" /etc/initramfs-tools/hooks/mt7902-firmware
    echo "    Updating initramfs via update-initramfs..."
    update-initramfs -u -k "${KVER}"
    echo -e "    ${GREEN}✓${NC} Embedded MT7902 firmware in initramfs for ${KVER}."
    INITRAMFS_UPDATED=true
fi

# Fedora / RHEL / openSUSE (dracut)
if [ -d "/etc/dracut.conf.d" ]; then
    install -m 644 "${CFG_SRC}/mt7902-firmware.dracut.conf" /etc/dracut.conf.d/mt7902-firmware.conf
    if command -v dracut >/dev/null 2>&1; then
        echo "    Regenerating initramfs via dracut..."
        dracut -f --kver "${KVER}" 2>/dev/null || true
        echo -e "    ${GREEN}✓${NC} Added dracut configuration for MT7902 firmware."
        INITRAMFS_UPDATED=true
    fi
fi

if [ "$INITRAMFS_UPDATED" = false ]; then
    echo -e "    ${YELLOW}!${NC} Neither initramfs-tools nor dracut detected; skipping ramdisk hook."
fi

# Step 4: USB Autosuspend fix
echo ""
echo -e "${BOLD}${BLUE}==> [4/6] Disabling USB autosuspend for MT7902 Bluetooth...${NC}"
install -m 644 "${CFG_SRC}/btusb-nosuspend.conf" /etc/modprobe.d/btusb-nosuspend.conf
install -m 644 "${CFG_SRC}/70-bt-mt7902.rules" /etc/udev/rules.d/70-bt-mt7902.rules
udevadm control --reload-rules 2>/dev/null || true
udevadm trigger --subsystem-match=usb 2>/dev/null || true

# Wake up USB devices immediately
for dev in /sys/bus/usb/devices/*; do
    if [ -f "$dev/idVendor" ] && [ "$(cat "$dev/idVendor" 2>/dev/null)" = "13d3" ]; then
        pid="$(cat "$dev/idProduct" 2>/dev/null || true)"
        case "$pid" in
            3579|3580|3594|3596)
                [ -f "$dev/power/control" ] && echo "on" > "$dev/power/control" || true
                [ -f "$dev/power/autosuspend_delay_ms" ] && echo "-1" > "$dev/power/autosuspend_delay_ms" || true
                echo -e "    ${GREEN}✓${NC} Woke up USB controller 13d3:${pid} at $(basename "$dev")"
                ;;
        esac
    fi
done

# Step 5: Reload driver and restart services
echo ""
echo -e "${BOLD}${BLUE}==> [5/6] Reloading Bluetooth kernel modules and restarting bluetooth.service...${NC}"
systemctl stop bluetooth 2>/dev/null || true
modprobe -r btusb btmtk 2>/dev/null || true
sleep 1
modprobe btmtk
modprobe btusb

echo "    Waiting 4 seconds for MT7902 firmware upload to complete..."
sleep 4

systemctl restart bluetooth
sleep 1
rfkill unblock bluetooth 2>/dev/null || true
bluetoothctl power on 2>/dev/null || true
bluetoothctl pairable on 2>/dev/null || true
bluetoothctl discoverable on 2>/dev/null || true

# Step 6: Final check
echo ""
echo -e "${BOLD}${BLUE}==> [6/6] Verifying Bluetooth Controller:${NC}"
echo "----------------------------------------------------------"
if command -v bluetoothctl >/dev/null 2>&1; then
    bluetoothctl show || true
fi
echo "----------------------------------------------------------"

echo ""
echo -e "${BOLD}${GREEN}==========================================================${NC}"
echo -e "${BOLD}${GREEN} SUCCESS! MediaTek MT7902 Bluetooth Fix Installed!${NC}"
echo -e " Run ${BOLD}./status.sh${NC} anytime to verify system health."
echo -e "${BOLD}${GREEN}==========================================================${NC}"
