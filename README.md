This repo is a scratchpad for operational notes, repeatable workflows, and Codex skills.

## Android Gemma-4 (on-device, CLI)

If you want to run the Gemma-4-E2B GGUF on an Android phone via `adb`:

- Skill: `skills/android-gemma4-llamacpp/`
- One-shot deploy (host): `skills/android-gemma4-llamacpp/scripts/deploy_gemma4_android.sh`

### Where Files Live On The Phone

Default paths written by the deploy script:

- llama.cpp Android bundle: `/data/local/tmp/llama-b8863/`
- Model file: `/sdcard/Download/gemma4-q2.gguf`
- Launcher script (interactive CLI): `/data/local/tmp/llama-b8863/run-gemma4.sh`

Run:

- `adb shell /data/local/tmp/llama-b8863/run-gemma4.sh`

### Copy To Another Mac

Fastest: just re-run the deploy script on the other Mac (it downloads and pushes everything).

If you want to literally copy the already-deployed artifacts from this Mac:

1. On the source Mac:
   - `adb pull /data/local/tmp/llama-b8863 ./llama-b8863`
   - `adb pull /sdcard/Download/gemma4-q2.gguf ./gemma4-q2.gguf`
2. Move `./llama-b8863` and `./gemma4-q2.gguf` to the other Mac (AirDrop/USB/rsync).
3. On the target Mac:
   - `adb push ./llama-b8863 /data/local/tmp/llama-b8863`
   - `adb push ./gemma4-q2.gguf /sdcard/Download/gemma4-q2.gguf`
   - `adb shell chmod 755 /data/local/tmp/llama-b8863/*.sh /data/local/tmp/llama-b8863/llama-* 2>/dev/null || true`
