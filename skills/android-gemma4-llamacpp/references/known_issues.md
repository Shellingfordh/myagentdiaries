# Known Issues / Fixes

## ADB Flakiness

Symptoms:
- `adb devices` shows nothing
- `adb shell ...` intermittently returns `no devices/emulators found`

Fixes:
- Unlock phone, accept RSA prompt, keep screen on during deploy
- USB mode: `File transfer (MTP)` (not charging-only)
- Restart:
  - `adb kill-server`
  - `adb start-server`
  - `adb usb`

## `CANNOT LINK EXECUTABLE ... libllama-common.so not found`

Cause: Android dynamic linker does not search the binary directory by default.

Fix: always run with:
- `LD_LIBRARY_PATH=/data/local/tmp/<llama-dir>`

The launcher script written by `deploy_gemma4_android.sh` sets this automatically.

## Model Too Slow / Too Hot

Mitigations:
- Use smaller quant (e.g. `Q2_K_P` before `Q4_K_P`)
- Reduce context: `-c 2048` (don’t start at 4096)
- Reduce threads: `-t 4` or `-t 5`

## Push/Google Features Break After Battery Lockdown

If you previously applied aggressive `appops ignore` for Google services:
- Downloads that rely on Google components may still work (direct HTTP), but push/auth/sync can break.
- Fix by resetting appops for the affected package:
  - `adb shell appops reset com.google.android.gms`

