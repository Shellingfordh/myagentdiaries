---
name: android-gemma4-llamacpp
description: Deploy llama.cpp Android arm64 CLI + a Gemma-4-E2B GGUF model to a connected Android phone via adb, then run it from the command line. Use for PixelExperience/Android 13+ devices when you want a reproducible, scriptable on-device LLM workflow.
---

# Android Gemma4 Llamacpp

## Overview

This skill installs a **prebuilt llama.cpp Android arm64 binary** and a **Gemma-4-E2B GGUF** onto a connected Android device (no root required), then runs the model via `adb shell` in an interactive CLI.

Use this when:
- You want an on-device LLM that can be started/stopped from a terminal.
- The device can be accessed over `adb` (USB debugging enabled).
- You want a reproducible, scripted deployment (binary + model + launcher script).

## Quick Start

1. Connect the phone via USB.
2. On the phone: enable `USB debugging`, accept the RSA prompt, and set USB mode to `File transfer (MTP)` for stable ADB.
3. Run the deploy script:
   - `skills/android-gemma4-llamacpp/scripts/deploy_gemma4_android.sh`
4. Start the on-device CLI:
   - The deploy script prints the exact `adb shell ...` command to run.

## What Gets Installed (Device)

- llama.cpp bundle: `/data/local/tmp/llama-b8863/` (or a similar versioned folder)
- model: `/sdcard/Download/gemma4-q2.gguf` (default; configurable)
- launcher: `/data/local/tmp/llama-b8863/run-gemma4.sh`

## Default Model Choice

The default deploy target is:
- `HauhauCS/Gemma-4-E2B-Uncensored-HauhauCS-Aggressive`
- `Gemma-4-E2B-Uncensored-HauhauCS-Aggressive-Q2_K_P.gguf` (~3.0 GB)

Rationale: `Q2_K_P` is the most likely to fit/boot on mid-range Android devices without instantly OOMing.

## Verification Checklist

- `adb devices -l` shows the device as `device`
- `adb shell /data/local/tmp/.../llama-cli -h` prints usage
- Running `run-gemma4.sh` opens an interactive prompt and generates text

## Notes

- Expect higher heat + battery drain while generating tokens. This is normal for on-device CPU inference.
- If ADB randomly “loses” the device, re-run `adb usb` and ensure the phone stays unlocked during deployment.

## Resources

- scripts:
  - `scripts/deploy_gemma4_android.sh` (end-to-end deploy)
  - `scripts/hf_signed_url.py` (resolve HuggingFace `resolve/main/...` redirects to signed CAS URLs)
- references:
  - `references/known_issues.md`
