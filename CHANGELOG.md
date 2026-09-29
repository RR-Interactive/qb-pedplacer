# Changelog

## 1.6.3 (2026-09-16)

- Added six **Gang House** preset groups (🟢 Families, 🟣 Ballas, 🟡 Vagos,
  ⚫ Lost MC, 🔴 Triads, 🟠 Cartel), 13 peds each, built from one shared layout
  in `config.lua`. Every ped carries a pistol and is placed **mortal** so
  rr-gangwar can run them: they fight rival sets on sight and respawn when killed.
- Preset group peds may now set `invincible` / `frozen` per ped; omitted values
  keep the old defaults (invincible, frozen when stationary).
- New exports `HoldPed(id, held)` / `IsPedHeld(id)`: another resource can drive a
  placed ped's fight. While held the stray snap-back is skipped and the row's
  behaviour thread is stopped; releasing restarts the placed behaviour. Holds are
  cleared on despawn.

## 1.6.2 (2026-09-12)

- Added the **🟢 Families Gang Party** preset group (17 peds) — drop a whole
  Families block party in one go: dancers, hype crew, OGs smoking and drinking,
  a corner boy, two homies arguing, armed lookouts and a roamer. Placed peds get
  `group_name = "🟢 Families Gang Party"` so the whole party can be hidden,
  shown or deleted together.
- Added more Families models to the 🎭 Gangs preset category: MP Families
  male, two street homies, Lamar Davis and Stretch.

## 1.6.1 (2026-08-22)

- Fixed placed peds vanishing until the resource was restarted. Three causes:
  - Non-idle peds (scenario/bartender) were unfrozen the instant they spawned,
    so any that streamed in before the world under them had loaded fell through
    it. Offshore locations were the worst case — the ped landed in the sea and
    swam off, but its handle stayed valid, so the streamer kept believing it was
    alive. They are now pinned until collision has loaded around them.
  - The streamer now also detects a stationary ped that has left its placed
    spot, snapping small strays back and rebuilding anything that fell through
    the map or drifted away (rate limited, and it gives up after 3 tries).
  - A character switch wiped the client's placed-ped list and never refetched
    it. The list is now reloaded on every character load.
- The streaming loop is error-guarded, so one bad row can no longer kill ped
  streaming for the rest of the session.

## 1.6.0 (2026-08-11)

- NUI management dashboard added (`html/`) — browse, search and edit placed
  peds from a visual interface.
- Emote bridge: loop any `scully_emotemenu` emote (with held props) as a
  persistent ped animation.
- Packaging: commercial licence, changelog and escrow config added.

## 1.5.0 (2026-06-30)

Initial public build.

- Persistent peds saved to MySQL — survive restarts, stream in/out by distance,
  cull-detection respawn for MLO interiors.
- Behaviors: idle, GTA scenario, patrol routes, wander, paired interactions.
- Weapons, freeze, invincibility per ped; groups and area visibility toggles.
- Placeable radios/speakers and metal detectors.
- Developer export API for other resources.
