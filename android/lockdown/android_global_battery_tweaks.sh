#!/bin/bash
set -euo pipefail

ADB_BIN="${ADB_BIN:-adb}"

if ! command -v "$ADB_BIN" >/dev/null 2>&1; then
  echo "❌ adb not found"
  exit 1
fi

if ! "$ADB_BIN" get-state >/dev/null 2>&1; then
  echo "❌ No ADB device online"
  "$ADB_BIN" devices -l || true
  exit 1
fi

TS="$(date +%Y%m%d_%H%M%S)"
OUT_DIR="$HOME/Downloads/android_global_tweaks_$TS"
mkdir -p "$OUT_DIR"

echo "👉 Backup: $OUT_DIR"

backup_key() {
  local ns="$1"
  local key="$2"
  echo "$ns:$key=$("$ADB_BIN" shell "settings get $ns $key" 2>/dev/null | tr -d '\r')" >>"$OUT_DIR/before.txt"
}

set_key() {
  local ns="$1"
  local key="$2"
  local val="$3"
  "$ADB_BIN" shell "settings put $ns $key $val" >/dev/null 2>&1 || true
}

# Backups
backup_key global mobile_data_always_on
backup_key global wifi_wakeup_enabled
backup_key global wifi_scan_always_enabled
backup_key global ble_scan_always_enabled
backup_key global cached_apps_freezer
backup_key global app_standby_enabled
backup_key global network_recommendations_enabled

# Apply (persist across reboot)
# - mobile_data_always_on: developer option; keeping the radio up drains standby battery
set_key global mobile_data_always_on 0
# - wifi_wakeup_enabled: prevent auto-wakeup Wi‑Fi when you leave home (can improve standby)
set_key global wifi_wakeup_enabled 0
# - scan always: already often 0; enforce anyway
set_key global wifi_scan_always_enabled 0
set_key global ble_scan_always_enabled 0
# - freezer + app standby are core to "screen-off calm"
set_key global cached_apps_freezer 1
set_key global app_standby_enabled 1
# - avoid extra network suggestions
set_key global network_recommendations_enabled 0

{
  echo "=== after"
  for k in mobile_data_always_on wifi_wakeup_enabled wifi_scan_always_enabled ble_scan_always_enabled cached_apps_freezer app_standby_enabled network_recommendations_enabled; do
    echo "global:$k=$("$ADB_BIN" shell "settings get global $k" 2>/dev/null | tr -d '\r')"
  done
} >"$OUT_DIR/after.txt"

cat >"$OUT_DIR/REVERT.txt" <<'EOF'
Revert by restoring the values from before.txt. Examples:
  adb shell settings put global mobile_data_always_on 1
  adb shell settings put global wifi_wakeup_enabled 1
EOF

echo "✅ Applied global battery tweaks. See:"
echo "$OUT_DIR/before.txt"
echo "$OUT_DIR/after.txt"

