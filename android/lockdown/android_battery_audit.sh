#!/bin/bash
set -euo pipefail

if ! command -v adb >/dev/null 2>&1; then
  echo "❌ adb not found"
  exit 1
fi

if ! adb get-state >/dev/null 2>&1; then
  echo "❌ No ADB device. On the phone: unlock screen → enable USB debugging → set USB mode to File transfer (MTP) → accept the RSA prompt."
  adb devices -l || true
  exit 1
fi

TS="$(date +%Y%m%d_%H%M%S)"
OUT_DIR="$HOME/Downloads/android_audit_$TS"
mkdir -p "$OUT_DIR"

echo "✅ Device:"
adb shell getprop ro.product.model | tr -d '\r'
echo "Android $(adb shell getprop ro.build.version.release | tr -d '\r') (SDK $(adb shell getprop ro.build.version.sdk | tr -d '\r'))"
echo

echo "👉 Saving audit to: $OUT_DIR"

adb shell ps -A -o NAME,PID,USER >"$OUT_DIR/ps_all.txt" 2>/dev/null || true
adb shell "ps -A -o NAME,PID,USER | grep 'u0_' || true" >"$OUT_DIR/ps_userapps.txt" 2>/dev/null || true
adb shell top -b -n 1 >"$OUT_DIR/top.txt" 2>/dev/null || true
adb shell dumpsys power >"$OUT_DIR/dumpsys_power.txt" 2>/dev/null || true
adb shell dumpsys deviceidle >"$OUT_DIR/dumpsys_deviceidle.txt" 2>/dev/null || true
adb shell dumpsys batterystats >"$OUT_DIR/dumpsys_batterystats.txt" 2>/dev/null || true

echo
echo "== Running user app processes (snapshot) =="
sed -n '1,80p' "$OUT_DIR/ps_userapps.txt" || true
echo
echo "== Estimated power use (top) =="
sed -n '/Estimated power use/,/All kernel wake locks/p' "$OUT_DIR/dumpsys_batterystats.txt" | head -n 80 || true
echo
echo "✅ Done. Share the folder if you want deeper parsing:"
echo "$OUT_DIR"

