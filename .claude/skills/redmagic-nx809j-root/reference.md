# RedMagic 11 Pro (NX809J) Technical Architecture and Reference

## 1. Storage Layout (UFS 4.0 Physical LUN Architecture)

The RedMagic 11 Pro storage is organized across six physical LUNs (Logical Unit Numbers) with a uniform 4096-byte (4KB) sector size:

| LUN | Type | Description | Key Partitions |
|---|---|---|---|
| LUN 0 | User Data & System | Largest storage unit containing Android OS and user space | `super` (~18.4GB), `userdata`, `misc`, `persist`, `vbmeta_system_a/b` |
| LUN 1 | XBL Boot | Primary bootloader / eXtensible Boot Loader (Slot A) | `xbl_a`, `xbl_config_a` |
| LUN 2 | XBL Boot | Primary bootloader / eXtensible Boot Loader (Slot B) | `xbl_b`, `xbl_config_b` |
| LUN 3 | RPMB / Subsystem | Replay Protected Memory Block & security components | Security metadata |
| LUN 4 | Core Boot & Firmware | Crucial kernel, bootloader, modem, and EFI partitions | `init_boot_a/b`, `boot_a/b`, `vendor_boot_a/b`, `abl_a/b`, `efisp` |
| LUN 5 | Radio & Baseband | Cellular baseband and calibration data | `modem_a/b`, `qcom_fw` |

### Critical Partition Offsets on LUN 4
- `init_boot_a`: Sector 360742 (Length: 2048 sectors = 8MB)
- `init_boot_b`: Sector 731346 (Length: 2048 sectors = 8MB)
- `efisp`: Sector 748894 (Length: 768 sectors = 3MB)

### Critical Partition Offsets on LUN 0
- `misc`: Length: 2048 sectors (Holds Android `bootloader_message`)
- `super`: Holds dynamic partitions (`system`, `vendor`, `product`, `system_ext`)

---

## 2. GBL EFI Unlock Exploit Mechanism

Qualcomm ABL on Snapdragon 8 Elite (SM8750) contains a logic flow where the bootloader attempts to execute EFI applications present on the `efisp` partition before enforcing signature verification.

### Disassembly Analysis of `gbl_unlock.efi`
Strings and protocol calls extracted from `gbl_unlock.efi`:
```text
VbRwStateApp: LocateProtocol(VerifiedBoot)
VbRwStateApp: VBRwDeviceState(READ_CONFIG)
VbRwStateApp: VBRwDeviceState(WRITE_CONFIG)
```

1. **Protocol Discovery**: The binary locates the internal Qualcomm `VerifiedBoot` protocol interface.
2. **State Override**: Invokes `VBRwDeviceState(WRITE_CONFIG)` passing `DEVICE_STATE_UNLOCKED` (value `0x00`).
3. **Hardware Effect**: Updates the persistent device lock flag in RPMB / security registers without requiring cryptographic OEM token validation.

### Role of `misc_wipedata.img`
Android Verified Boot (AVB) mandates that changing the device lock state invalidates existing encryption keys. If the device boots without clearing encryption keys, a bootloop or `device corrupt` panic occurs.
Writing `misc_wipedata.img` writes the following standard Android `bootloader_message` structure to the `misc` partition:
```text
boot-recovery\0
recovery
--wipe_data
--reason=CryptKeeper.showFactoryReset()
```
When ABL finishes setting the boot state, Recovery detects this command, formats `/data`, regenerates crypto keys, and allows the device to boot cleanly.

### Importance of `efisp_empty.img`
Once the unlock state is written to hardware:
- Leaving `gbl_unlock.efi` in `efisp` causes the unlock sequence to re-execute on every subsequent boot.
- Overwriting `efisp` with `efisp_empty.img` (a 3MB file consisting purely of `0x00` bytes) cleans the partition and prevents unwanted repeated execution.

---

## 3. Qualcomm Sahara v3 Multi-Stage Loader on SM8750

Snapdragon 8 Elite uses Sahara protocol version 3, requiring a multi-stage firmware upload sequence defined in `qsahara_device_programmer.xml`:

| Stage ID | Target Binary | Purpose |
|---|---|---|
| ID 59 | `sequencer_ram.elf` | Low-level memory sequencer initialization |
| ID 36 | `multi_image_qti.mbn` | Qualcomm signed multi-image metadata |
| ID 37 | `multi_image.mbn` | Secondary signed multi-image bundle |
| ID 61 | `tme_config.elf` | Trusted Management Engine configuration |
| ID 60 | `signed_firmware_soc_view.elf` | SoC peripheral and register mapping |
| ID 21 | `xbl_sc.elf` | Secondary core eXtensible Boot Loader |
| ID 13 | `prog_firehose_ddr.elf` | DDR-resident Firehose programmer |
| ID 38 | `xbl_config_devprg.elf` | Programmer configuration parameters |

### Handling Sahara Handshakes
When connecting via `bkerler-edl`:
```bash
python edl.py --loader=qsahara_device_programmer.xml <command>
```
The client uploads each stage sequentially, responding to device re-handshake requests until transitioning to the Firehose protocol for partition reads/writes.

---

## 4. Troubleshooting and Recovery Patterns

### Symptom: `fastboot: unknown command`
- **Cause**: Stock RedMagic bootloader blocks `flash`, `flashing unlock`, and slot switching commands by OEM policy.
- **Solution**: Do not attempt Fastboot operations. Route all partition writing and state changes through EDL 9008 mode.

### Symptom: `Magisk environment incomplete, abort` in logcat
- **Cause**: After flashing patched `init_boot`, the stub app was present, but `/data/adb` had not been initialized by Magisk daemon.
- **Solution**: Install the full `Magisk-v30.7.apk` over the stub (`adb install -r Magisk-v30.7.apk`), open the app, and click **OK** on the "Requires additional setup" prompt. Magisk will set up `/data/adb` and reboot the device.

### Symptom: `Error: Couldn't detect partition: X` in EDL
- **Cause**: GPT partition table corruption, or targeting the wrong physical LUN.
- **Solution**: Ensure LUN 0 and LUN 4 GPT headers are intact (`gpt_main0.bin` and `gpt_main4.bin`). Check partition visibility with `edl.py printgpt --lun=4`.

### Symptom: `DeviceClass - USBError(5, 'Input/Output Error')` during EDL reset
- **Cause**: Normal USB bus reset event as the device terminates the EDL session and resets the USB phy to boot.
- **Behavior**: Safe to ignore if the command was `reset`. Wait 10-15 seconds for ADB to reappear.
