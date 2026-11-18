#!/bin/bash
set -euo pipefail

BOLD='\033[1m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}${BOLD}==========================================================${NC}"
    echo -e "${RED}${BOLD} Error: This uninstaller must be run as root (with sudo).${NC}"
    echo -e " Please run: ${BOLD}sudo ./uninstall.sh${NC}"
    echo -e "${RED}${BOLD}==========================================================${NC}"
    exit 1
fi

KVER="$(uname -r)"

echo -e "${BOLD}${CYAN}==========================================================${NC}"
echo -e "${BOLD}${CYAN} MediaTek MT7902 Linux Bluetooth Uninstaller${NC}"
echo -e "${BOLD}${CYAN}==========================================================${NC}"

echo -e "${BOLD}${BLUE}==> [1/4] Removing mt7902-bluetooth DKMS module...${NC}"
if command -v dkms >/dev/null 2>&1; then
    dkms remove mt7902-bluetooth/git --all 2>/dev/null || true
    echo -e "  ${GREEN}✓${NC} Removed from DKMS"
fi
rm -rf /usr/src/mt7902-bluetooth-git

echo -e "${BOLD}${BLUE}==> [2/4] Removing system configuration files...${NC}"
rm -f /etc/initramfs-tools/hooks/mt7902-firmware
rm -f /etc/dracut.conf.d/mt7902-firmware.conf
rm -f /etc/modprobe.d/btusb-nosuspend.conf
rm -f /etc/udev/rules.d/70-bt-mt7902.rules
udevadm control --reload-rules 2>/dev/null || true
depmod -a "${KVER}"
echo -e "  ${GREEN}✓${NC} Removed initramfs hooks, modprobe configs, and udev rules"

echo -e "${BOLD}${BLUE}==> [3/4] Updating boot ramdisk (initramfs)...${NC}"
if command -v update-initramfs >/dev/null 2>&1 && [ -d "/etc/initramfs-tools" ]; then
    update-initramfs -u -k "${KVER}"
    echo -e "  ${GREEN}✓${NC} Updated initramfs via update-initramfs"
elif command -v dracut >/dev/null 2>&1; then
    dracut -f --kver "${KVER}" 2>/dev/null || true
    echo -e "  ${GREEN}✓${NC} Regenerated initramfs via dracut"
fi

echo -e "${BOLD}${BLUE}==> [4/4] Reloading in-tree stock Bluetooth modules...${NC}"
systemctl stop bluetooth 2>/dev/null || true
modprobe -r btusb btmtk 2>/dev/null || true
sleep 1
modprobe btmtk 2>/dev/null || true
modprobe btusb 2>/dev/null || true
systemctl start bluetooth 2>/dev/null || true
echo -e "  ${GREEN}✓${NC} Reloaded stock kernel modules"

echo ""
echo -e "${BOLD}${GREEN}==========================================================${NC}"
echo -e "${BOLD}${GREEN} Uninstallation complete. Stock modules restored.${NC}"
echo -e "${BOLD}${GREEN}==========================================================${NC}"
