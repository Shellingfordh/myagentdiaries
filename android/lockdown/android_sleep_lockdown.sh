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
BACKUP_DIR="$HOME/Downloads/android_lockdown_backup_$TS"
mkdir -p "$BACKUP_DIR"

# Conservative defaults: block background + wakelocks for common battery hogs.
# Add/remove packages by passing them as args or editing DEFAULT_PKGS below.
# Flags:
#   --include-gms     Also restrict core Google Play services processes (may break push/Google features).
#   --no-wakelock     Do not touch WAKE_LOCK appops (safer, weaker).
INCLUDE_GMS=0
TOUCH_WAKELOCK=1
ARGS_PKGS=()
for a in "$@"; do
  case "$a" in
    --include-gms) INCLUDE_GMS=1 ;;
    --no-wakelock) TOUCH_WAKELOCK=0 ;;
    *) ARGS_PKGS+=("$a") ;;
  esac
done

# Never touch critical OS/telephony UI packages.
PROTECT_PKGS=(
  android
  com.android.systemui
  com.android.phone
  com.qti.phone
  org.codeaurora.ims
  com.android.providers.telephony
  com.android.settings
)

is_protected() {
  local p="$1"
  for x in "${PROTECT_PKGS[@]}"; do
    if [ "$p" = "$x" ]; then
      return 0
    fi
  done
  return 1
}

DEFAULT_PKGS=(
  com.google.android.googlequicksearchbox
  com.android.vending
  com.google.android.apps.photos
  com.google.android.apps.turbo
  com.google.android.settings.intelligence
  com.google.android.apps.chromecast.app
  com.google.android.apps.wear.companion
  com.google.ar.core
  com.google.android.gms.location.history
  com.tencent.tim
  com.tencent.nrc
  com.joaomgcd.join
)

if [ "${#ARGS_PKGS[@]}" -gt 0 ]; then
  PKGS=("${ARGS_PKGS[@]}")
else
  PKGS=("${DEFAULT_PKGS[@]}")
fi

if [ "$INCLUDE_GMS" -eq 1 ]; then
  PKGS+=(
    com.google.android.gms
    com.google.android.gms.persistent
    com.google.android.gms.unstable
    com.google.process.gservices
    com.google.process.gapps
    com.google.android.gsf
  )
fi

echo "👉 Backup: $BACKUP_DIR"

echo "✅ Applying persistent background restrictions (survive reboot):"
for p in "${PKGS[@]}"; do
  if is_protected "$p"; then
    echo "-- $p (protected, skip)"
    continue
  fi
  echo "-- $p"
  {
    echo "=== $p"
    echo "RUN_IN_BACKGROUND:"
    adb shell "appops get $p RUN_IN_BACKGROUND 2>/dev/null | head -n 5 || true"
    echo "RUN_ANY_IN_BACKGROUND:"
    adb shell "appops get $p RUN_ANY_IN_BACKGROUND 2>/dev/null | head -n 5 || true"
    echo "WAKE_LOCK:"
    adb shell "appops get $p WAKE_LOCK 2>/dev/null | head -n 5 || true"
    echo
  } >>"$BACKUP_DIR/appops_before.txt"

  adb shell "appops set $p RUN_IN_BACKGROUND ignore" >/dev/null 2>&1 || true
  adb shell "appops set $p RUN_ANY_IN_BACKGROUND ignore" >/dev/null 2>&1 || true
  if [ "$TOUCH_WAKELOCK" -eq 1 ]; then
    adb shell "appops set $p WAKE_LOCK ignore" >/dev/null 2>&1 || true
  fi

  # Stop now; persistence comes from appops.
  adb shell "am force-stop $p" >/dev/null 2>&1 || true
done

adb shell "appops write-settings" >/dev/null 2>&1 || true

echo
echo "✅ Enabling stronger cached-app freezing (persist across reboot):"
{
  echo "=== settings before"
  adb shell "settings get global cached_apps_freezer || true"
  adb shell "device_config get activity_manager use_freezer || true"
  adb shell "device_config get activity_manager use_freezer_reaper_enabled || true"
  echo
} >>"$BACKUP_DIR/system_before.txt"

# Mirrors Android's "Suspend execution for cached apps".
adb shell "settings put global cached_apps_freezer 1" >/dev/null 2>&1 || true
adb shell "device_config put activity_manager use_freezer true" >/dev/null 2>&1 || true
adb shell "device_config put activity_manager use_freezer_reaper_enabled true" >/dev/null 2>&1 || true

{
  echo "=== settings after"
  adb shell "settings get global cached_apps_freezer || true"
  adb shell "device_config get activity_manager use_freezer || true"
  adb shell "device_config get activity_manager use_freezer_reaper_enabled || true"
  echo
} >>"$BACKUP_DIR/system_after.txt"

cat >"$BACKUP_DIR/REVERT.txt" <<'EOF'
Revert options (pick one):

1) Reset one package to defaults:
   adb shell appops reset <package>

2) Reset ALL packages appops to defaults (dangerous; affects everything):
   adb shell appops reset

3) Unforce-stop is not needed; apps will resume naturally if allowed.

4) Undo cached-app freezing toggles:
   adb shell settings put global cached_apps_freezer device_default
   adb shell device_config delete activity_manager use_freezer
   adb shell device_config delete activity_manager use_freezer_reaper_enabled
EOF

echo
echo "✅ Done."
echo "Backup: $BACKUP_DIR"
echo "Revert:  $BACKUP_DIR/REVERT.txt"
