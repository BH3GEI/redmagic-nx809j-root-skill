# AGENTS.md

Cross-harness entry point for AI coding agents without a native skill system (Codex CLI, DeepSeek, and other AGENTS.md-compatible harnesses). Claude Code and Cursor load this repository as a native skill via `.claude/skills/` and `.cursor/skills/` respectively; agents reading this file should follow the same canonical skill content below.

## When This Skill Applies

Use this skill when the task involves:
- Unlocking or rooting a RedMagic 11 Pro (model NX809J, Snapdragon 8 Elite / SM8750)
- Flashing `init_boot` on devices with locked-OEM fastboot
- Troubleshooting EDL 9008 flashing on Snapdragon 8 Elite devices

## Required Reading (Before Any Operation)

1. [`redmagic-nx809j-root/SKILL.md`](redmagic-nx809j-root/SKILL.md) — canonical end-to-end workflow: EDL bootloader unlock via GBL EFI exploit → offline Magisk `init_boot` patching → dual-slot EDL flashing → Magisk finalization.
2. [`redmagic-nx809j-root/reference.md`](redmagic-nx809j-root/reference.md) — UFS LUN / partition maps, GBL EFI exploit mechanism, Sahara v3 multi-stage loader, troubleshooting patterns.

## Hard Safety Rules

From `SKILL.md` § Safety Guidelines — apply verbatim, no exceptions:

1. **Explicit Confirmation Before Reboot**: Always confirm with the user before issuing soft reboot or power cycle commands.
2. **Dual-Slot Synchronization**: Always flash both `init_boot_a` and `init_boot_b` to prevent unbootable fallbacks if slot switching occurs.
3. **Partition Cleanliness**: Never leave `gbl_unlock.efi` in `efisp` after bootloader state is verified. Always write `efisp_empty.img` before everyday operation.
4. **EDL Dirty Sessions**: If an EDL operation is interrupted or reports `subCert failure` / `USBError`, unplug USB cable, power off phone completely (hold Power + Vol Down + Vol Up for 12 seconds), and re-enter 9008 mode.

## Helper Scripts

- `redmagic-nx809j-root/scripts/check_env.sh` — USB / ADB / Fastboot / EDL 9008 environment diagnostics
- `redmagic-nx809j-root/scripts/patch_init_boot.sh` — on-device offline Magisk boot patcher
- `redmagic-nx809j-root/scripts/edl_flash_root.py` — automated dual-slot EDL flasher with efisp cleanup

## Canonical Source

The [`redmagic-nx809j-root/`](redmagic-nx809j-root/) directory is the single source of truth. `.claude/skills/redmagic-nx809j-root/` and `.cursor/skills/redmagic-nx809j-root/SKILL.md` are format mirrors for their respective harnesses. Edit the canonical directory first, then re-sync the mirrors (commands in [README.md](README.md)).
