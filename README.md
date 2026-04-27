# Superpower Showdown

1v1 ranked PvP duels on Roblox. Pick from 5 powers, fight for 60s, persistent Elo.

## Layout

```
src/
  shared/           -> ReplicatedStorage.Shared (Config, Remotes, Abilities)
  server/           -> ServerScriptService.Server
  client/           -> StarterPlayer.StarterPlayerScripts.Client
default.project.json -> Rojo project file
```

## Sync into Studio (Rojo)

1. Install Rojo (https://rojo.space) — `cargo install rojo` or via the VS Code extension.
2. From this directory: `rojo serve`
3. In Studio, install the Rojo plugin and click "Connect".

Or `rojo build -o SuperpowerShowdown.rbxlx` to produce a place file you can open directly.

## Game loop

1. Lobby spawn → walk onto a blue or red glowing pad.
2. Stand on a pad for 3 seconds. If both pads have one player, you cross-pair. Otherwise the closest-Elo pair on a pad is matched.
3. Both players teleport to the arena. 8-second ability picker overlay; auto-picks if you wait.
4. 60-second fight. HP=0 ends instantly; timer-out: higher HP wins, tied HP draws.
5. Elo updates and is shown on a banner; you return to lobby after 4s.

## Abilities

| Power           | E activation                                | Notes                |
|-----------------|---------------------------------------------|----------------------|
| Flying          | Burst upward 0.4s                           | No gravity, hover    |
| Teleportation   | Blink 30 studs forward                      | 4s cooldown          |
| Super Strength  | Ground slam (radius 14, 25 dmg + knockback) | 3x punch dmg, 6s cd  |
| Super Speed     | 2s sprint burst                             | Always 2x walkspeed  |
| Invisibility    | Vanish for 4s                               | 1.5x punch dmg, 10s  |

## Elo

- Stored in DataStore `SuperpowerShowdownElo_v1` (skipped in Studio test sessions).
- Default 1000.
- Deltas: equal ±25, favored ±10, upset ±40, draw 0. Favored gap = 100 Elo.

## UX guarantees

- Welcome overlay in lobby explains pads + controls before you need to act.
- Ability picker is full-screen, "CHOOSE YOUR POWER vs <opponent>".
- "YOUR POWER: X" banner when the fight starts.
- Persistent bottom-center controls strip: `LEFT-CLICK = Attack • E = Ability`.
- Persistent right-side ability HUD with name, "Press E to use", cooldown bar.
- Elo over every player's head: `Name` + `Elo: ####`.
