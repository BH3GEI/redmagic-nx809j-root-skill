#!/usr/bin/env bash
#
# check_env.sh
# Diagnostic script for RedMagic 11 Pro (NX809J) connection state.
# Inspects USB bus, ADB daemon, Fastboot mode, and EDL 9008 status on macOS/Linux.
#

set -euo pipefail

echo "=================================================="
echo " RedMagic 11 Pro (NX809J) Environment Check"
echo "=================================================="

# 1. Check Operating System
OS_TYPE="$(uname -s)"
echo "[*] Operating System: ${OS_TYPE} ($(uname -m))"

# 2. Check Qualcomm EDL 9008 Status
echo ""
echo "[*] Checking for Qualcomm EDL 9008 device..."
EDL_FOUND=false

if [[ "${OS_TYPE}" == "Darwin" ]]; then
    if ioreg -p IOUSB -w0 -l 2>/dev/null | grep -q -i "QUSB_BULK"; then
        EDL_INFO=$(ioreg -p IOUSB -w0 -l | grep -i "QUSB_BULK" | tr -d ' ' || true)
        echo "    [+] Detected EDL 9008 device: ${EDL_INFO}"
        EDL_FOUND=true
    fi
elif [[ "${OS_TYPE}" == "Linux" ]]; then
    if lsusb 2>/dev/null | grep -q -i "05c6:9008"; then
        EDL_INFO=$(lsusb | grep -i "05c6:9008")
        echo "    [+] Detected EDL 9008 device: ${EDL_INFO}"
        EDL_FOUND=true
    fi
fi

if [[ "${EDL_FOUND}" == "false" ]]; then
    echo "    [-] No EDL 9008 device found on USB bus."
fi

# 3. Check Fastboot Device
echo ""
echo "[*] Checking for Fastboot devices..."
if command -v fastboot >/dev/null 2>&1; then
    FASTBOOT_DEVS=$(fastboot devices 2>/dev/null || true)
    if [[ -n "${FASTBOOT_DEVS}" ]]; then
        echo "    [+] Fastboot device detected:"
        echo "${FASTBOOT_DEVS}" | sed 's/^/        /'
    else
        echo "    [-] No devices in Fastboot mode."
    fi
else
    echo "    [-] 'fastboot' binary not found in PATH."
fi

# 4. Check ADB Device and Android Properties
echo ""
echo "[*] Checking for ADB devices..."
if command -v adb >/dev/null 2>&1; then
    ADB_DEVS=$(adb devices | grep -v "List of devices" | grep "device$" || true)
    if [[ -n "${ADB_DEVS}" ]]; then
        echo "    [+] ADB device online:"
        echo "${ADB_DEVS}" | sed 's/^/        /'

        echo ""
        echo "[*] Querying target device properties..."
        MODEL=$(adb shell getprop ro.product.model 2>/dev/null | tr -d '\r')
        NAME=$(adb shell getprop ro.product.name 2>/dev/null | tr -d '\r')
        FINGERPRINT=$(adb shell getprop ro.build.display.id 2>/dev/null | tr -d '\r')
        LOCKED=$(adb shell getprop ro.boot.flash.locked 2>/dev/null | tr -d '\r')
        VB_STATE=$(adb shell getprop ro.boot.vbmeta.device_state 2>/dev/null | tr -d '\r')
        SLOT=$(adb shell getprop ro.boot.slot_suffix 2>/dev/null | tr -d '\r')

        echo "    Model:        ${MODEL:-Unknown} (${NAME:-Unknown})"
        echo "    Build ID:     ${FINGERPRINT:-Unknown}"
        echo "    Active Slot:  ${SLOT:-Unknown}"
        echo "    Flash Locked: ${LOCKED:-Unknown} (0 = unlocked, 1 = locked)"
        echo "    VB State:     ${VB_STATE:-Unknown}"

        echo ""
        echo "[*] Testing Root Privileges..."
        SU_VER=$(adb shell "su -v 2>/dev/null" | tr -d '\r' || true)
        if [[ -n "${SU_VER}" ]]; then
            SU_ID=$(adb shell "su -c id 2>/dev/null" | tr -d '\r' || true)
            echo "    [+] Root status: ACTIVE (${SU_VER})"
            echo "    [+] Root identity: ${SU_ID}"
        else
            echo "    [-] Root status: NOT ACTIVE (su binary not accessible)"
        fi
    else
        echo "    [-] No ADB device authorized and online."
    fi
else
    echo "    [-] 'adb' binary not found in PATH."
fi

echo "=================================================="
