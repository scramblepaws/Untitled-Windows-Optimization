# Untitled Windows Optimization

A novice-friendly Windows debloat, privacy, and performance tool. It removes
bloat (Copilot, OneDrive, Xbox, preinstalled apps), disables telemetry and ads,
and applies performance tweaks — with a GUI, presets, and full revert.

Built in PowerShell, compiled to a double-clickable `.exe`.

## Features

- **GUI** with tabs per category: Debloat, Privacy, Performance
- **Presets**: Recommended and Aggressive one-click bundles, plus per-tweak checkboxes
- **Safe by default**: auto-creates a System Restore point and snapshots original registry/services state before changing anything
- **Restore Backup** button reverts everything it changed
- Live log pane showing exactly what ran
- Supports Windows 10 and 11 (tweaks are conditional where they differ)

## Build

```powershell
.\build.ps1            # produces WinDebloat.exe
```

The `.exe` must sit next to `tweaks.ps1` and `backup.ps1` at runtime.

## Run (without compiling)

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\WinDebloat.ps1       # self-elevates to admin
```

## Usage

1. Launch the app (accept the UAC prompt).
2. Click **Recommended** or **Aggressive** to pre-select tweaks, or tick individual checkboxes.
3. Click **Apply Selected**.
4. To undo, click **Restore Backup** (restores the latest snapshot).

## Scope

- **Debloat**: remove Copilot, OneDrive, Xbox, and preinstalled Store bloatware
- **Privacy**: disable telemetry, Cortana, ads, tips & suggestions
- **Performance**: startup delay, visual effects, power plan, hibernation

> **Note on revert limits**: registry and service changes are fully reversible via the
> backup snapshot. Removed Store apps are not re-provisionable offline; they can be
> reinstalled from the Microsoft Store manually.

## Disclaimer

Modifying Windows internals carries risk. A System Restore point is created
automatically before applying, but use at your own discretion. Test on a
non-critical machine first.
