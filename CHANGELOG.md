# Changelog

## 1.6.3 (2026-09-16)

- Six gang house preset groups (Families, Ballas, Vagos, Lost MC, Triads, Cartel), 13 peds each, built from one shared layout in `config.lua`. Every ped has a pistol and is placed mortal so a gang war script can run them
- Preset group peds can set `invincible` / `frozen` per ped. If you leave them out you get the old defaults (invincible, frozen when stationary)
- New exports `HoldPed(id, held)` and `IsPedHeld(id)` so another resource can take over a placed ped's fight. While held, snap-back and the ped's behaviour thread are paused. Holds clear on despawn

## 1.6.2 (2026-09-12)

- Families block party preset group (17 peds): dancers, hype crew, OGs smoking and drinking, a corner boy, two homies arguing, armed lookouts and a roamer. They share a group name so the whole party can be hidden, shown or deleted together
- More Families models in the gang presets

## 1.6.1 (2026-08-22)

- Fixed placed peds vanishing until the resource was restarted. There were three causes:
  - Non-idle peds were unfrozen as soon as they spawned, so if the ground under them hadn't loaded yet they fell through. Offshore spots were the worst, the ped would land in the sea and swim off. They now stay pinned until collision loads
  - The streamer now notices when a stationary ped has left its spot. Small drifts get snapped back, and anything that fell through the map gets rebuilt (rate limited, gives up after 3 tries)
  - Switching character cleared the placed ped list and never loaded it again. It now reloads on every character load
- The streaming loop is error guarded, so one bad row can't stop ped streaming for the rest of the session

## 1.6.0 (2026-08-11)

- Dashboard (`html/`) to browse, search and edit placed peds
- Loop any `scully_emotemenu` emote (with props) on a placed ped

## 1.5.0 (2026-06-30)

First public build.

- Peds saved to MySQL, streamed by distance, respawned if the game culls them in MLOs
- Behaviors: idle, GTA scenario, patrol routes, wander, paired interactions
- Weapons, freeze and invincibility per ped, plus groups and area visibility
- Radios/speakers and metal detectors
- Exports for other resources
