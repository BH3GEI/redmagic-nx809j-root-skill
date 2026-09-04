#!/usr/bin/env bash
#
# patch_init_boot.sh
# Patches stock init_boot.img using Magisk ARM64 binaries on an attached Android device.
#
# Usage:
#   ./patch_init_boot.sh <path_to_magisk.apk> <path_to_stock_init_boot.img> [output_path]
#

set -euo pipefail

if [[ $# -lt 2 ]]; then
    echo "Usage: $0 <path_to_magisk.apk> <path_to_stock_init_boot.img> [output_path]"
    exit 1
fi

MAGISK_APK="$1"
STOCK_INIT_BOOT="$2"
OUTPUT_IMAGE="${3:-./magisk_patched_init_boot.img}"

# 1. Sanity Checks
if [[ ! -f "${MAGISK_APK}" ]]; then
    echo "[-] Error: Magisk APK not found at '${MAGISK_APK}'"
    exit 1
fi

if [[ ! -f "${STOCK_INIT_BOOT}" ]]; then
    echo "[-] Error: Stock init_boot image not found at '${STOCK_INIT_BOOT}'"
    exit 1
fi

echo "[*] Checking ADB connection..."
if ! adb get-state 2>/dev/null | grep -q "device"; then
    echo "[-] Error: No ADB device online. Please connect device with USB debugging enabled."
    exit 1
fi

# 2. Extract APK on Host
WORKDIR=$(mktemp -d /tmp/magisk_patcher_XXXXXX)
trap 'rm -rf "${WORKDIR}"' EXIT

echo "[*] Extracting Magisk assets from APK..."
unzip -q "${MAGISK_APK}" -d "${WORKDIR}"

if [[ ! -d "${WORKDIR}/lib/arm64-v8a" ]]; then
    echo "[-] Error: arm64-v8a binaries missing from Magisk APK."
    exit 1
fi

# 3. Transfer Components to Device
TARGET_DIR="/data/local/tmp/magisk_patcher"
echo "[*] Staging patching environment on device (${TARGET_DIR})..."
adb shell "rm -rf ${TARGET_DIR} && mkdir -p ${TARGET_DIR}"

adb push "${WORKDIR}/assets/boot_patch.sh" "${TARGET_DIR}/boot_patch.sh" >/dev/null
adb push "${WORKDIR}/assets/util_functions.sh" "${TARGET_DIR}/util_functions.sh" >/dev/null
adb push "${WORKDIR}/assets/stub.apk" "${TARGET_DIR}/stub.apk" >/dev/null

adb push "${WORKDIR}/lib/arm64-v8a/libmagiskboot.so" "${TARGET_DIR}/magiskboot" >/dev/null
adb push "${WORKDIR}/lib/arm64-v8a/libmagisk.so" "${TARGET_DIR}/magisk" >/dev/null
adb push "${WORKDIR}/lib/arm64-v8a/libmagiskinit.so" "${TARGET_DIR}/magiskinit" >/dev/null

if [[ -f "${WORKDIR}/lib/arm64-v8a/libinit-ld.so" ]]; then
    adb push "${WORKDIR}/lib/arm64-v8a/libinit-ld.so" "${TARGET_DIR}/init-ld" >/dev/null
fi

echo "[*] Uploading stock init_boot.img..."
adb push "${STOCK_INIT_BOOT}" "${TARGET_DIR}/init_boot.img" >/dev/null

# 4. Execute Patching on Device
echo "[*] Executing boot_patch.sh on device..."
adb shell "cd ${TARGET_DIR} && chmod 755 * && sh boot_patch.sh init_boot.img"

# 5. Retrieve Patched Image
echo "[*] Pulling patched image to host: ${OUTPUT_IMAGE}..."
adb pull "${TARGET_DIR}/new-boot.img" "${OUTPUT_IMAGE}"

# Clean up device temporary directory
adb shell "rm -rf ${TARGET_DIR}"

echo "[+] Success! Patched image generated at: ${OUTPUT_IMAGE}"
ls -lh "${OUTPUT_IMAGE}"
