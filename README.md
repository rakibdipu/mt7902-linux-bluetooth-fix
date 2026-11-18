# MediaTek MT7902 Linux Bluetooth Complete Fix

A complete, kernel-upgrade-proof fix for **MediaTek MT7902 (Filogic 310)** Bluetooth on Linux (tested on Ubuntu 26.04 LTS / Linux Kernel `7.0.x` on ASUS Vivobook, USB ID `13d3:3579`).

## Problems Solved

This repository resolves all four common failure modes encountered with the MediaTek MT7902 Bluetooth controller on Linux:

1. **Adapter fails to turn on (`Opcode 0x0c03 failed: -110` / `No default controller available`)**
   - Stock kernels `< 7.1` do not map MT7902 USB IDs (`13d3:3579`, `13d3:3580`, `13d3:3594`, `13d3:3596`) in `btusb` or `0x7902` in `btmtk`.
   - **Fix:** Patched `btusb` + `btmtk` built and installed via **DKMS** (`mt7902-bluetooth`) so it automatically rebuilds on every kernel upgrade.

2. **Bluetooth breaks after reboot or kernel update (`Direct firmware load for mediatek/BT_RAM_CODE_MT7902_1_1_hdr.bin failed with error -2`)**
   - Backported `btmtk` drivers omitted `MODULE_FIRMWARE(FIRMWARE_MT7902)`, causing `initramfs-tools` to skip bundling the firmware into `/boot/initrd.img-*`. During early boot, the kernel probed `btusb` before rootfs was mounted and failed with `-ENOENT (-2)`.
   - **Fix:** Added `FIRMWARE_MT7902` and `MODULE_FIRMWARE(FIRMWARE_MT7902)` to `btmtk.h` / `btmtk.c` AND installed an initramfs hook (`/etc/initramfs-tools/hooks/mt7902-firmware`) to always embed the firmware in the boot ramdisk.

3. **Bluetooth turns on, but finds 0 devices during scan (dead RF receiver)**
   - Linux USB power management places the MT7902 USB Bluetooth device into `suspended` state (`power/control = auto`), silently turning off the RF radio while software reports the controller as `UP RUNNING`.
   - **Fix:** Permanently disabled USB autosuspend via `/etc/modprobe.d/btusb-nosuspend.conf` (`options btusb enable_autosuspend=0`) and `/etc/udev/rules.d/70-bt-mt7902.rules`.

4. **Incompatible firmware negotiation (`Failed to read MSFT supported features (-56)`)**
   - Bundled verified MediaTek MT7902 Bluetooth firmware (`BT_RAM_CODE_MT7902_1_1_hdr.bin`, Build `20220107141051`) compatible with the `btmtk` backport.

---

## Supported Hardware

- **Combo Card:** MediaTek MT7902 (Filogic 310, PCIe `14c3:7902`)
- **Bluetooth USB IDs:**
  - `13d3:3579` (IMC Networks / ASUS Vivobook)
  - `13d3:3580`
  - `13d3:3594`
  - `13d3:3596`

---

## Prerequisites

Install kernel headers and DKMS build tools (Debian / Ubuntu):

```bash
sudo apt update
sudo apt install -y build-essential dkms zstd linux-headers-$(uname -r)
```

> **Note:** If Secure Boot is enabled, ensure your DKMS MOK key is enrolled or disable Secure Boot in BIOS/UEFI so unsigned/MOK-signed kernel modules can load.

---

## Quick Installation

```bash
git clone https://github.com/rakibdipu/mt7902-linux-bluetooth-fix.git
cd mt7902-linux-bluetooth-fix
chmod +x install.sh uninstall.sh
sudo ./install.sh
```

### What `install.sh` Does

1. Copies verified `BT_RAM_CODE_MT7902_1_1_hdr.bin` & `.bin.zst` to `/lib/firmware/mediatek/`.
2. Registers, compiles, and installs `mt7902-bluetooth` (`btusb` + `btmtk` with `MODULE_FIRMWARE`) via **DKMS**.
3. Installs `/etc/initramfs-tools/hooks/mt7902-firmware` and runs `update-initramfs -u`.
4. Installs `/etc/modprobe.d/btusb-nosuspend.conf` and `/etc/udev/rules.d/70-bt-mt7902.rules` to permanently disable USB autosuspend.
5. Reloads `btmtk` and `btusb`, restarts `bluetooth.service`, powers on the controller, and displays `bluetoothctl show`.

---

## Verification

Check that everything is working properly:

```bash
# 1. Verify controller is UP with a real MAC address (not 00:00:00:00:00:00)
bluetoothctl show

# 2. Verify DKMS status
dkms status

# 3. Verify USB device is active (not suspended)
for d in /sys/bus/usb/devices/*; do
  [ -f "$d/idVendor" ] && [ "$(cat $d/idVendor)" = "13d3" ] && echo "$d: $(cat $d/power/control) / $(cat $d/power/runtime_status)"
done

# 4. Verify firmware is declared in btmtk
modinfo btmtk | grep 7902
```

---

## Uninstall

To cleanly revert all changes and restore stock kernel modules:

```bash
sudo ./uninstall.sh
```

---

## Repository Structure

```text
.
├── install.sh                    # One-click automated installer
├── uninstall.sh                  # Clean uninstaller
├── dkms/                         # Patched btusb + btmtk DKMS driver source
│   ├── Makefile
│   ├── dkms.conf
│   ├── btusb.c                   # Includes MT7902 USB IDs (13d3:3579, etc.)
│   ├── btmtk.c                   # Includes 0x7902 support & MODULE_FIRMWARE(FIRMWARE_MT7902)
│   ├── btmtk.h                   # Defines FIRMWARE_MT7902
│   ├── btintel.h
│   ├── btbcm.h
│   └── btrtl.h
├── firmware/                     # Verified MT7902 Bluetooth firmware
│   ├── BT_RAM_CODE_MT7902_1_1_hdr.bin
│   └── BT_RAM_CODE_MT7902_1_1_hdr.bin.zst
└── config/                       # System configs installed by install.sh
    ├── 70-bt-mt7902.rules        # udev rule disabling USB autosuspend
    ├── btusb-nosuspend.conf      # modprobe option disabling btusb autosuspend
    └── mt7902-firmware.hook      # initramfs-tools hook embedding firmware at boot
```

---

## Credits

Based on upstream Linux `btusb`/`btmtk` drivers and community MT7902 backport patches (`hmtheboy154/mt7902` & `abdullaabdullazade/mt7902_driver`), extended with permanent `MODULE_FIRMWARE`, initramfs boot hook, DKMS persistence, and USB autosuspend fixes.
