# qb-pedplacer

Place NPCs anywhere in your city from an in-game menu and they stay there. They're saved to your database, come back after restarts, and stream in and out by distance so you don't fill up the ped pool.

Free and open source from [RR Interactive](https://playrosie.com), the team behind the ROSIE FiveM city.
[Docs](https://playrosie.com/docs/pedplacer/) · [Store page](https://playrosie.com/store/pedplacer/) · [Discord](https://discord.gg/VMXzjgzN7R) · [Our other scripts](https://playrosie.com/store/)

## What it does

- Peds are saved to MySQL and survive restarts
- They only spawn when someone is nearby. If the game culls one (happens a lot in MLOs) it quietly respawns, so no more peds vanishing until you restart the resource
- Loop any `scully_emotemenu` emote on a ped, props included (beer, clipboard, cigar and so on)
- Behaviors: idle, any GTA scenario, patrol routes with multiple points, wander, and paired interactions
- Weapons, freeze and invincibility per ped
- Save nearby peds as a group, then hide, show or delete the whole group or a map area at runtime. Handy for businesses that open and close
- Also places radios/speakers and metal detector props
- A dashboard to browse, search and edit every placed ped
- 300+ ped model presets plus scenarios, weapons and radio stations, all in the config
- Exports so your other scripts can find and control placed peds

## Requirements

- [ox_lib](https://github.com/overextended/ox_lib)
- oxmysql
- qbx_core (Qbox)

Optional, picked up automatically if you have them:
- `scully_emotemenu` for the emote loops
- `rr-bartender` so bartender peds take drink orders
- a `metal-detectors` resource for the metal detector props

## Install

1. Put `qb-pedplacer` in your resources folder
2. Import `sql/peds.sql` (the tables also get created on first start)
3. Add `ensure qb-pedplacer` to your server.cfg
4. Restart the server

## Using it

Type `/pedplacer` in-game (you can rename the command with `Config.Command`). You need admin (`Config.RequiredPermission`, `admin` by default) or the `command.pedplacer` ace.

Placing, moving, grouping, deleting, patrol routes and emotes are all done from the menus. Everything is stored in the database, not in code.

## Permissions

On start the resource adds `add_ace group.admin command.pedplacer allow`. Give other staff access through your normal ace setup or change `Config.RequiredPermission`. The Qbox/QBCore permission check works too.

## Exports

Client:

| Export | What it returns |
|---|---|
| `exports['qb-pedplacer']:GetPedHandle(dbId)` | the live ped entity for a database id |
| `exports['qb-pedplacer']:GetPedData(dbId)` | the saved data for a placed ped |
| `exports['qb-pedplacer']:GetPedsByGroup(name)` | peds in a named group |
| `exports['qb-pedplacer']:GetGuardPeds()` | armed/guard peds |
| `exports['qb-pedplacer']:GetSpawnedPeds()` | every placed ped that's spawned right now |

Server:

| Export | What it does |
|---|---|
| `exports['qb-pedplacer']:SetGroupHidden(group, hidden)` | despawn or respawn a whole group for everyone |
| `exports['qb-pedplacer']:SetAreaHidden(key, x, y, radius, hidden)` | hide or show every placed ped in a radius |

There are also `lib.callback` callbacks: `getPeds`, `getGroups`, `getRadios`, `getDetectors`, `getHiddenGroups`, `getHiddenAreas`.

## Config

- `Config.Command` / `Config.RequiredPermission`: the command and who can use it
- `Config.PermanentPeds`: keep every ped loaded instead of streaming by distance. Leave it `false` unless you only have a few dozen
- `Config.RenderDistance`: how close you get before a ped spawns
- `Config.PedModels`: the model presets, add your own
- `Config.Scenarios`, `Config.Weapons`, `Config.RadioStations`, `Config.SpeakerModels`, `Config.PresetGroups`

## License

[GNU GPL v3.0](LICENSE). Use it, change it, share it. If you share or sell a modified version it has to stay open source.

Made by [RR Interactive](https://playrosie.com).
