# MediaTek MT7902 Linux Bluetooth Fix

[![CI Build & Lint](https://github.com/rakibdipu/mt7902-linux-bluetooth-fix/actions/workflows/ci.yml/badge.svg)](https://github.com/rakibdipu/mt7902-linux-bluetooth-fix/actions/workflows/ci.yml)
[![License: GPL v2](https://img.shields.io/badge/License-GPLv2-blue.svg)](https://www.gnu.org/licenses/old-licenses/gpl-2.0.en.html)
[![Linux Kernel](https://img.shields.io/badge/Kernel-6.6--7.0+-orange.svg)](https://kernel.org)
[![Tested On](https://img.shields.io/badge/Tested%20On-Ubuntu%2026.04%20LTS-E95420.svg?logo=ubuntu&logoColor=white)](https://ubuntu.com)
[![Hardware](https://img.shields.io/badge/Hardware-MediaTek%20MT7902%20(Filogic%20310)-blue.svg)](https://www.mediatek.com)

A complete, kernel-upgrade-proof driver and system patch for **MediaTek MT7902 (Filogic 310)** Bluetooth combo cards on Linux. Tested on ASUS Vivobook with Ubuntu 26.04 LTS (Kernels `6.x` through `7.0.x`).

---

## The Problem & Root Cause

The MediaTek MT7902 is a single-die Wi-Fi 6 + Bluetooth 5.2 combo card (PCIe `14c3:7902` for Wi-Fi, USB `13d3:3579/3580/3594/3596` for Bluetooth). On modern Linux distributions with stock kernels `< 7.1`, users suffer from four critical failure modes:

```
[ Cold Boot / Reboot ]
        │
        ▼
   (Step 1) Kernel boots with initramfs (early boot)
        │
        ├──► Missing MODULE_FIRMWARE in btmtk:
        │    Initramfs omits BT_RAM_CODE_MT7902_1_1_hdr.bin
        │    Error: "Direct firmware load failed with error -2"
        │    RESULT: Controller crashes on boot, BD Address stays 00:00:00:00:00:00
        │
        ▼
   (Step 2) Driver probe (if firmware manually reloaded)
        │
        ├──► Stock btusb lacks MT7902 USB device table entries
        │    Error: "No default controller available"
        │
        ▼
   (Step 3) Controller powers ON
        │
        └──► Linux USB Power Management (Autosuspend) triggers
             power/control = auto  -->  runtime_status = suspended
             RESULT: Controller shows "Powered: yes", but RF radio is asleep!
             Scan returns 0 devices, earbuds & phones are invisible.
```

### The Fix

This repository provides an automated, permanent fix for all three layers:
1. **Patched DKMS Module (`mt7902-bluetooth`):** Backports MT7902 support into `btusb` and `btmtk` with explicit `MODULE_FIRMWARE(FIRMWARE_MT7902)`, ensuring DKMS automatically rebuilds the driver on every future kernel update.
2. **Boot Ramdisk Protection (`initramfs` / `dracut` hook):** Installs an initramfs hook that embeds the MT7902 Bluetooth firmware directly into `/boot/initrd.img-*`, preventing the `-2` (`ENOENT`) firmware missing crash during cold boot.
3. **USB Autosuspend Prevention (`udev` + `modprobe`):** Sets `enable_autosuspend=0` for `btusb` and locks USB power control to `on`, keeping the 2.4 GHz RF radio active and discovering nearby devices.

---

## Supported Hardware

| Component | Identifier | Details |
| :--- | :--- | :--- |
| **Wi-Fi Card (PCIe)** | `14c3:7902` | MediaTek MT7902 802.11ax Wireless Network Adapter |
| **Bluetooth (USB)** | `13d3:3579` | IMC Networks / ASUS Vivobook |
| **Bluetooth (USB)** | `13d3:3580` | MediaTek MT7902 Bluetooth Adapter |
| **Bluetooth (USB)** | `13d3:3594` | MediaTek MT7902 Bluetooth Adapter |
| **Bluetooth (USB)** | `13d3:3596` | MediaTek MT7902 Bluetooth Adapter |

---

## Prerequisites

Install kernel headers and DKMS build tools:

### Ubuntu / Debian / Linux Mint:
```bash
sudo apt update
sudo apt install -y build-essential dkms zstd linux-headers-$(uname -r)
```

### Fedora / RHEL:
```bash
sudo dnf install -y kernel-devel kernel-headers dkms zstd make gcc
```

### Arch Linux / Manjaro:
```bash
sudo pacman -S --needed base-devel dkms zstd linux-headers
```

> **Secure Boot Notice:** If Secure Boot is enabled in BIOS/UEFI, either enroll the DKMS MOK key (`sudo mokutil --import /var/lib/shim-signed/mok/MOK.der`) or temporarily disable Secure Boot.

---

## Installation

Clone the repository and run the installer:

```bash
git clone https://github.com/rakibdipu/mt7902-linux-bluetooth-fix.git
cd mt7902-linux-bluetooth-fix
chmod +x install.sh uninstall.sh status.sh
sudo ./install.sh
```

### What `install.sh` Does Automatically:
1. Installs verified MT7902 Bluetooth firmware (`BT_RAM_CODE_MT7902_1_1_hdr.bin` & `.zst`) into `/lib/firmware/mediatek/`.
2. Registers and compiles `mt7902-bluetooth` via **DKMS** for your current kernel (auto-rebuilds on future updates).
3. Adds an **initramfs hook** (`/etc/initramfs-tools/hooks/mt7902-firmware` or dracut config) and regenerates your boot ramdisk so firmware is always present at early boot.
4. Permanently disables USB autosuspend via `/etc/modprobe.d/btusb-nosuspend.conf` and `/etc/udev/rules.d/70-bt-mt7902.rules`.
5. Reloads `btmtk` and `btusb`, restarts `bluetooth.service`, and brings up the controller.

---

## Diagnostics & Status Verification

Run the included diagnostic utility to verify all 7 subsystems:

```bash
./status.sh
```

**Expected output:**
```text
==========================================================
 MediaTek MT7902 Bluetooth Diagnostic & Status Tool
==========================================================
Kernel: 7.0.0-43-generic (x86_64)

[1/7] Hardware Detection:
  ✓ Found MT7902 Wireless Card on PCIe bus: 14c3:7902
  ✓ Found MT7902 Bluetooth USB device: 13d3:3579 at 3-2

[2/7] USB Autosuspend Status:
  ✓ Device 3-2 power: control=on, runtime=active (Autosuspend disabled)

[3/7] Firmware Verification (/lib/firmware/mediatek):
  ✓ BT_RAM_CODE_MT7902_1_1_hdr.bin present (495426 bytes)
  ✓ BT_RAM_CODE_MT7902_1_1_hdr.bin.zst present

[4/7] Kernel Modules & DKMS Status:
  ✓ btusb module is currently LOADED
  ✓ btmtk module is currently LOADED
  ✓ DKMS Registration: mt7902-bluetooth/git, 7.0.0-43-generic: installed
  ✓ btmtk module declares MODULE_FIRMWARE(FIRMWARE_MT7902)

[5/7] Boot Ramdisk (Initramfs) Protection:
  ✓ initramfs-tools hook installed: /etc/initramfs-tools/hooks/mt7902-firmware

[6/7] Service & RF-Kill Status:
  ✓ bluetooth.service is ACTIVE (running)
  ✓ rfkill: Bluetooth is UNBLOCKED

[7/7] Bluetooth Controller Details:
  ✓ Default Controller: 10:68:38:0C:DC:DB
  ✓ Controller Powered: yes
==========================================================
```

---

## Troubleshooting & FAQ

<details>
<summary><b>1. Bluetooth is ON, but doesn't find nearby devices?</b></summary>

- Verify USB power status with `./status.sh`. If `power/control` shows `auto`, run:
  ```bash
  sudo ./install.sh
  ```
- Make sure devices (earbuds/phones) are in active pairing mode.
- If your Wi-Fi is heavily utilizing the 2.4 GHz band, test switching your Wi-Fi router to the 5 GHz band to rule out antenna coexistence congestion.
</details>

<details>
<summary><b>2. Dual-Boot with Windows: Bluetooth disappears after booting Windows?</b></summary>

Windows **Fast Startup** puts the wireless card into a low-power hibernation state instead of cleanly powering down, which leaves the firmware in an unreset state when Linux boots.
- In Windows: Open **Control Panel** $\rightarrow$ **Power Options** $\rightarrow$ **Choose what the power buttons do** $\rightarrow$ Click **"Change settings that are currently unavailable"** $\rightarrow$ Uncheck **"Turn on fast startup"**.
</details>

<details>
<summary><b>3. Secure Boot prevents loading out-of-tree module?</b></summary>

If `dmesg` reports `Loading of unsigned module is rejected`:
- Either disable Secure Boot in UEFI BIOS settings, or enroll the Ubuntu/Debian MOK key:
  ```bash
  sudo mokutil --import /var/lib/shim-signed/mok/MOK.der
  sudo reboot
  ```
</details>

<details>
<summary><b>4. How do I test scanning from the command line?</b></summary>

```bash
bluetoothctl
[bluetoothctl]> power on
[bluetoothctl]> scan on
```
</details>

---

## Uninstallation

To completely remove the fix and restore default in-tree kernel drivers:

```bash
sudo ./uninstall.sh
```

---

## Repository Structure

```text
.
├── install.sh                          # Automated, colorized installer & setup script
├── uninstall.sh                        # Clean uninstaller restoring stock state
├── status.sh                           # 7-point hardware & driver diagnostic utility
├── LICENSE                             # GNU General Public License v2.0
├── README.md                           # Documentation & troubleshooting guide
├── dkms/                               # DKMS driver source tree
│   ├── Makefile                        # Self-contained kbuild Makefile
│   ├── dkms.conf                       # DKMS configuration
│   ├── btusb.c                         # Patched btusb with MT7902 USB device IDs
│   ├── btmtk.c                         # Patched btmtk with 0x7902 init & MODULE_FIRMWARE
│   ├── btmtk.h                         # Defines FIRMWARE_MT7902
│   ├── btintel.h
│   ├── btbcm.h
│   └── btrtl.h
├── firmware/                           # Verified MediaTek MT7902 firmware
│   ├── BT_RAM_CODE_MT7902_1_1_hdr.bin
│   └── BT_RAM_CODE_MT7902_1_1_hdr.bin.zst
└── config/                             # System configurations
    ├── 70-bt-mt7902.rules              # udev rule disabling USB autosuspend
    ├── btusb-nosuspend.conf            # modprobe configuration
    ├── mt7902-firmware.hook            # initramfs-tools boot ramdisk hook
    └── mt7902-firmware.dracut.conf     # dracut boot ramdisk configuration
```

---

## License

This project is licensed under the [GNU General Public License v2.0](LICENSE) (GPL-2.0), in accordance with the Linux kernel source licensing.
