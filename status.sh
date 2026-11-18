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

echo -e "${BOLD}${CYAN}==========================================================${NC}"
echo -e "${BOLD}${CYAN} MediaTek MT7902 Bluetooth Diagnostic & Status Tool${NC}"
echo -e "${BOLD}${CYAN}==========================================================${NC}"
echo -e "${BOLD}Kernel:${NC} $(uname -r) ($(uname -m))"
echo -e "${BOLD}Date:${NC}   $(date)"
echo ""

# 1. Hardware Presence
echo -e "${BOLD}${BLUE}[1/7] Hardware Detection:${NC}"
PCI_FOUND=false
if lspci -nn 2>/dev/null | grep -qi "14c3:7902"; then
    echo -e "  ${GREEN}✓${NC} Found MT7902 Wireless Card on PCIe bus:"
    lspci -nn | grep -i "14c3:7902" | sed 's/^/    /'
    PCI_FOUND=true
elif [ -f /sys/bus/pci/devices/*/device ]; then
    for dev in /sys/bus/pci/devices/*; do
        if [ -f "$dev/vendor" ] && [ "$(cat "$dev/vendor" 2>/dev/null)" = "0x14c3" ] && [ "$(cat "$dev/device" 2>/dev/null)" = "0x7902" ]; then
            echo -e "  ${GREEN}✓${NC} Found MT7902 Wireless Card on PCIe bus at $(basename "$dev")"
            PCI_FOUND=true
            break
        fi
    done
fi

if [ "$PCI_FOUND" = false ]; then
    echo -e "  ${YELLOW}!${NC} No 14c3:7902 detected on PCIe bus."
fi

USB_FOUND=false
for d in /sys/bus/usb/devices/*; do
    if [ -f "$d/idVendor" ] && [ "$(cat "$d/idVendor" 2>/dev/null)" = "13d3" ]; then
        pid="$(cat "$d/idProduct" 2>/dev/null || true)"
        case "$pid" in
            3579|3580|3594|3596)
                echo -e "  ${GREEN}✓${NC} Found MT7902 Bluetooth USB device: ${BOLD}13d3:${pid}${NC} at $(basename "$d")"
                USB_FOUND=true
                ;;
        esac
    fi
done
if [ "$USB_FOUND" = false ]; then
    echo -e "  ${RED}✗${NC} No MT7902 USB Bluetooth controller found (13d3:3579/3580/3594/3596)."
fi

# 2. USB Power & Autosuspend State
echo ""
echo -e "${BOLD}${BLUE}[2/7] USB Autosuspend Status:${NC}"
SUSPEND_OK=true
for d in /sys/bus/usb/devices/*; do
    if [ -f "$d/idVendor" ] && [ "$(cat "$d/idVendor" 2>/dev/null)" = "13d3" ]; then
        pid="$(cat "$d/idProduct" 2>/dev/null || true)"
        case "$pid" in
            3579|3580|3594|3596)
                p_ctrl="$(cat "$d/power/control" 2>/dev/null || echo 'unknown')"
                p_stat="$(cat "$d/power/runtime_status" 2>/dev/null || echo 'unknown')"
                if [ "$p_ctrl" = "on" ] && [ "$p_stat" = "active" ]; then
                    echo -e "  ${GREEN}✓${NC} Device $(basename "$d") power: ${GREEN}control=${p_ctrl}${NC}, ${GREEN}runtime=${p_stat}${NC} (Autosuspend disabled)"
                else
                    echo -e "  ${RED}✗${NC} Device $(basename "$d") power: ${RED}control=${p_ctrl}${NC}, ${RED}runtime=${p_stat}${NC} (Device may be suspended!)"
                    SUSPEND_OK=false
                fi
                ;;
        esac
    fi
done

# 3. Firmware Files
echo ""
echo -e "${BOLD}${BLUE}[3/7] Firmware Verification (/lib/firmware/mediatek):${NC}"
if [ -f "/lib/firmware/mediatek/BT_RAM_CODE_MT7902_1_1_hdr.bin" ]; then
    sz="$(stat -c %s /lib/firmware/mediatek/BT_RAM_CODE_MT7902_1_1_hdr.bin 2>/dev/null || echo '?')"
    echo -e "  ${GREEN}✓${NC} BT_RAM_CODE_MT7902_1_1_hdr.bin present (${sz} bytes)"
else
    echo -e "  ${RED}✗${NC} BT_RAM_CODE_MT7902_1_1_hdr.bin is MISSING from /lib/firmware/mediatek!"
fi

if [ -f "/lib/firmware/mediatek/BT_RAM_CODE_MT7902_1_1_hdr.bin.zst" ]; then
    echo -e "  ${GREEN}✓${NC} BT_RAM_CODE_MT7902_1_1_hdr.bin.zst present"
fi

# 4. Kernel Module & DKMS Status
echo ""
echo -e "${BOLD}${BLUE}[4/7] Kernel Modules & DKMS Status:${NC}"
if grep -q "^btusb " /proc/modules 2>/dev/null; then
    echo -e "  ${GREEN}✓${NC} btusb module is currently LOADED"
else
    echo -e "  ${RED}✗${NC} btusb module is NOT loaded"
fi

if grep -q "^btmtk " /proc/modules 2>/dev/null; then
    echo -e "  ${GREEN}✓${NC} btmtk module is currently LOADED"
else
    echo -e "  ${RED}✗${NC} btmtk module is NOT loaded"
fi

if command -v dkms >/dev/null 2>&1; then
    dkms_out="$(dkms status 2>/dev/null | grep mt7902-bluetooth || true)"
    if [ -n "$dkms_out" ]; then
        echo -e "  ${GREEN}✓${NC} DKMS Registration:"
        echo "$dkms_out" | sed 's/^/    /'
    else
        echo -e "  ${YELLOW}!${NC} mt7902-bluetooth is NOT registered in DKMS"
    fi
fi

if modinfo btmtk 2>/dev/null | grep -q "BT_RAM_CODE_MT7902"; then
    echo -e "  ${GREEN}✓${NC} btmtk module declares MODULE_FIRMWARE(FIRMWARE_MT7902)"
else
    echo -e "  ${YELLOW}!${NC} btmtk module does not declare MT7902 firmware (standard in-tree module?)"
fi

# 5. Boot Ramdisk (initramfs) Configuration
echo ""
echo -e "${BOLD}${BLUE}[5/7] Boot Ramdisk (Initramfs) Protection:${NC}"
INITRAMFS_PROTECTED=false
if [ -f "/etc/initramfs-tools/hooks/mt7902-firmware" ]; then
    echo -e "  ${GREEN}✓${NC} initramfs-tools hook installed: /etc/initramfs-tools/hooks/mt7902-firmware"
    INITRAMFS_PROTECTED=true
fi
if [ -f "/etc/dracut.conf.d/mt7902-firmware.conf" ]; then
    echo -e "  ${GREEN}✓${NC} dracut config installed: /etc/dracut.conf.d/mt7902-firmware.conf"
    INITRAMFS_PROTECTED=true
fi
if [ "$INITRAMFS_PROTECTED" = false ]; then
    echo -e "  ${YELLOW}!${NC} No initramfs firmware hook found (firmware may fail to load on cold boot)"
fi

# 6. Service & rfkill Status
echo ""
echo -e "${BOLD}${BLUE}[6/7] Service & RF-Kill Status:${NC}"
if systemctl is-active --quiet bluetooth 2>/dev/null; then
    echo -e "  ${GREEN}✓${NC} bluetooth.service is ACTIVE (running)"
else
    echo -e "  ${RED}✗${NC} bluetooth.service is NOT active"
fi

rf_blocked=false
while read -r line; do
    if echo "$line" | grep -qi "soft blocked: yes"; then
        rf_blocked=true
    fi
done < <(rfkill list bluetooth 2>/dev/null || true)

if [ "$rf_blocked" = true ]; then
    echo -e "  ${RED}✗${NC} Bluetooth is SOFT-BLOCKED by rfkill! (Run: rfkill unblock bluetooth)"
else
    echo -e "  ${GREEN}✓${NC} rfkill: Bluetooth is UNBLOCKED"
fi

# 7. Bluetooth Controller Status
echo ""
echo -e "${BOLD}${BLUE}[7/7] Bluetooth Controller Details:${NC}"
if command -v bluetoothctl >/dev/null 2>&1; then
    ctrl_info="$(bluetoothctl show 2>/dev/null || true)"
    if echo "$ctrl_info" | grep -q "Controller"; then
        ctrl_mac="$(echo "$ctrl_info" | grep -m1 "Controller" | awk '{print $2}')"
        ctrl_pwr="$(echo "$ctrl_info" | grep -m1 "Powered:" | awk '{print $2}')"
        echo -e "  ${GREEN}✓${NC} Default Controller: ${BOLD}${ctrl_mac}${NC}"
        echo -e "  ${GREEN}✓${NC} Controller Powered: ${BOLD}${ctrl_pwr}${NC}"
    else
        echo -e "  ${RED}✗${NC} No default controller available!"
    fi
fi

echo ""
echo -e "${BOLD}${CYAN}==========================================================${NC}"
echo -e "Summary: If all items above show ${GREEN}✓${NC}, your MT7902 Bluetooth is in"
echo -e "perfect working condition. If any show ${RED}✗${NC}, run ${BOLD}sudo ./install.sh${NC}."
echo -e "${BOLD}${CYAN}==========================================================${NC}"
