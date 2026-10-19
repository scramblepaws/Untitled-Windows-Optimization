# Glossary

- **Tweak** — a single reversible registry/service/app change. Defined by an id, name, category, presets, and an apply function.
- **Preset** — a named bundle of tweaks: `recommended` (safe, everyday) or `aggressive` (thorough, higher risk).
- **Bloatware** — preinstalled or unwanted apps/features (Copilot, OneDrive, Xbox, Store apps).
- **Debloat** — removing bloatware (uninstall app + disable the underlying feature/keys).
- **Telemetry** — OS data-collection features (Diagnostic Data, DiagTrack).
- **Privacy tweak** — disables telemetry, ads, tips, and data sharing.
- **Performance tweak** — a change that improves responsiveness (startup delay, visual effects, power plan, hibernation).
- **Backup** — a timestamped snapshot of original registry subtrees, service startup states, and the installed appx list, taken before applying.
- **Revert** — restoring that snapshot via the Restore Backup button.
- **System Restore point** — a Windows checkpoint created automatically before applying tweaks.

## Roblox analysis

- **Dump Script** — the single-file client script (`game_dumps_analyzer.lua`) that continuously records game data and writes it to disk for analysis. No feature toggles.
- **Remote Spy** — capture of RemoteEvent/RemoteFunction calls (`FireServer`/`InvokeServer`) with method, path, and arguments, via hooks or (degraded) listener polling.
- **Hierarchy Dump** — a capped snapshot of ReplicatedStorage, ReplicatedFirst, and workspace structure (classes, names, paths, attributes, positions).
- **Player State** — periodic snapshot of the local player's leaderstats, tools, and Humanoid stats.
- **Game Dumps folder** — the executor-workspace directory `game dumps/<GameName>_<PlaceId>/` holding `remotes.json`, `playerstate.json`, `hierarchy.json`, and `events.log`.
- **Compat Layer** — the guarded resolution of UNC/SUNC executor functions (`writefile`, `getgenv`, `hookmetamethod`, etc.); missing functions degrade features instead of crashing.
