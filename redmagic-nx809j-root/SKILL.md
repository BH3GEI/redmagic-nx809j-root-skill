---
name: redmagic-nx809j-root
description: Unlock bootloader via Qualcomm GBL EFI exploit on efisp and root RedMagic 11 Pro (NX809J, Snapdragon 8 Elite / SM8750) using Magisk patched init_boot via EDL (9008). Use when unlocking or rooting RedMagic 11 Pro, flashing init_boot on locked OEM fastboot, or troubleshooting EDL 9008 flashing on Snapdragon 8 Elite devices.
---

# RedMagic 11 Pro (NX809J) Root and Bootloader Unlock Skill

## Overview

This skill documents the exact end-to-end workflow for unlocking the bootloader and obtaining root privileges on the RedMagic 11 Pro (model NX809J).

### Target Device Profile
- Device: Nubia RedMagic 11 Pro / RedMagic 11 Series (NX809J)
- Chipset: Qualcomm Snapdragon 8 Elite (SM8750 / 8E5, QTI Sun architecture)
- System: RedMagicOS 11 (Android 16, Linux 6.12 GKI kernel)
- Storage: UFS 4.0 partitioned across 6 physical LUNs (LUN 0 through LUN 5)
- Partition Architecture: A/B dual-slot system with GKI (ramdisk located in `init_boot`, not `boot`)

### Key OEM Constraints
1. **Restricted Fastboot Interface**: Stock ABL intentionally disables standard fastboot unlock and partition write commands:
   - `fastboot flashing unlock` returns `FAILED (remote: 'unknown command')`
   - `fastboot oem unlock` returns `FAILED (remote: 'unknown command')`
   - `fastboot flash init_boot <file>` returns `FAILED (remote: 'unknown command')`
   - `fastboot --set-active=<slot>` returns `FAILED (remote: 'unknown command')`
2. **Bootloader Unlock Path**: Bootloader state must be modified at the UEFI layer by injecting `gbl_unlock.efi` into the `efisp` partition via Emergency Download Mode (EDL 9008).
3. **Partition Flashing Path**: Patched `init_boot.img` must be flashed directly to UFS storage via EDL 9008 using `bkerler-edl`.

---

## Required Artifacts and Tools

| Artifact | Source / Description | Target Destination |
|---|---|---|
| `bkerler-edl` | Python Qualcomm Sahara/Firehose client with Sahara v3 support | Host environment |
| `qsahara_device_programmer.xml` | Multi-stage Sahara loader XML config for SM8750 | EDL `--loader` parameter |
| `gbl_unlock.efi` | EDK2 EFI executable invoking `VBRwDeviceState(WRITE_CONFIG)` | `efisp` partition (LUN 4) |
| `misc_wipedata.img` | 8KB Android `bootloader_message` triggering `--wipe_data` | `misc` partition (LUN 0) |
| `efisp_empty.img` | 3MB all-zero binary to restore clean partition state | `efisp` partition (LUN 4) |
| `init_boot.img` | Clean stock `init_boot.img` from factory firmware (8MB) | Magisk patching input |
| `Magisk-v30.7.apk` | Magisk v30.7+ APK containing `boot_patch.sh` and ARM64 binaries | Patching tool & Manager app |

---

## Complete Execution Workflow

### Phase 1: Bootloader Unlock via GBL EFI Exploit

Standard fastboot unlock does not work on this device. The unlock is achieved by executing an EFI application during boot:

1. **Reboot to EDL Mode**:
   ```bash
   adb reboot edl
   ```
   Verify 9008 device presence:
   ```bash
   # macOS
   ioreg -p IOUSB -w0 -l | grep "QUSB_BULK"
   # Linux
   lsusb | grep -i "05c6:9008"
   ```

2. **Flash Unlock Binary and Wipe Trigger via EDL**:
   ```bash
   cd /path/to/bkerler-edl
   # Write gbl_unlock.efi to efisp partition on LUN 4
   python edl.py --loader=/path/to/qsahara_device_programmer.xml w efisp /path/to/gbl_unlock.efi

   # Write misc_wipedata.img to misc partition on LUN 0 to force clean crypto reset
   python edl.py --loader=/path/to/qsahara_device_programmer.xml w misc /path/to/misc_wipedata.img

   # Soft reboot device
   python edl.py --loader=/path/to/qsahara_device_programmer.xml reset
   ```

3. **Verify Unlock State**:
   After the device completes factory data wipe and boots into the setup wizard:
   - Enable Developer Options and USB Debugging.
   - Verify unlock status via ADB:
     ```bash
     adb shell getprop ro.boot.flash.locked
     # Expected output: 0

     adb shell getprop ro.boot.vbmeta.device_state
     # Expected output: unlocked
     ```

---

### Phase 2: Magisk Offline Ramdisk Patching

Because RedMagicOS 11 uses a GKI kernel, the first-stage ramdisk lives in `init_boot` (not `boot`).

1. **Prepare Patching Assets**:
   Unzip Magisk APK on the host or push directly to the device:
   ```bash
   mkdir -p /tmp/magisk_patcher
   unzip -q /path/to/Magisk-v30.7.apk -d /tmp/magisk_patcher
   cp /tmp/magisk_patcher/lib/arm64-v8a/libmagiskboot.so /tmp/magisk_patcher/magiskboot
   chmod +x /tmp/magisk_patcher/magiskboot
   ```

2. **Execute On-Device Patching via ADB**:
   Push the patcher components and stock `init_boot.img` to `/data/local/tmp`:
   ```bash
   adb shell mkdir -p /data/local/tmp/magisk_patcher
   adb push /tmp/magisk_patcher/assets/boot_patch.sh /data/local/tmp/magisk_patcher/
   adb push /tmp/magisk_patcher/assets/util_functions.sh /data/local/tmp/magisk_patcher/
   adb push /tmp/magisk_patcher/assets/stub.apk /data/local/tmp/magisk_patcher/
   adb push /tmp/magisk_patcher/lib/arm64-v8a/* /data/local/tmp/magisk_patcher/
   adb push /path/to/clean/init_boot.img /data/local/tmp/magisk_patcher/

   adb shell "cd /data/local/tmp/magisk_patcher && \
              mv libmagiskboot.so magiskboot && \
              mv libmagisk.so magisk && \
              mv libmagiskinit.so magiskinit && \
              chmod 755 * && \
              sh boot_patch.sh init_boot.img"
   ```

3. **Pull Patched Image**:
   ```bash
   adb pull /data/local/tmp/magisk_patcher/new-boot.img ./magisk_patched_init_boot.img
   ```

---

### Phase 3: Flashing Root Image and Restoring Clean efisp via EDL

Do not attempt `fastboot flash init_boot`; it will fail. Flash via EDL 9008:

1. **Reboot to EDL Mode**:
   ```bash
   adb reboot edl
   ```

2. **Flash Both Slots and Clean efisp**:
   ```bash
   cd /path/to/bkerler-edl

   # Flash patched init_boot to slot A
   python edl.py --loader=/path/to/qsahara_device_programmer.xml w init_boot_a ./magisk_patched_init_boot.img

   # Flash patched init_boot to slot B
   python edl.py --loader=/path/to/qsahara_device_programmer.xml w init_boot_b ./magisk_patched_init_boot.img

   # Clean efisp partition by writing 3MB zero image (prevents re-triggering unlock/wipe)
   python edl.py --loader=/path/to/qsahara_device_programmer.xml w efisp /path/to/efisp_empty.img

   # Reset to boot into system
   python edl.py --loader=/path/to/qsahara_device_programmer.xml reset
   ```

---

### Phase 4: Finalizing Magisk Environment

1. **Install Full Magisk APK**:
   ```bash
   adb install -r /path/to/Magisk-v30.7.apk
   ```

2. **Complete Additional Setup**:
   - Open Magisk app on device:
     ```bash
     adb shell monkey -p com.topjohnwu.magisk -c android.intent.category.LAUNCHER 1
     ```
   - When the dialog "Requires additional setup" appears, confirm OK to let Magisk set up `/data/adb` and reboot.

3. **Verify Root Access**:
   ```bash
   adb shell su -v
   # Output: 30.7:MAGISKSU

   adb shell su -c id
   # Output: uid=0(root) gid=0(root) groups=0(root) context=u:r:magisk:s0
   ```

---

## Safety Guidelines

1. **Explicit Confirmation Before Reboot**:
   Always confirm with the user before issuing soft reboot or power cycle commands.
2. **Dual-Slot Synchronization**:
   Always flash both `init_boot_a` and `init_boot_b` to prevent unbootable fallbacks if slot switching occurs.
3. **Partition Cleanliness**:
   Never leave `gbl_unlock.efi` in `efisp` after bootloader state is verified. Always write `efisp_empty.img` before everyday operation.
4. **EDL Dirty Sessions**:
   If an EDL operation is interrupted or reports `subCert failure` / `USBError`, unplug USB cable, power off phone completely (hold Power + Vol Down + Vol Up for 12 seconds), and re-enter 9008 mode.

---

## Additional Resources

- For deep dive into partition maps, EFI protocol disassembly, and EDL Sahara protocols, see [reference.md](reference.md).
- Helper automation scripts are located in [scripts/](scripts/).
