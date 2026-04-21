#!/bin/bash
set -euo pipefail

# End-to-end deploy:
# - downloads latest llama.cpp android-arm64 bundle (prebuilt)
# - downloads Gemma GGUF from HuggingFace (resumable)
# - pushes both to a connected Android device via adb
# - writes a launcher script on the device to start an interactive CLI
#
# Requirements (host/mac):
# - adb
# - python3
# - curl
# - tar
# Optional:
# - aria2c (faster downloads)

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
SKILL_DIR="$(cd -- "$ROOT_DIR/.." >/dev/null 2>&1 && pwd)"

ADB_BIN="${ADB_BIN:-adb}"
PY_BIN="${PY_BIN:-python3}"

REPO_DEFAULT="HauhauCS/Gemma-4-E2B-Uncensored-HauhauCS-Aggressive"
FILE_DEFAULT="Gemma-4-E2B-Uncensored-HauhauCS-Aggressive-Q2_K_P.gguf"

HF_REPO="${HF_REPO:-$REPO_DEFAULT}"
HF_FILE="${HF_FILE:-$FILE_DEFAULT}"

MODEL_ALIAS="${MODEL_ALIAS:-gemma4-q2.gguf}"
MODEL_DEVICE_PATH="${MODEL_DEVICE_PATH:-/sdcard/Download/$MODEL_ALIAS}"

LLAMA_DEVICE_DIR="${LLAMA_DEVICE_DIR:-/data/local/tmp/llama-b8863}"
LLAMA_TAG="${LLAMA_TAG:-latest}"

THREADS="${THREADS:-6}"
CTX_SIZE="${CTX_SIZE:-2048}"
N_PREDICT="${N_PREDICT:-256}"
TEMP="${TEMP:-0.7}"
TOP_P="${TOP_P:-0.95}"

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Options (env overrides in parentheses):
  --repo <owner/name>          HuggingFace repo ($HF_REPO)
  --file <filename.gguf>       HuggingFace file ($HF_FILE)
  --model-alias <name.gguf>    Device filename ($MODEL_ALIAS)
  --device-model-path <path>   Device model path ($MODEL_DEVICE_PATH)
  --llama-dir <path>           Device llama dir ($LLAMA_DEVICE_DIR)
  --llama-tag <tag|latest>     llama.cpp release tag ($LLAMA_TAG)

  --threads <n>                llama-cli -t ($THREADS)
  --ctx <n>                    llama-cli -c ($CTX_SIZE)
  --n-predict <n>              llama-cli -n ($N_PREDICT)
  --temp <f>                   llama-cli --temp ($TEMP)
  --top-p <f>                  llama-cli --top-p ($TOP_P)

  --serial <serial>            ADB device serial (ADB_SERIAL)

Example:
  $0 --repo "$REPO_DEFAULT" --file "$FILE_DEFAULT"
EOF
}

ADB_SERIAL="${ADB_SERIAL:-}"
while [ "${1:-}" != "" ]; do
  case "$1" in
    --repo) HF_REPO="$2"; shift 2 ;;
    --file) HF_FILE="$2"; shift 2 ;;
    --model-alias) MODEL_ALIAS="$2"; MODEL_DEVICE_PATH="/sdcard/Download/$MODEL_ALIAS"; shift 2 ;;
    --device-model-path) MODEL_DEVICE_PATH="$2"; shift 2 ;;
    --llama-dir) LLAMA_DEVICE_DIR="$2"; shift 2 ;;
    --llama-tag) LLAMA_TAG="$2"; shift 2 ;;
    --threads) THREADS="$2"; shift 2 ;;
    --ctx) CTX_SIZE="$2"; shift 2 ;;
    --n-predict) N_PREDICT="$2"; shift 2 ;;
    --temp) TEMP="$2"; shift 2 ;;
    --top-p) TOP_P="$2"; shift 2 ;;
    --serial) ADB_SERIAL="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1"; usage; exit 2 ;;
  esac
done

adb_cmd() {
  if [ -n "$ADB_SERIAL" ]; then
    "$ADB_BIN" -s "$ADB_SERIAL" "$@"
  else
    "$ADB_BIN" "$@"
  fi
}

require_cmd() {
  local c="$1"
  if ! command -v "$c" >/dev/null 2>&1; then
    echo "❌ Missing required command: $c"
    exit 1
  fi
}

require_cmd "$ADB_BIN"
require_cmd "$PY_BIN"
require_cmd curl
require_cmd tar

if ! adb_cmd get-state >/dev/null 2>&1; then
  echo "❌ No ADB device online."
  echo "Fix: unlock phone → enable USB debugging → accept RSA prompt → USB mode File transfer (MTP)"
  adb_cmd devices -l || true
  exit 1
fi

echo "✅ ADB device online: $(adb_cmd get-serialno | tr -d '\r')"

CACHE_DIR="${CACHE_DIR:-$HOME/.cache/android-gemma4-llamacpp}"
mkdir -p "$CACHE_DIR"

get_llama_android_url() {
  if [ "$LLAMA_TAG" != "latest" ]; then
    # Use explicit tag.
    local tag="$LLAMA_TAG"
    echo "https://github.com/ggml-org/llama.cpp/releases/download/$tag/llama-$tag-bin-android-arm64.tar.gz"
    return 0
  fi

  "$PY_BIN" - <<'PY'
import json, urllib.request
url="https://api.github.com/repos/ggerganov/llama.cpp/releases/latest"
with urllib.request.urlopen(url, timeout=30) as r:
    data=json.load(r)
tag=data.get("tag_name")
assets=data.get("assets", [])
for a in assets:
    name=(a.get("name") or "").lower()
    if name.endswith("bin-android-arm64.tar.gz"):
        print(a.get("browser_download_url"))
        raise SystemExit(0)
raise SystemExit("No android arm64 tarball found in latest release "+str(tag))
PY
}

LLAMA_URL="$(get_llama_android_url)"
LLAMA_TARBALL="$CACHE_DIR/llama-android.tar.gz"
LLAMA_EXTRACT_DIR="$CACHE_DIR/llama-android"

echo "👉 Download llama.cpp android bundle"
echo "   $LLAMA_URL"

curl -L -C - -o "$LLAMA_TARBALL" "$LLAMA_URL"
rm -rf "$LLAMA_EXTRACT_DIR"
mkdir -p "$LLAMA_EXTRACT_DIR"
tar -xzf "$LLAMA_TARBALL" -C "$LLAMA_EXTRACT_DIR"

LLAMA_LOCAL_DIR="$(find "$LLAMA_EXTRACT_DIR" -maxdepth 2 -type f -name 'llama-cli' -print -quit | xargs -I{} dirname {})"
if [ -z "$LLAMA_LOCAL_DIR" ] || [ ! -f "$LLAMA_LOCAL_DIR/llama-cli" ]; then
  echo "❌ Failed to locate llama-cli after extracting tarball"
  exit 1
fi

echo "👉 Push llama bundle to device: $LLAMA_DEVICE_DIR"
adb_cmd shell "rm -rf '$LLAMA_DEVICE_DIR' && mkdir -p '$LLAMA_DEVICE_DIR'"
adb_cmd push -p "$LLAMA_LOCAL_DIR/" "$LLAMA_DEVICE_DIR"
adb_cmd shell "chmod 755 '$LLAMA_DEVICE_DIR/llama-cli' '$LLAMA_DEVICE_DIR/llama-server' 2>/dev/null || true"

echo "👉 Resolve HuggingFace signed URL"
SIGNED_URL="$("$PY_BIN" "$SKILL_DIR/scripts/hf_signed_url.py" --repo "$HF_REPO" --file "$HF_FILE")"

MODEL_LOCAL="$CACHE_DIR/$MODEL_ALIAS"
echo "👉 Download model to host cache: $MODEL_LOCAL"

if command -v aria2c >/dev/null 2>&1; then
  aria2c -x 16 -s 16 -c --file-allocation=none -o "$MODEL_ALIAS" -d "$CACHE_DIR" "$SIGNED_URL"
else
  curl -L -C - -o "$MODEL_LOCAL" "$SIGNED_URL"
fi

echo "👉 Push model to device: $MODEL_DEVICE_PATH"
adb_cmd push -p "$MODEL_LOCAL" "$MODEL_DEVICE_PATH"

echo "👉 Write launcher on device"
LAUNCHER_TMP="$(mktemp)"
cat >"$LAUNCHER_TMP" <<SH
#!/system/bin/sh
DIR="$LLAMA_DEVICE_DIR"
MODEL="$MODEL_DEVICE_PATH"
export LD_LIBRARY_PATH="\$DIR"
exec "\$DIR/llama-cli" -m "\$MODEL" --chat-template gemma -t "$THREADS" -c "$CTX_SIZE" -n "$N_PREDICT" --temp "$TEMP" --top-p "$TOP_P" -i
SH

adb_cmd push -p "$LAUNCHER_TMP" "$LLAMA_DEVICE_DIR/run-gemma4.sh"
adb_cmd shell "chmod 755 '$LLAMA_DEVICE_DIR/run-gemma4.sh'"
rm -f "$LAUNCHER_TMP"

echo "👉 Smoke test (help output)"
adb_cmd shell "LD_LIBRARY_PATH='$LLAMA_DEVICE_DIR' '$LLAMA_DEVICE_DIR/llama-cli' -h >/dev/null"

echo
echo "✅ Deploy complete."
echo "Run:"
echo "  adb shell '$LLAMA_DEVICE_DIR/run-gemma4.sh'"

