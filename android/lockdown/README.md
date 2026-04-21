# Android Lockdown Toolkit (adb + appops)

This folder contains host-side scripts that apply **persistent** background restrictions to an Android device over `adb`.

Scope:
- Works without root.
- Changes are applied via `appops` and `settings`, so they survive reboot.

Limitations:
- Truly automatic enforcement for *future installs* requires an on-device automation trigger (e.g. Shizuku automation, root, or a scheduled job).
- Without that, re-run `android_vendor_lockdown.sh` after installing new apps.

## Scripts

- `android_battery_audit.sh`
  - Captures snapshots of processes and power signals into `~/Downloads/android_audit_<timestamp>/`.

- `android_sleep_lockdown.sh`
  - Applies persistent `appops ignore` for selected packages and enables cached-app freezer.
  - Supports:
    - `--include-gms` (very aggressive; can break push/auth)
    - `--no-wakelock` (safer; weaker)

- `android_global_battery_tweaks.sh`
  - Applies global power-friendly settings such as disabling `mobile_data_always_on`.

- `android_vendor_lockdown.sh`
  - Scans installed packages and applies restrictions for vendor prefix patterns.
  - Edit `PATTERNS` / `PROTECT` to tune.

## Safety / Rollback

Each script writes a backup directory under `~/Downloads/` with:
- captured "before" state
- a `REVERT.txt` with `appops reset` commands

