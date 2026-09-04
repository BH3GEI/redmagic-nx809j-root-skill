#!/usr/bin/env python3
"""
edl_flash_root.py
Automated partition flash utility for RedMagic 11 Pro (NX809J).
Safely flashes patched init_boot to slot A and slot B, and restores clean efisp.

Author: BH3GEI
"""

import argparse
import os
import subprocess
import sys


def run_command(cmd, desc):
    """Execute a system command with formatted feedback."""
    print(f"\n[*] {desc}")
    print(f"    Command: {' '.join(cmd)}")
    result = subprocess.run(cmd)
    if result.returncode != 0:
        print(f"[-] Execution failed with return code {result.returncode}")
        sys.exit(result.returncode)
    print(f"[+] {desc} completed successfully.")


def main():
    parser = argparse.ArgumentParser(
        description="Flash Magisk patched init_boot and restore clean efisp on RedMagic 11 Pro via EDL."
    )
    parser.add_argument(
        "--edl-dir",
        required=True,
        help="Path to bkerler-edl directory containing edl.py and virtualenv.",
    )
    parser.add_argument(
        "--loader",
        required=True,
        help="Path to qsahara_device_programmer.xml multi-stage Sahara config.",
    )
    parser.add_argument(
        "--patched-init-boot",
        required=True,
        help="Path to the Magisk-patched init_boot.img.",
    )
    parser.add_argument(
        "--efisp-empty",
        required=True,
        help="Path to efisp_empty.img (3MB all-zero image) to clean the exploit partition.",
    )
    parser.add_argument(
        "--no-reset",
        action="store_true",
        help="Skip automatic reset after flashing.",
    )

    args = parser.parse_args()

    # Validate file existence
    edl_py = os.path.join(args.edl_dir, "edl.py")
    python_bin = os.path.join(args.edl_dir, ".venv", "bin", "python")
    if not os.path.exists(python_bin):
        python_bin = sys.executable

    for path, label in [
        (edl_py, "edl.py script"),
        (args.loader, "Sahara XML loader"),
        (args.patched_init_boot, "Patched init_boot image"),
        (args.efisp_empty, "Empty efisp image"),
    ]:
        if not os.path.exists(path):
            print(f"[-] Error: {label} does not exist at '{path}'")
            sys.exit(1)

    print("==================================================")
    print(" RedMagic 11 Pro EDL Root Flasher")
    print(" Target: NX809J (Snapdragon 8 Elite)")
    print("==================================================")
    print(f"[*] EDL Python:        {python_bin}")
    print(f"[*] Loader XML:        {args.loader}")
    print(f"[*] Patched init_boot: {args.patched_init_boot}")
    print(f"[*] Clean efisp:       {args.efisp_empty}")
    print("==================================================")

    # 1. Flash init_boot_a
    cmd_a = [
        python_bin,
        edl_py,
        f"--loader={args.loader}",
        "w",
        "init_boot_a",
        args.patched_init_boot,
    ]
    run_command(cmd_a, "Flashing patched init_boot to slot A (init_boot_a)")

    # 2. Flash init_boot_b
    cmd_b = [
        python_bin,
        edl_py,
        f"--loader={args.loader}",
        "w",
        "init_boot_b",
        args.patched_init_boot,
    ]
    run_command(cmd_b, "Flashing patched init_boot to slot B (init_boot_b)")

    # 3. Clean efisp
    cmd_efisp = [
        python_bin,
        edl_py,
        f"--loader={args.loader}",
        "w",
        "efisp",
        args.efisp_empty,
    ]
    run_command(cmd_efisp, "Writing clean empty image to efisp partition")

    # 4. Optional Reset
    if not args.no_reset:
        confirm = input("\n[?] Device is ready to reset. Proceed with soft reboot? [Y/n]: ")
        if confirm.strip().lower() in ("", "y", "yes"):
            cmd_reset = [python_bin, edl_py, f"--loader={args.loader}", "reset"]
            print("\n[*] Sending soft reset command to device...")
            # edl.py reset typically triggers USB disconnect (USBError 5), which is expected
            subprocess.run(cmd_reset)
            print("[+] Device reset signal sent. Please wait for Android to boot.")
        else:
            print("[*] Device reset skipped by user.")
    else:
        print("[*] Device reset skipped per --no-reset flag.")


if __name__ == "__main__":
    main()
