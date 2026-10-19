# Roblox Game Dumps Analyzer

UNC/SUNC-compliant analysis dump script. No feature toggles — it records how a game
works so the output can be pasted back for parsing.

## Run

`roblox/game_dumps_analyzer.lua` — run as a client local script (single file, no
dependencies). On startup it self-checks the environment and prints a PASS/FAIL
table to the executor console.

## What it collects

- **Remote Spy** — hooks `__namecall` and logs every `FireServer`/`InvokeServer`
  call with method, remote path, and args (ring buffer, 500 events, args capped at
  depth 2 / 10 keys). If the executor blocks hooking, falls back to polling remote
  listener existence (lower fidelity).
- **Hierarchy dump** — on Export only: ReplicatedStorage / ReplicatedFirst /
  workspace tree capped at depth 6, 2000 nodes.
- **Player state** — every 5s: leaderstats, tools, Humanoid stats (200 samples).

## Output

Written continuously (30s autosave while dirty) and on Export into:

```
<executor workspace>/game dumps/<GameName>_<PlaceId>/
```

- `remotes.json` — recorded remote events
- `playerstate.json` — state snapshots
- `hierarchy.json` — only written on manual Export
- `events.log` — timestamped append log (survives rejoin)

For game analysis, paste `remotes.json` + `events.log` first — those two carry
most of the signal.

## Panel buttons

- **Export** — force-write all three JSONs now
- **Stop** — stop recording (still run Export afterwards for a final flush)
- **Clear** — wipe buffers

## Limits (deliberate, ponytail caps)

- 500 remote events, then drops (counted in meta `dropped`)
- 200 state samples, oldest evicted
- Hooks unavailable → existence-only remote data
- Flat-file fallback if executor lacks `makefolder`
