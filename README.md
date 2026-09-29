# qb-pedplacer

> Free and open source from [RR Interactive](https://playrosie.com), the team behind the ROSIE FiveM city.
> [Docs](https://playrosie.com/docs/pedplacer/) · [Store page](https://playrosie.com/store/pedplacer/) · [Discord support](https://discord.gg/VMXzjgzN7R) · [All our scripts](https://playrosie.com/store/)

**Place, persist and manage world NPC peds — in-game, with a menu.**

`qb-pedplacer` is an admin tool for building living worlds. Walk up to a spot,
open a menu, and drop an NPC that **stays there forever** (saved to your database)
and streams in/out by distance so you never blow GTA's ped pool. Peds can idle,
run any GTA scenario, walk patrol routes, wander, hold weapons, be frozen or
invincible, and — uniquely — **loop any `scully_emotemenu` emote (with held props)
as a permanent animation.** Group peds together to hide/show or delete a whole
business at once. Also places persistent **radios/speakers** and **metal detectors**.

---

## ✨ Features

- **Persistent peds** saved to MySQL — survive restarts and server reboots.
- **Smart streaming + cull-detection** — peds spawn only when you're near, and if
  the engine culls one (common in MLOs) it silently respawns. No more "peds vanish
  until I restart the resource."
- **Emote bridge** — loop ANY emote from `scully_emotemenu` (animation + held props
  like a beer, clipboard, cigar) as a persistent ped scenario.
- **Behaviors:** idle, GTA scenario, patrol route (multi-point), wander, and paired
  interactions.
- **Weapons, freeze, invincibility** per ped.
- **Groups & area visibility** — save nearby peds as a named group; hide/show or
  delete an entire group or map area at runtime (great for open/closed businesses).
- **Bonus entities:** placeable radios/speakers and metal-detector props.
- **Developer export API** (see below) — other resources can query and control peds.
- **NUI management dashboard** — browse, search and edit every placed ped from a
  visual interface (new in 1.6.0).
- **Fully data-driven config** — 300+ ped-model presets, scenarios, weapons, radios.

---

## 📦 Requirements

**Required:** [`ox_lib`](https://github.com/overextended/ox_lib), `oxmysql`,
`qbx_core` (Qbox)

**Optional integrations** (auto-detected, degrade gracefully if absent):
- `scully_emotemenu` — enables the emote bridge (place peds that loop emotes + props).
- `rr-bartender` — bartender-behavior peds register as drink-order points.
- A casino dealer placer + a `metal-detectors` resource — for those bonus entity types.

Built for **Qbox** (`qbx_core` required). Admin permissions can also be granted
via server ACE (see Permissions).

---

## 🔧 Installation

1. Drop the `qb-pedplacer` folder into your `resources` directory.
2. Import **`sql/peds.sql`** into your database (creates `placed_peds`, `ped_groups`,
   `placed_radios`, `placed_metaldetectors`). Tables also self-create on first start.
3. Add `ensure qb-pedplacer` to your `server.cfg`.
4. Restart the server.

---

## 🎮 Usage

- Open the placer menu in-game with **`/pedplacer`** (command configurable via
  `Config.Command`).
- Requires admin permission (`Config.RequiredPermission`, default `admin`) or the
  server ACE `command.pedplacer`.
- Everything else — placing, moving, grouping, deleting, patrol routes, emotes — is
  done through the ox_lib menus. Placement data lives in the DB, not in code.

---

## 🔐 Permissions

Admin gating is ACE-based and configurable. On boot the resource runs:
`add_ace group.admin command.pedplacer allow`. Grant additional admins via your
normal ACE setup, or change `Config.RequiredPermission`. On QBCore/Qbox it also
accepts that framework's permission check.

---

## 🧩 Developer API (exports)

**Client:**
| Export | Purpose |
|---|---|
| `exports['qb-pedplacer']:GetPedHandle(dbId)` | live ped entity handle for a DB id |
| `exports['qb-pedplacer']:GetPedData(dbId)` | stored data for a placed ped |
| `exports['qb-pedplacer']:GetPedsByGroup(name)` | peds in a named group |
| `exports['qb-pedplacer']:GetGuardPeds()` | armed/guard peds (for defense scripts) |
| `exports['qb-pedplacer']:GetSpawnedPeds()` | all currently-spawned placed peds |

**Server:**
| Export | Purpose |
|---|---|
| `exports['qb-pedplacer']:SetGroupHidden(group, hidden)` | despawn/respawn a whole group for everyone |
| `exports['qb-pedplacer']:SetAreaHidden(key, x, y, radius, hidden)` | hide/show every placed ped in a radius |

Server callbacks (`lib.callback`) are also available: `getPeds`, `getGroups`,
`getRadios`, `getDetectors`, `getHiddenGroups`, `getHiddenAreas`.

---

## ⚙️ Configuration highlights (`config.lua`)

- `Config.Command` / `Config.RequiredPermission` — command + admin gate.
- `Config.PermanentPeds` — keep peds permanently loaded vs. stream by distance
  (leave `false` unless you place only a few dozen).
- `Config.RenderDistance` — how close before a ped spawns.
- `Config.PedModels` — 300+ categorized model presets buyers can extend.
- `Config.Scenarios`, `Config.Weapons`, `Config.RadioStations`, `Config.SpeakerModels`,
  `Config.PresetGroups` — all data-driven and editable.

---

## Credits

© RR Interactive. All rights reserved.

---

## License

Released under the [GNU GPL v3.0](LICENSE). You can use, change and share it; if you share or sell a modified version, it has to stay open source under the same license.

Made by [RR Interactive](https://playrosie.com).
