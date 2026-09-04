# RedMagic 11 Pro (NX809J) Root Agent Skill

An automated, reproducible Cursor Agent Skill and engineering playbook for unlocking the bootloader and obtaining systemless Magisk root on the **RedMagic 11 Pro / RedMagic 11 Series (model NX809J, Snapdragon 8 Elite / SM8750)** under macOS / Linux.

## Background and Motivation

The RedMagic 11 Pro is built on Qualcomm's Snapdragon 8 Elite platform (QTI Sun architecture, SM8750) running RedMagicOS 11 (Android 16, Linux 6.12 GKI kernel).

Traditional rooting workflows fail on this device due to vendor constraints:
- The stock ABL (bootloader) intentionally blocks standard Fastboot partition writes (`fastboot flash init_boot` fails with `unknown command`).
- Fastboot unlock commands (`fastboot flashing unlock`, `fastboot oem unlock`) are completely rejected by the bootloader.
- Standard slot-switching operations via Fastboot are disallowed.

This repository provides an end-to-end engineered pathway bypassing these restrictions using Qualcomm Emergency Download Mode (EDL 9008), the Qualcomm GBL (Generic Bootloader Loader) EFI protocol execution vector, and offline Magisk ramdisk patching.

---

## Repository Structure

```text
redmagic-nx809j-root-skill/
├── AGENTS.md                        # Cross-harness entry point (Codex CLI, DeepSeek, AGENTS.md-compatible agents)
├── .claude/
│   └── skills/
│       └── redmagic-nx809j-root/    # Project-scoped Claude Code skill (mirror of canonical)
│           ├── SKILL.md
│           ├── reference.md
│           └── scripts/
├── .cursor/
│   └── skills/
│       └── redmagic-nx809j-root/
│           └── SKILL.md             # Project-scoped Cursor skill definition (mirror)
├── redmagic-nx809j-root/
│   ├── SKILL.md                     # Canonical skill specification
│   ├── reference.md                 # Deep technical architecture & disassembly
│   └── scripts/
│       ├── check_env.sh             # Real-time hardware/OS diagnostic utility
│       ├── patch_init_boot.sh       # On-device offline Magisk boot patcher
│       └── edl_flash_root.py        # Automated dual-slot EDL flasher
├── README.md                        # Project documentation
└── .gitignore                       # Git ignore rules
```

---

## Core Technical Vectors

### 1. Bootloader Unlock via GBL EFI Exploit
- The device bootloader checks the `efisp` partition on UFS LUN 4 during early UEFI phases.
- Flashing `gbl_unlock.efi` to `efisp` directly interacts with the hardware `VerifiedBoot` protocol via `VBRwDeviceState(WRITE_CONFIG)` to mark the device as `UNLOCKED`.
- Concurrently flashing `misc_wipedata.img` to `misc` on LUN 0 triggers an Android Verified Boot clean data wipe, avoiding cryptographic lockouts.
- After unlocking, `efisp` is overwritten with `efisp_empty.img` (3MB all-zero image) to restore partition cleanliness.

### 2. GKI Ramdisk Patching
- Under Android 16 with Generic Kernel Images (GKI), the first-stage ramdisk resides in `init_boot` rather than `boot`.
- The clean factory `init_boot.img` is patched with Magisk v30.7+ using ARM64 native binaries staged via ADB into `/data/local/tmp`.

### 3. Dual-Slot Direct Flashing via EDL 9008
- Using `bkerler-edl` and the multi-stage Sahara v3 configuration (`qsahara_device_programmer.xml`), the patched image is written directly to physical sectors:
  - Slot A: `init_boot_a` (Sector 360742 on LUN 4)
  - Slot B: `init_boot_b` (Sector 731346 on LUN 4)
- This guarantees bootability regardless of slot state and circumvents all Fastboot restrictions.

---

## Installation Across Agent Harnesses

The canonical skill lives in [`redmagic-nx809j-root/`](redmagic-nx809j-root/). The `.claude/skills/` and `.cursor/skills/` directories are format mirrors of it — after editing the canonical files, re-sync them (see [Syncing Mirrors](#syncing-mirrors)).

### Claude Code
- **Project Skill**: If using this repository directly as a workspace in Claude Code, the skill is already pre-configured under `.claude/skills/redmagic-nx809j-root/`.
- **Personal Skill (Recommended)**: To make this skill globally accessible to Claude Code across all workspaces on your machine:
```bash
mkdir -p ~/.claude/skills
cp -R redmagic-nx809j-root ~/.claude/skills/
```
The skill frontmatter sets `disable-model-invocation: true`, so it is invoked explicitly (`/redmagic-nx809j-root`) rather than auto-triggered by the model.

### Codex CLI / DeepSeek / AGENTS.md-Compatible Agents
- **This Repository as Workspace**: No installation needed — these harnesses read [`AGENTS.md`](AGENTS.md) automatically and are routed to the canonical skill files.
- **Global Skill**: Add a pointer to your user-level agents file (e.g. `~/.codex/AGENTS.md`):
```bash
echo "For RedMagic NX809J root/unlock tasks, follow the skill at: /absolute/path/to/redmagic-nx809j-root-skill/AGENTS.md" >> ~/.codex/AGENTS.md
```

### Cursor
- **Personal Skill (Recommended)**: To make this skill globally accessible to Cursor across all workspaces on your machine:
```bash
mkdir -p ~/.cursor/skills/redmagic-nx809j-root
cp redmagic-nx809j-root/SKILL.md ~/.cursor/skills/redmagic-nx809j-root/
```
- **Project Skill**: If using this repository directly as a workspace in Cursor, the configuration is already pre-configured under `.cursor/skills/redmagic-nx809j-root/SKILL.md`.

### Syncing Mirrors

After editing the canonical files in `redmagic-nx809j-root/`, refresh the harness mirrors:
```bash
rsync -a --delete redmagic-nx809j-root/ .claude/skills/redmagic-nx809j-root/
cp redmagic-nx809j-root/SKILL.md .cursor/skills/redmagic-nx809j-root/SKILL.md
```

---

## Helper Scripts Usage

### 1. Environment Diagnostic
Inspects connected devices across USB, ADB, Fastboot, and EDL 9008:
```bash
./redmagic-nx809j-root/scripts/check_env.sh
```

### 2. Offline Boot Patching
Extracts Magisk components and generates `magisk_patched_init_boot.img` via an ADB-connected device:
```bash
./redmagic-nx809j-root/scripts/patch_init_boot.sh /path/to/Magisk-v30.7.apk /path/to/stock/init_boot.img ./magisk_patched_init_boot.img
```

### 3. EDL Root Flashing
Flashes both slots and cleans the EFI partition in a single guided process:
```bash
python3 ./redmagic-nx809j-root/scripts/edl_flash_root.py \
    --edl-dir=/path/to/bkerler-edl \
    --loader=/path/to/qsahara_device_programmer.xml \
    --patched-init-boot=./magisk_patched_init_boot.img \
    --efisp-empty=/path/to/efisp_empty.img
```

---

## Safety and Quality Rules

- Never reboot a connected device without explicit confirmation.
- Maintain dual-slot parity: always update both `init_boot_a` and `init_boot_b`.
- Always wipe `efisp` after bootloader state transition to avoid recurrent boot triggers.
- Code is for humans to read; it only happens that machines can run it.
