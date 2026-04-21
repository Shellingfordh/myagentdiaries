#!/bin/bash
set -euo pipefail

# Lock down "rogue background behavior" for apps matching vendor patterns.
# This is best-effort without root: uses appops (persistent) + force-stop (immediate).
#
# What it does (per package):
# - appops set RUN_IN_BACKGROUND ignore
# - appops set RUN_ANY_IN_BACKGROUND ignore
# - (optional) appops set WAKE_LOCK ignore
# - am force-stop
#
# Limitations:
# - This cannot catch new installs automatically unless you run it again.
#   (For true "auto-apply on install", use Shizuku + an automation app or root.)

ADB_BIN="${ADB_BIN:-adb}"
INCLUDE_WAKELOCK="${INCLUDE_WAKELOCK:-1}" # set 0 to keep WAKE_LOCK untouched

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
OUT_DIR="$HOME/Downloads/android_vendor_lockdown_$TS"
mkdir -p "$OUT_DIR"

# Vendor-ish package prefixes (tune freely).
# Keep these broad; protect list below prevents breaking OS/OEM pieces.
PATTERNS=(
  '^com\.tencent\.'
  '^com\.qq\.'
  '^com\.taobao\.'
  '^com\.tmall\.'
  '^com\.alibaba\.'
  '^com\.alipay\.'
  '^com\.ant\.'
  '^com\.bytedance\.'
  '^com\.ss\.android\.'
  '^com\.xiaohongshu\.'
  '^com\.kuaishou\.'
  '^com\.smile\.gifmaker\.'
  '^com\.sina\.'
  '^com\.weibo\.'
  '^com\.bilibili\.'
  '^tv\.danmaku\.bili\.'
  '^com\.zhihu\.'
  '^com\.jd\.'
  '^com\.jingdong\.'
  '^com\.meituan\.'
  '^com\.sankuai\.'
  '^com\.dianping\.'
  '^com\.douban\.'
  '^com\.netease\.'
  '^com\.baidu\.'
  '^com\.umeng\.'
  '^com\.huawei\.'
  '^com\.oppo\.'
  '^com\.vivo\.'
  '^com\.miui\.'
  '^com\.xiaomi\.'
)

# Do not touch critical OS / connectivity / vendor framework packages.
PROTECT=(
  '^android$'
  '^com\.android\.'
  '^com\.google\.'            # keep Google out; you already have a separate GMS lockdown flow
  '^com\.qualcomm\.'
  '^com\.qti\.'
  '^org\.codeaurora\.'
  '^com\.miui\.core$'
  '^com\.xiaomi\.xmsf$'
  '^com\.xiaomi\.finddevice$'
  '^com\.xiaomi\.mipicks$'
  '^com\.xiaomi\.market$'
)

echo "👉 Backup + logs: $OUT_DIR"
echo "Patterns:" >"$OUT_DIR/patterns.txt"
printf '%s\n' "${PATTERNS[@]}" >>"$OUT_DIR/patterns.txt"
echo "Protect:" >>"$OUT_DIR/patterns.txt"
printf '%s\n' "${PROTECT[@]}" >>"$OUT_DIR/patterns.txt"

PKG_LIST="$("$ADB_BIN" shell pm list packages 2>/dev/null | sed 's/^package://g' | tr -d '\r')"

# Build fast grep regexes.
PATTERN_RE="$(printf '%s\n' "${PATTERNS[@]}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | paste -sd'|' -)"
PROTECT_RE="$(printf '%s\n' "${PROTECT[@]}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | paste -sd'|' -)"

TARGETS_TXT="$OUT_DIR/targets.txt"
printf '%s\n' "$PKG_LIST" | grep -E "$PATTERN_RE" | grep -Ev "$PROTECT_RE" | sort >"$TARGETS_TXT" || true

TARGET_COUNT="$(wc -l <"$TARGETS_TXT" | tr -d ' ')"
echo "✅ Targets: $TARGET_COUNT"

if [ "$TARGET_COUNT" -eq 0 ]; then
  echo "No matching packages found. Nothing to do."
  exit 0
fi

while IFS= read -r p; do
  [ -z "$p" ] && continue
  echo "-- $p"
  {
    echo "=== $p"
    echo "RUN_IN_BACKGROUND:"
    "$ADB_BIN" shell "appops get $p RUN_IN_BACKGROUND 2>/dev/null | head -n 5 || true"
    echo "RUN_ANY_IN_BACKGROUND:"
    "$ADB_BIN" shell "appops get $p RUN_ANY_IN_BACKGROUND 2>/dev/null | head -n 5 || true"
    echo "WAKE_LOCK:"
    "$ADB_BIN" shell "appops get $p WAKE_LOCK 2>/dev/null | head -n 5 || true"
    echo
  } >>"$OUT_DIR/appops_before.txt"

  "$ADB_BIN" shell "appops set $p RUN_IN_BACKGROUND ignore" >/dev/null 2>&1 || true
  "$ADB_BIN" shell "appops set $p RUN_ANY_IN_BACKGROUND ignore" >/dev/null 2>&1 || true
  if [ "$INCLUDE_WAKELOCK" = "1" ]; then
    "$ADB_BIN" shell "appops set $p WAKE_LOCK ignore" >/dev/null 2>&1 || true
  fi
  "$ADB_BIN" shell "am force-stop $p" >/dev/null 2>&1 || true
done <"$TARGETS_TXT"

"$ADB_BIN" shell "appops write-settings" >/dev/null 2>&1 || true

cat >"$OUT_DIR/REVERT.txt" <<'EOF'
Revert options:

1) Reset one package:
   adb shell appops reset <package>

2) Reset all appops (dangerous):
   adb shell appops reset
EOF

echo "✅ Done. Backup: $OUT_DIR"
