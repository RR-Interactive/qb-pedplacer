-- ═══════════════════════════════════════════════════════════
--  STATE
-- ═══════════════════════════════════════════════════════════
local SpawnedPeds   = {}   -- [dbId] = { handle, data, thread }
local PreviewPed    = nil
local IsPlacing     = false
local isLoggedIn    = false
local PlacerDataLoaded = false -- false → the streaming loop refetches every placed row (first spawn AND after a character switch)
local AllPedData    = {}
local PatrolThreads = {} -- [dbId] = true (tracks active patrol/wander threads)
local FailedPeds    = {} -- [dbId] = true (invalid model — logged once, never retried)
local HealTries     = {} -- [dbId] = how many times we've rebuilt a ped that left its placed spot (4 = gave up)
local HealNextAt    = {} -- [dbId] = GetGameTimer() before which we won't rebuild it again
local HiddenGroups  = {} -- [group_name] = true → peds in this group stay despawned (e.g. a closed business)
local HiddenAreas   = {} -- [key] = { x, y, r } → peds within this 2D radius stay despawned (e.g. a closed venue)
local ClaimedPeds   = {} -- [dbId] = true → another resource (rr-girlfriend) owns this ped's entity; never (re)spawn our copy
local HeldPeds      = {} -- [dbId] = true → another resource (rr-gangwar) is driving this ped's fight: no stray snap-back, no behaviour thread

-- Home Control bridge state (rr-homecontrol)
local PartyAreas         = {} -- [key] = { x, y, z, r, mode = 'party'|'away', anims, excludeModels, excludeBehaviors, exit, walkMs, graceUntil }
local DisabledRadioAreas = {} -- [key] = { x, y, r } → speaker zones inside stay silent while a home's music is off
local NextBehaviorToken  = 0  -- each behavior thread gets a unique token so starting a new one invalidates the old instantly

-- Radio state
local SpawnedRadios = {}  -- [dbId] = { prop = objHandle, audioVeh = vehHandle, data = row }
local AllRadioData  = {}

-- Metal-detector state
local SpawnedDetectors   = {}  -- [dbId] = { prop = objHandle, data = row }
local AllDetectorData    = {}
local DetectorTriggered  = {}  -- [dbId] = true while player is inside the scan radius (debounce)

-- ═══════════════════════════════════════════════════════════
--  HELPERS
-- ═══════════════════════════════════════════════════════════

local function LoadModel(model)
    local hash = type(model) == 'number' and model or joaat(model)
    if not IsModelValid(hash) then return nil end
    RequestModel(hash)
    local timeout = 0
    while not HasModelLoaded(hash) do
        Wait(10)
        timeout = timeout + 10
        if timeout > 10000 then return nil end
    end
    return hash
end

--- Add-on streamed peds can come out of CreatePed with no component variation
--- applied at all — solid but invisible. Force drawable 0 / texture 0 on every
--- component for the models flagged in Config.AddonPeds.
--- Deliberately unconditional (no GetNumberOfPedDrawableVariations guard): in
--- the failing case the variations aren't enumerable in the first place, so
--- guarding on the count would skip exactly the peds that need this.
local function ApplyAddonPedVariation(ped, modelName)
    if not modelName or not Config.AddonPeds then return end
    if not Config.AddonPeds[string.lower(tostring(modelName))] then return end
    SetPedDefaultComponentVariation(ped)
    for comp = 0, 11 do
        SetPedComponentVariation(ped, comp, 0, 0, 0)
    end
end

function DrawText3D(x, y, z, text)
    SetTextScale(0.35, 0.35)
    SetTextFont(4)
    SetTextProportional(true)
    SetTextColour(255, 255, 255, 215)
    SetTextEntry('STRING')
    SetTextCentre(true)
    AddTextComponentString(text)
    SetDrawOrigin(x, y, z, 0)
    DrawText(0.0, 0.0)
    local factor = string.len(text) / 370
    DrawRect(0.0, 0.0 + 0.0125, 0.017 + factor, 0.03, 0, 0, 0, 100)
    ClearDrawOrigin()
end

local function GetCoordsFromCam(distance)
    local camCoords = GetGameplayCamCoord()
    local camRot    = GetGameplayCamRot(2)
    local fwd = vector3(
        -math.sin(math.rad(camRot.z)) * math.abs(math.cos(math.rad(camRot.x))),
        math.cos(math.rad(camRot.z)) * math.abs(math.cos(math.rad(camRot.x))),
        math.sin(math.rad(camRot.x))
    )
    local target = camCoords + fwd * (distance or 10.0)
    local ray = StartShapeTestRay(camCoords.x, camCoords.y, camCoords.z, target.x, target.y, target.z, -1, PlayerPedId(), 0)
    local _, hit, endCoords = GetShapeTestResult(ray)
    return hit and endCoords or target
end

-- ═══════════════════════════════════════════════════════════
--  BEHAVIOR ENGINE
-- ═══════════════════════════════════════════════════════════

--- Start a wander behavior for a ped
local function StartWanderBehavior(dbId, ped, originX, originY, originZ, radius)
    if PatrolThreads[dbId] then return end
    NextBehaviorToken = NextBehaviorToken + 1
    local myToken = NextBehaviorToken
    PatrolThreads[dbId] = myToken

    CreateThread(function()
        while PatrolThreads[dbId] == myToken and DoesEntityExist(ped) do
            -- Pick random point within radius
            local angle = math.random() * 2 * math.pi
            local dist  = math.random() * radius
            local tx = originX + math.cos(angle) * dist
            local ty = originY + math.sin(angle) * dist

            TaskGoStraightToCoord(ped, tx, ty, originZ, Config.DefaultPatrolSpeed, -1, 0.0, 0.0)

            -- Wait until ped arrives or timeout
            local waitTime = 0
            while PatrolThreads[dbId] == myToken and DoesEntityExist(ped) and waitTime < 30000 do
                local pedCoords = GetEntityCoords(ped)
                if #(pedCoords - vector3(tx, ty, originZ)) < 2.0 then break end
                Wait(500)
                waitTime = waitTime + 500
            end

            if PatrolThreads[dbId] ~= myToken or not DoesEntityExist(ped) then break end

            -- Wait at destination
            local idleTime = math.random(Config.WanderMinWait, Config.WanderMaxWait) * 1000
            Wait(idleTime)
        end
    end)
end

--- Start a patrol route behavior
local function StartPatrolBehavior(dbId, ped, points, speed)
    if PatrolThreads[dbId] then return end
    if not points or #points < 2 then return end
    NextBehaviorToken = NextBehaviorToken + 1
    local myToken = NextBehaviorToken
    PatrolThreads[dbId] = myToken

    CreateThread(function()
        local idx = 1
        while PatrolThreads[dbId] == myToken and DoesEntityExist(ped) do
            local pt = points[idx]
            TaskGoStraightToCoord(ped, pt.x, pt.y, pt.z, speed or 1.0, -1, 0.0, 0.0)

            local waitTime = 0
            while PatrolThreads[dbId] == myToken and DoesEntityExist(ped) and waitTime < 60000 do
                local pedCoords = GetEntityCoords(ped)
                if #(pedCoords - vector3(pt.x, pt.y, pt.z)) < 2.0 then break end
                Wait(500)
                waitTime = waitTime + 500
            end

            if PatrolThreads[dbId] ~= myToken or not DoesEntityExist(ped) then break end

            -- Pause at waypoint
            Wait(math.random(2000, 5000))

            idx = idx + 1
            if idx > #points then idx = 1 end
        end
    end)
end

--- Start an interact behavior (face a nearby ped and play scenario)
local function StartInteractBehavior(dbId, ped, interactType, originX, originY, originZ)
    if PatrolThreads[dbId] then return end
    NextBehaviorToken = NextBehaviorToken + 1
    local myToken = NextBehaviorToken
    PatrolThreads[dbId] = myToken

    -- Find scenario for this interaction type
    local interactScenario = 'WORLD_HUMAN_STAND_IMPATIENT'
    for _, ia in ipairs(Config.Interactions) do
        if ia.label == interactType or ia.scenario == interactType then
            interactScenario = ia.scenario
            break
        end
    end

    CreateThread(function()
        Wait(2000) -- let other peds spawn first

        while PatrolThreads[dbId] == myToken and DoesEntityExist(ped) do
            -- Find nearest other placed ped
            local nearestPed = nil
            local nearestDist = 999.0
            local myCoords = GetEntityCoords(ped)

            for otherId, otherEntry in pairs(SpawnedPeds) do
                if otherId ~= dbId and DoesEntityExist(otherEntry.handle) then
                    local otherCoords = GetEntityCoords(otherEntry.handle)
                    local d = #(myCoords - otherCoords)
                    if d < nearestDist and d < 10.0 then
                        nearestDist = d
                        nearestPed = otherEntry.handle
                    end
                end
            end

            if nearestPed and DoesEntityExist(nearestPed) then
                -- Face the other ped
                local otherCoords = GetEntityCoords(nearestPed)
                local headingTo = math.deg(math.atan(otherCoords.y - myCoords.y, otherCoords.x - myCoords.x)) - 90.0
                SetEntityHeading(ped, headingTo)

                -- Play interaction scenario
                TaskStartScenarioInPlace(ped, interactScenario, 0, true)
                Wait(math.random(15000, 30000))

                -- Briefly stop and restart
                ClearPedTasks(ped)
                Wait(math.random(3000, 6000))
            else
                -- No partner found, idle
                TaskStartScenarioInPlace(ped, interactScenario, 0, true)
                Wait(15000)
                ClearPedTasks(ped)
                Wait(5000)
            end
        end
    end)
end

--- Keep a TaskPlayAnim-based "scenario" alive.
--- Unlike real GTA scenarios (TaskStartScenarioInPlace), which the ped's
--- scenario brain self-maintains, a one-shot TaskPlayAnim is routinely cleared
--- by the ped's ambient brain — so placed anim-peds (counting money, drug
--- handoff, stripper dances, weed/coke/meth ops) would play for a frame and
--- then silently revert to standing idle. This thread:
---   1. VALIDATES the dict — an invalid dict name never loads, so we log it
---      loudly (a bad dict in Config.Scenarios becomes visible in F8), and
---   2. VALIDATES the clip — a valid dict with a wrong clip loads fine but
---      TaskPlayAnim then silently does nothing, so we check IsEntityPlayingAnim
---      after the first attempt and warn once if the clip never starts, and
---   3. re-applies the loop whenever the ped falls out of it.
--- Where a ped row says the ped belongs. Heading is normalized because some rows
--- were saved past 360 (the placement rotate loop doesn't wrap in every path).
local function PedAnchor(d)
    return {
        x = d.x, y = d.y, z = d.z,
        heading = (d.heading or 0.0) % 360.0,
    }
end

--- `anchor` ({x,y,z,heading}) is where the ped was placed. TaskPlayAnim applies
--- the clip's root motion to the entity, so a looping clip nudges/rotates the ped
--- a little on every pass and over a session that adds up to a ped standing in the
--- wrong spot facing the wrong way. Pass it and the loop pulls the ped back.
local function StartAnimLoop(dbId, ped, dict, name, anchor)
    if PatrolThreads[dbId] then return end
    NextBehaviorToken = NextBehaviorToken + 1
    local myToken = NextBehaviorToken
    PatrolThreads[dbId] = myToken

    CreateThread(function()
        RequestAnimDict(dict)
        local waited = 0
        while not HasAnimDictLoaded(dict) and waited < 3000 do
            Wait(50)
            waited = waited + 50
        end
        if not HasAnimDictLoaded(dict) then
            print(('^1[qb-pedplacer]^0 Ped #%s: anim DICTIONARY "%s" is invalid (does not exist in-game) — the ped will stand idle. Fix the dict in Config.Scenarios.')
                :format(tostring(dbId), tostring(dict)))
            if PatrolThreads[dbId] == myToken then PatrolThreads[dbId] = nil end
            return
        end

        -- Stop the ambient brain from fighting the anim, then keep it looping.
        SetBlockingOfNonTemporaryEvents(ped, true)
        local warnedBadClip = false
        local tick = 0
        while PatrolThreads[dbId] == myToken and DoesEntityExist(ped) do
            -- Anim keep-alive, still on a 2s cadence (every 4th 500ms tick).
            if tick % 4 == 0 and not IsEntityPlayingAnim(ped, dict, name, 3) then
                TaskPlayAnim(ped, dict, name, 8.0, -8.0, -1, 1, 0.0, false, false, false)
                -- Dict loaded but clip refused to start => clip name is wrong.
                if not warnedBadClip then
                    warnedBadClip = true
                    Wait(300)
                    if DoesEntityExist(ped) and not IsEntityPlayingAnim(ped, dict, name, 3) then
                        print(('^1[qb-pedplacer]^0 Ped #%s: dict "%s" loaded but clip "%s" will not play — the CLIP name is wrong. Fix it in Config.Scenarios.')
                            :format(tostring(dbId), tostring(dict), tostring(name)))
                    end
                end
            end

            -- Root-motion drift correction. Only correct once the ped has actually
            -- moved, so clips that behave never visibly snap. (TaskPlayAnimAdvanced
            -- would pin the ped outright, but these clips are authored around a
            -- scene origin and it would displace the ped by that offset.)
            if anchor then
                local c = GetEntityCoords(ped)
                if #(c - vector3(anchor.x, anchor.y, anchor.z)) > 0.35 then
                    SetEntityCoords(ped, anchor.x, anchor.y, anchor.z, false, false, false, false)
                end
                -- Shortest signed angle between the two headings, in [-180, 180).
                local drift = math.abs((GetEntityHeading(ped) - anchor.heading + 180.0) % 360.0 - 180.0)
                if drift > 3.0 then
                    SetEntityHeading(ped, anchor.heading)
                end
            end

            tick = tick + 1
            Wait(500)
        end

        RemoveAnimDict(dict)
    end)
end

--- Is this row a ped SITTING via a real GTA scenario (not an anim clip)?
--- Seated scenarios are placed by TaskStartScenarioAtPosition, which owns both
--- the position AND the heading — see StartSeatLoop for why that matters.
local function IsSeatedScenario(d, animDict)
    return (d.behavior or 'idle') == 'scenario'
        and (animDict == nil or animDict == '')
        and d.scenario and d.scenario ~= ''
        and d.scenario:find('SEAT') ~= nil
end

--- Keep a SEATED scenario ped parked in its chair, facing the way it was placed.
---
--- TaskStartScenarioAtPosition does not sit the ped ON the coords you hand it:
--- the seat clip carries its own root offset and alignment, so the game settles
--- the entity at a fixed offset from the scenario point and turns it to suit the
--- clip. That is fine — the ped looks right — but it means the entity heading the
--- ped ends up holding is NOT the heading in the database row.
---
--- The old code then re-asserted the row's heading with SetEntityHeading (the
--- generic fix for standing peds). On a seated ped that rotates the entity about
--- its origin while the body sits offset from it, so the ped swung sideways out
--- of the chair and ended up facing the wrong way on every respawn — the "ped
--- drifts left and won't sit forward after a restart" bug.
---
--- So: let the scenario own the pose, and correct only REAL drift. We let the
--- sit settle, record the pose the game chose, and from then on pull the ped back
--- by re-issuing the scenario AT THE ROW'S ANCHOR (never at the ped's current
--- coords, so nothing can accumulate across respawns).
local function StartSeatLoop(dbId, ped, scenario, anchor)
    local function applyScenario()
        -- z - 1.0: the sit pose anchors the pelvis ~1m above the ped's root, so a
        -- ped placed with feet on the seat would otherwise float above it.
        TaskStartScenarioAtPosition(ped, scenario,
            anchor.x, anchor.y, anchor.z - 1.0,
            anchor.heading, 0, true, true)
    end

    -- Sit down FIRST, unconditionally — the keep-alive below is maintenance, so a
    -- stale thread token must never be able to leave the ped standing up.
    applyScenario()

    if PatrolThreads[dbId] then return end
    NextBehaviorToken = NextBehaviorToken + 1
    local myToken = NextBehaviorToken
    PatrolThreads[dbId] = myToken

    CreateThread(function()
        -- Let the enter anim finish before reading the pose it settled into.
        Wait(1500)
        if PatrolThreads[dbId] ~= myToken or not DoesEntityExist(ped) then return end

        local settled = GetEntityCoords(ped)
        local settledHeading = GetEntityHeading(ped)

        while PatrolThreads[dbId] == myToken and DoesEntityExist(ped) do
            Wait(1000)
            if PatrolThreads[dbId] ~= myToken or not DoesEntityExist(ped) then break end

            local drifted = #(GetEntityCoords(ped) - settled) > 0.35
            local turned  = math.abs((GetEntityHeading(ped) - settledHeading + 180.0) % 360.0 - 180.0) > 5.0

            -- Re-seat if it wandered, got turned, or the brain dropped the scenario.
            if drifted or turned or not IsPedUsingScenario(ped, scenario) then
                applyScenario()
                Wait(1500)
                if PatrolThreads[dbId] ~= myToken or not DoesEntityExist(ped) then break end
                settled = GetEntityCoords(ped)
                settledHeading = GetEntityHeading(ped)
            end
        end
    end)
end

--- Stop any active behavior thread for a ped
local function StopBehavior(dbId)
    PatrolThreads[dbId] = nil
end

-- ═══════════════════════════════════════════════════════════
--  HOME CONTROL BRIDGE HELPERS (rr-homecontrol)
--  Lets a home control panel drive already-placed peds in an area:
--  party = dance loops, chill = restore placed behavior, away =
--  walk out and stay despawned until brought back.
-- ═══════════════════════════════════════════════════════════

--- Is this ped row inside the area and not excluded from control?
local function PedMatchesArea(d, area)
    local dx, dy = d.x - area.x, d.y - area.y
    if (dx * dx + dy * dy) > (area.r * area.r) then return false end
    for _, b in ipairs(area.excludeBehaviors or {}) do
        if (d.behavior or 'idle') == b then return false end
    end
    for _, m in ipairs(area.excludeModels or {}) do
        if d.model == m then return false end
    end
    return true
end

--- First active party area this ped row falls in (nil if none)
local function PedPartyArea(d)
    for _, area in pairs(PartyAreas) do
        if PedMatchesArea(d, area) then return area end
    end
    return nil
end

--- Put one spawned ped into party mode: back to its placed spot, then a
--- dance loop kept alive by StartAnimLoop. Anim choice is dbId-stable so
--- each guest keeps their dance across respawns but the crowd is varied.
local function ApplyPartyAnim(dbId, ped, d, area)
    local anims = area.anims
    if not anims or #anims == 0 then return end
    local a = anims[(dbId % #anims) + 1]
    StopBehavior(dbId)
    ClearPedTasksImmediately(ped)
    SetEntityCoords(ped, d.x, d.y, d.z, false, false, false, false)
    SetEntityHeading(ped, d.heading or 0.0)
    StartAnimLoop(dbId, ped, a.dict, a.anim, PedAnchor(d))
end

-- ═══════════════════════════════════════════════════════════
--  SCULLY EMOTE MENU BRIDGE
--  Pull scully_emotemenu's emote library so a placed ped can use ANY emote
--  (dances, prop emotes, etc.) as a looping "scenario". An emote is just an
--  anim dict + clip (+ optional held props), which maps straight onto the
--  placer's existing anim_dict/anim_name + StartAnimLoop engine. The library
--  is read at runtime from scully's shared files (declared in its files{}),
--  so it always reflects whatever emotes scully currently ships — no copy to
--  keep in sync. Synchronized emotes are intentionally skipped (they need a
--  second live player and can't run on a static ped).
-- ═══════════════════════════════════════════════════════════
local EMOTE_RESOURCE = 'scully_emotemenu'
local EMOTE_FILES = {
    { key = 'general',    file = 'general_emotes',    icon = '🙂' },
    { key = 'prop',       file = 'prop_emotes',       icon = '📦' },
    { key = 'consumable', file = 'consumable_emotes', icon = '🍔' },
    { key = 'dance',      file = 'dance_emotes',       icon = '💃' },
    { key = 'animal',     file = 'animal_emotes',      icon = '🐾' },
}
EmoteCategories = nil   -- lazy-loaded: { { key, icon, name, options = {...} }, ... }
EmoteByCommand  = nil   -- [command] = emote table

local function EmotesAvailable()
    return GetResourceState(EMOTE_RESOURCE) == 'started'
end

--- Read + cache scully's emote tables. Returns true if at least one loaded.
function LoadEmoteLibrary()
    if EmoteCategories then return #EmoteCategories > 0 end
    if not EmotesAvailable() then return false end

    EmoteCategories = {}
    EmoteByCommand = {}
    for _, cat in ipairs(EMOTE_FILES) do
        local path = ('shared/data/emotes/%s.lua'):format(cat.file)
        local content = LoadResourceFile(EMOTE_RESOURCE, path)
        if content and content ~= '' then
            -- Emote files are plain `return { ... }`; vec3() inside them resolves
            -- against FiveM's global env, so the default chunk env is correct.
            local chunk = load(content, '@' .. EMOTE_RESOURCE .. '/' .. path)
            local ok, tbl = pcall(chunk)
            if ok and type(tbl) == 'table' and type(tbl.options) == 'table' then
                EmoteCategories[#EmoteCategories + 1] = {
                    key = cat.key, icon = cat.icon,
                    name = tbl.name or cat.file, options = tbl.options,
                }
                for _, e in ipairs(tbl.options) do
                    if e.Command then EmoteByCommand[e.Command] = e end
                end
            else
                print(('^3[qb-pedplacer]^0 Could not parse emote file %s'):format(path))
            end
        end
    end
    return #EmoteCategories > 0
end

local function Vec3ToTable(v)
    if not v then return { x = 0.0, y = 0.0, z = 0.0 } end
    return { x = (v.x or 0.0) + 0.0, y = (v.y or 0.0) + 0.0, z = (v.z or 0.0) + 0.0 }
end

--- Turn a scully emote entry into the concrete (dict, clip, propsList) a placed
--- ped needs. Random dict/clip pools are resolved ONCE here so the ped's pose is
--- deterministic for the rest of its life.
function ResolveEmote(emote)
    local dict, anim = emote.Dictionary, emote.Animation
    if type(dict) == 'table' and type(anim) == 'table' then
        local i = math.random(1, #anim)
        dict, anim = dict[i], anim[i]
    end

    local props = {}
    local opt = emote.Options
    if opt and opt.Props then
        for _, p in ipairs(opt.Props) do
            local placement = p.Placement
            props[#props + 1] = {
                name    = p.Name,
                bone    = p.Bone or 60309,
                pos     = Vec3ToTable(placement and placement[1]),
                rot     = Vec3ToTable(placement and placement[2]),
                variant = p.Variant,
            }
        end
    end
    return dict, anim, props
end

-- ═══════════════════════════════════════════════════════════
--  EMOTE PROP ATTACH / DETACH  (held items for prop/consumable emotes)
-- ═══════════════════════════════════════════════════════════

--- Spawn + bone-attach the held props of an emote-based scenario ped.
--- Returns a list of object handles (stored on the SpawnedPeds entry) or nil.
local function AttachEmoteProps(ped, data)
    if (data.behavior or 'idle') ~= 'scenario' then return nil end

    local list = data.emote_props
    if type(list) == 'string' then
        if list == '' then return nil end
        local ok, decoded = pcall(json.decode, list)
        list = ok and decoded or nil
    end
    if type(list) ~= 'table' or #list == 0 then return nil end

    local objs = {}
    for _, p in ipairs(list) do
        local hash = LoadModel(p.name)
        if hash then
            local c = GetEntityCoords(ped)
            local obj = CreateObject(hash, c.x, c.y, c.z, false, false, false)
            SetModelAsNoLongerNeeded(hash)
            if DoesEntityExist(obj) then
                SetEntityCollision(obj, false, false)
                if p.variant then SetObjectTextureVariation(obj, p.variant) end
                local boneIdx = GetPedBoneIndex(ped, p.bone or 60309)
                local pos, rot = p.pos or {}, p.rot or {}
                AttachEntityToEntity(obj, ped, boneIdx,
                    (pos.x or 0.0) + 0.0, (pos.y or 0.0) + 0.0, (pos.z or 0.0) + 0.0,
                    (rot.x or 0.0) + 0.0, (rot.y or 0.0) + 0.0, (rot.z or 0.0) + 0.0,
                    true, true, false, true, 1, true)
                objs[#objs + 1] = obj
            end
        end
    end
    return #objs > 0 and objs or nil
end

--- Delete a ped's attached emote props (called on despawn / cull / wipe).
local function DeleteEmoteProps(props)
    if not props then return end
    for _, obj in ipairs(props) do
        if DoesEntityExist(obj) then
            SetEntityAsMissionEntity(obj, true, true)
            DeleteObject(obj)
        end
    end
end

-- ═══════════════════════════════════════════════════════════
--  PED SPAWNING
-- ═══════════════════════════════════════════════════════════

-- Apply the static, always-on flags a placed ped needs: heading, invincibility,
-- combat/ragdoll behavior and weapon. Kept separate from StartBehavior (freeze
-- state + scenario/movement) purely to keep SpawnPed readable.
local function ApplyBaseFlags(ped, data)
    if not DoesEntityExist(ped) then return end

    SetEntityHeading(ped, data.heading or 0.0)

    local invincible = data.invincible
    if invincible == nil then invincible = Config.Invincible end
    SetEntityInvincible(ped, invincible)

    SetPedFleeAttributes(ped, 0, false)
    SetPedCombatAttributes(ped, 46, true)
    SetPedCombatAttributes(ped, 17, true)
    SetPedCanRagdollFromPlayerImpact(ped, false)
    SetPedDiesWhenInjured(ped, false)
    SetPedConfigFlag(ped, 32, false)
    SetPedConfigFlag(ped, 36, false)

    -- Weapon
    if data.weapon and data.weapon ~= '' then
        local weaponHash = joaat(data.weapon)
        GiveWeaponToPed(ped, weaponHash, 999, false, true)
        SetCurrentPedWeapon(ped, weaponHash, true)
    end
end

-- Attach the rr-bartender "Order a drink" interaction to a bartender ped.
-- Guarded so qb-pedplacer still works if rr-bartender isn't installed/running.
local BartenderWarned = false
local function AttachBartenderTarget(ped)
    if GetResourceState('rr-bartender') ~= 'started' then
        if not BartenderWarned then
            BartenderWarned = true
            print('^3[qb-pedplacer]^0 Bartender ped placed but rr-bartender is not started — drink ordering disabled until it is.')
        end
        return
    end
    exports['rr-bartender']:AddBartenderTarget(ped)
end

--- Pin a ped at its placed coords until the map underneath it has streamed in,
--- then hand it back to gravity.
---
--- Peds spawn at Config.RenderDistance (100m), and at that range the collision
--- under the spawn point is not always loaded yet — an offshore island is the
--- worst case, because the only thing loaded out there is open sea. An unfrozen
--- ped dropped into that gap falls through, lands in the water and swims away.
--- Its handle stays perfectly valid, so StreamPeds still believes the ped is
--- alive and never rebuilds it: the party is simply gone until the resource is
--- restarted. Holding the ped still until collision exists removes the fall.
local function HoldUntilGrounded(ped, data)
    CreateThread(function()
        local waited = 0
        RequestCollisionAtCoord(data.x, data.y, data.z)
        while waited < 15000 do
            if not DoesEntityExist(ped) then return end
            if HasCollisionLoadedAroundEntity(ped) then break end
            RequestCollisionAtCoord(data.x, data.y, data.z)
            Wait(100)
            waited = waited + 100
        end
        if not DoesEntityExist(ped) then return end
        -- Re-assert the row before releasing: whatever nudged the ped while it
        -- was pinned (a scenario enter anim, an MLO popping in) must not become
        -- the position it falls from. Seated scenarios are left alone — the game
        -- settles those at its own offset from the row and StartSeatLoop owns it.
        if not IsSeatedScenario(data, data.anim_dict or data.animDict or '') then
            local c = GetEntityCoords(ped)
            if #(c - vector3(data.x, data.y, data.z)) > 0.5 then
                SetEntityCoords(ped, data.x, data.y, data.z, false, false, false, false)
            end
        end
        FreezeEntityPosition(ped, false)
    end)
end

-- Bring a ped "to life": set its freeze state, start its scenario/animation and
-- kick off any active behavior thread (wander/patrol/interact/bartender).
-- Called from SpawnPed once the entity exists.
local function StartBehavior(ped, data)
    if not DoesEntityExist(ped) then return end
    local dbId    = data.id
    local behavior = data.behavior or 'idle'

    -- Only freeze idle peds. Scenario/wander/patrol/interact/bartender peds must
    -- be unfrozen so gravity settles them and prop-based scenarios attach — but
    -- only once there is ground under them to settle ONTO, so the unfreeze is
    -- deferred until collision has loaded (see HoldUntilGrounded).
    if behavior == 'idle' then
        local frozen = data.frozen
        if frozen == nil then frozen = Config.Frozen end
        FreezeEntityPosition(ped, frozen)
    else
        FreezeEntityPosition(ped, true)
        HoldUntilGrounded(ped, data)
    end

    local animDict = data.animDict or data.anim_dict or ''
    local animName = data.animName or data.anim_name or ''
    if behavior == 'scenario' then
        if animDict ~= '' and animName ~= '' then
            -- Animation-clip "scenario" (stripper dances, drug ops, counting
            -- money, handoffs). Driven by a self-healing keep-alive thread so it
            -- doesn't get cleared by the ambient brain and revert to idle.
            StartAnimLoop(dbId, ped, animDict, animName, PedAnchor(data))
        elseif data.scenario and data.scenario ~= '' then
            -- Make sure the ped can play ambient anims (required for prop scenarios)
            SetPedCanPlayAmbientAnims(ped, true)
            SetPedCanPlayAmbientBaseAnims(ped, true)
            ClearPedTasksImmediately(ped)

            if data.scenario:find('SEAT') then
                -- Seated: StartSeatLoop applies the scenario and keeps the ped
                -- in the chair. It owns both position and heading — see the
                -- comment on StartSeatLoop for why this must not be re-headed.
                StartSeatLoop(dbId, ped, data.scenario, PedAnchor(data))
            else
                TaskStartScenarioInPlace(ped, data.scenario, 0, true)
            end
        end
    elseif behavior == 'bartender' then
        -- Stand attentively behind the bar; the "Order a drink" target is
        -- attached below once the scenario is running.
        SetPedCanPlayAmbientAnims(ped, true)
        SetPedCanPlayAmbientBaseAnims(ped, true)
        ClearPedTasksImmediately(ped)
        local barScenario = (data.scenario and data.scenario ~= '') and data.scenario or 'WORLD_HUMAN_STAND_IMPATIENT'
        TaskStartScenarioInPlace(ped, barScenario, 0, true)
    end

    -- Re-assert the placed heading AFTER the task has started. ApplyBaseFlags set
    -- it before we ran, but ClearPedTasksImmediately and the scenario's enter anim
    -- both turn the ped, so the heading applied at creation is not the one it ends
    -- up holding — that's why a ped can spawn facing the wrong way even though the
    -- database row is correct. Stationary behaviors only; wander/patrol are meant
    -- to turn. Two passes: once the enter anim is under way, once after it settles.
    -- SEATED scenario peds are excluded: TaskStartScenarioAtPosition already set
    -- their pose, and forcing the row's heading on top of it rotates the ped out
    -- of the chair (see StartSeatLoop). StartSeatLoop maintains those instead.
    if (behavior == 'idle' or behavior == 'scenario' or behavior == 'bartender')
        and not IsSeatedScenario(data, animDict) then
        local placedHeading = (data.heading or 0.0) % 360.0
        for _, delay in ipairs({ 500, 2000 }) do
            Citizen.SetTimeout(delay, function()
                if DoesEntityExist(ped) then
                    SetEntityHeading(ped, placedHeading)
                end
            end)
        end
    end

    -- Block fleeing/reaction events AFTER the scenario task has started, so the
    -- scenario's internal prop-spawn event isn't suppressed.
    if Config.BlockEvents and (behavior == 'idle' or behavior == 'scenario' or behavior == 'bartender') then
        Citizen.SetTimeout(500, function()
            if DoesEntityExist(ped) then
                SetBlockingOfNonTemporaryEvents(ped, true)
            end
        end)
    else
        SetBlockingOfNonTemporaryEvents(ped, false)
    end

    -- Active behaviors (movement threads)
    if behavior == 'wander' then
        StartWanderBehavior(dbId, ped, data.x, data.y, data.z, data.wander_radius or Config.DefaultWanderRadius)
    elseif behavior == 'patrol' then
        local points = data.patrol_points
        if type(points) == 'string' then
            points = json.decode(points)
        end
        if points and #points >= 2 then
            StartPatrolBehavior(dbId, ped, points, data.patrol_speed or Config.DefaultPatrolSpeed)
        else
            -- No patrol points yet, wander as fallback
            StartWanderBehavior(dbId, ped, data.x, data.y, data.z, 10.0)
        end
    elseif behavior == 'interact' then
        StartInteractBehavior(dbId, ped, data.interact_type or '', data.x, data.y, data.z)
    elseif behavior == 'bartender' then
        AttachBartenderTarget(ped)
    end
end

-- Create the ped entity and bring it to life. Only ever called when the player
-- is within range, so the world/collision around the spawn point is loaded.
local function SpawnPed(data)
    if SpawnedPeds[data.id] then return end
    if FailedPeds[data.id] then return end

    -- Reject invalid models up front. The streaming loop calls SpawnPed every
    -- Config.StreamCheckInterval while the player is in range, so without this an
    -- invalid model would print "Failed to load" every cycle forever. Log once,
    -- flag the ped, and never retry it this session.
    local modelHash = type(data.model) == 'number' and data.model or joaat(data.model)
    if not IsModelValid(modelHash) then
        FailedPeds[data.id] = true
        print(('^1[qb-pedplacer]^0 Invalid model "%s" for ped #%s — skipping (fix or delete it via /%s)')
            :format(tostring(data.model), tostring(data.id), Config.Command))
        return
    end

    local hash = LoadModel(data.model)
    if not hash then
        -- Transient load failure (e.g. streaming pressure). Don't flag/spam —
        -- the next streaming pass will retry the (valid) model.
        return
    end

    -- Ask for the world around the spawn point up front. Free if it's already
    -- streamed, and it gives HoldUntilGrounded a head start when it isn't.
    RequestCollisionAtCoord(data.x, data.y, data.z)

    local ped = CreatePed(4, hash, data.x, data.y, data.z, data.heading or 0.0, false, true)
    SetModelAsNoLongerNeeded(hash)
    if not DoesEntityExist(ped) then return end

    ApplyAddonPedVariation(ped, data.model)
    SetEntityAsMissionEntity(ped, true, true)

    -- Place ped at exact stored coordinates — the Z is already correct from when it was saved.
    -- DO NOT use PlaceObjectOnGroundProperly here: it snaps to outdoor terrain under MLO floors.
    SetEntityCoords(ped, data.x, data.y, data.z, false, false, false, false)

    ApplyBaseFlags(ped, data)
    StartBehavior(ped, data)

    -- Attach any held emote props (beer/cigar/clipboard/etc.) and keep their
    -- handles so they're cleaned up when the ped despawns or is culled.
    local props = AttachEmoteProps(ped, data)

    SpawnedPeds[data.id] = { handle = ped, data = data, props = props }

    -- Home Control: if this ped streams in while its home is partying,
    -- swap the placed behavior for a dance loop.
    local pa = PedPartyArea(data)
    if pa and pa.mode == 'party' then
        ApplyPartyAnim(data.id, ped, data, pa)
    end
end

local function DespawnPed(dbId)
    StopBehavior(dbId)
    local entry = SpawnedPeds[dbId]
    if entry then
        DeleteEmoteProps(entry.props)
        if DoesEntityExist(entry.handle) then
            if entry.data and entry.data.behavior == 'bartender' and GetResourceState('rr-bartender') == 'started' then
                exports['rr-bartender']:RemoveBartenderTarget(entry.handle)
            end
            DeletePed(entry.handle)
        end
    end
    SpawnedPeds[dbId] = nil
    HeldPeds[dbId]    = nil   -- a hold dies with the entity it was holding
end

local function DespawnAllPeds()
    for id, _ in pairs(SpawnedPeds) do
        StopBehavior(id)
    end
    for _, entry in pairs(SpawnedPeds) do
        DeleteEmoteProps(entry.props)
        if DoesEntityExist(entry.handle) then
            DeletePed(entry.handle)
        end
    end
    SpawnedPeds = {}
    FailedPeds = {}
    HealTries = {}
    HealNextAt = {}
    HeldPeds = {}
end

-- ═══════════════════════════════════════════════════════════
--  STREAMING
-- ═══════════════════════════════════════════════════════════

-- Behaviors whose ped is meant to stay on its placed spot, so leaving that spot
-- means something went wrong. wander/patrol/interact are excluded — moving is
-- their whole job.
local StationaryBehavior = { idle = true, scenario = true, bartender = true }

local function StreamPeds()
    local playerCoords = GetEntityCoords(PlayerPedId())
    for _, data in ipairs(AllPedData) do
        local entry = SpawnedPeds[data.id]

        -- The engine can quietly cull a ped (interior transitions, ped-pool
        -- pressure, MLO load) while our table still believes it's alive — that's
        -- the classic "peds vanished, had to restart the resource" bug. Detect
        -- the dead handle and clear it so the logic below recreates the ped.
        if entry and not DoesEntityExist(entry.handle) then
            StopBehavior(data.id)
            DeleteEmoteProps(entry.props)
            SpawnedPeds[data.id] = nil
            entry = nil
        end

        -- Claimed by another resource (rr-girlfriend walked off with this ped):
        -- the claimer owns the entity now. The entry-despawn only fires on the
        -- login race where our copy streamed in before the claim arrived.
        if ClaimedPeds[data.id] then
            if entry then DespawnPed(data.id) end
            goto continue
        end

        -- Hidden group (e.g. a closed business): keep it despawned regardless of
        -- distance, and remove it if it's currently spawned.
        if data.group_name and data.group_name ~= '' and HiddenGroups[data.group_name] then
            if entry then DespawnPed(data.id) end
            goto continue
        end

        -- Hidden area (e.g. a closed venue): same, by 2D distance from a point.
        for _, a in pairs(HiddenAreas) do
            local dx, dy = data.x - a.x, data.y - a.y
            if (dx * dx + dy * dy) <= (a.r * a.r) then
                if entry then DespawnPed(data.id) end
                goto continue
            end
        end

        -- Home Control: guests sent home → never respawn, and cull any
        -- straggler once the walk-out grace period has passed.
        local pa = PedPartyArea(data)
        if pa and pa.mode == 'away' then
            if entry and GetGameTimer() >= (pa.graceUntil or 0) then DespawnPed(data.id) end
            goto continue
        end

        -- A ped that is supposed to stand still has left its spot. The engine
        -- doesn't tell us — the handle is still valid — so without this the ped
        -- is "gone" for the rest of the session no matter how many times you
        -- walk back: the streamer sees a live entry and skips it. Snap small
        -- strays back, and rebuild anything that has fallen through the world or
        -- drifted out to sea (the offshore-island failure, see HoldUntilGrounded).
        -- Skipped while another resource holds the ped (HoldPed): a gang ped
        -- chasing a rival 20 m down the block is not a stray.
        if entry and StationaryBehavior[data.behavior or 'idle'] and not HeldPeds[data.id] then
            local c = GetEntityCoords(entry.handle)
            local stray = #(c - vector3(data.x, data.y, data.z))
            -- Note the swim test is paired with a stray check: a ped deliberately
            -- placed in the water is fine where it is, it just must not have
            -- swum off. Without that pairing this would rebuild it every tick.
            if stray > 25.0 or (data.z - c.z) > 5.0 or (IsPedSwimming(entry.handle) and stray > 3.0) then
                -- Rate-limited, and given up on after a few goes, so a row whose
                -- z is genuinely wrong can never turn into a ped that pops in and
                -- falls out of the world once a second forever.
                local tries = HealTries[data.id] or 0
                if tries < 3 and GetGameTimer() >= (HealNextAt[data.id] or 0) then
                    HealTries[data.id] = tries + 1
                    HealNextAt[data.id] = GetGameTimer() + 15000
                    DespawnPed(data.id)
                    entry = nil
                elseif tries == 3 then
                    HealTries[data.id] = 4
                    print(('^3[qb-pedplacer]^0 Ped #%s will not stay on its placed spot (row z may be wrong) — leaving it alone. Re-place it with /%s.')
                        :format(tostring(data.id), Config.Command))
                end
            elseif stray > 3.0 and not IsSeatedScenario(data, data.anim_dict or data.animDict or '') then
                StopBehavior(data.id)
                ClearPedTasksImmediately(entry.handle)
                SetEntityCoords(entry.handle, data.x, data.y, data.z, false, false, false, false)
                SetEntityHeading(entry.handle, (data.heading or 0.0) % 360.0)
                if pa and pa.mode == 'party' then
                    ApplyPartyAnim(data.id, entry.handle, data, pa)
                else
                    StartBehavior(entry.handle, data)
                end
            end
        end

        local dist = #(playerCoords - vector3(data.x, data.y, data.z))
        local near = dist <= Config.RenderDistance

        if Config.PermanentPeds then
            -- Permanent: spawn the FIRST time you come within range (so the ped
            -- is created where the world/collision is loaded, never in an
            -- unstreamed area), then keep it loaded forever — it is never
            -- despawned by distance. Combined with the cull-detection above,
            -- this means once you've been to an MLO its peds stay put and
            -- self-heal if the engine ever removes them, with no resource reset.
            if near and not entry then
                if not FailedPeds[data.id] then SpawnPed(data) end
            end
        else
            -- Streaming: spawn within range, despawn beyond it.
            if near then
                if not entry then SpawnPed(data) end
            else
                if entry then DespawnPed(data.id) end
            end
        end

        ::continue::
    end
end

-- ═══════════════════════════════════════════════════════════
--  RADIO SPAWNING (speaker prop only — audio via mobile radio zone)
-- ═══════════════════════════════════════════════════════════

local activeRadioZone = nil   -- db id of the radio zone the player is currently inside

local function SpawnRadio(data)
    if SpawnedRadios[data.id] then return end

    -- Spawn speaker prop (visual only)
    local propHash = LoadModel(data.model)
    if not propHash then
        print('^1[qb-pedplacer]^0 Failed to load speaker: ' .. tostring(data.model))
        return
    end

    local prop = CreateObject(propHash, data.x, data.y, data.z, false, false, false)
    SetModelAsNoLongerNeeded(propHash)
    if not DoesEntityExist(prop) then return end

    SetEntityAsMissionEntity(prop, true, true)
    PlaceObjectOnGroundProperly(prop)
    SetEntityHeading(prop, data.heading or 0.0)
    FreezeEntityPosition(prop, true)
    SetEntityInvincible(prop, true)

    SpawnedRadios[data.id] = { prop = prop, data = data }
end

local function DespawnRadio(radioId)
    local entry = SpawnedRadios[radioId]
    if entry then
        if entry.prop and DoesEntityExist(entry.prop) then
            SetEntityAsMissionEntity(entry.prop, true, true)
            DeleteObject(entry.prop)
        end
        SpawnedRadios[radioId] = nil
    end
    -- If this was the active radio zone, turn off radio
    if activeRadioZone == radioId then
        SetMobileRadioEnabledDuringGameplay(false)
        SetMobilePhoneRadioState(false)
        SetUserRadioControlEnabled(true)
        SetRadioToStationName('OFF')
        activeRadioZone = nil
    end
end

local function DespawnAllRadios()
    for id, _ in pairs(SpawnedRadios) do
        if SpawnedRadios[id] and SpawnedRadios[id].prop and DoesEntityExist(SpawnedRadios[id].prop) then
            SetEntityAsMissionEntity(SpawnedRadios[id].prop, true, true)
            DeleteObject(SpawnedRadios[id].prop)
        end
    end
    SpawnedRadios = {}
    if activeRadioZone then
        SetMobileRadioEnabledDuringGameplay(false)
        SetMobilePhoneRadioState(false)
        SetUserRadioControlEnabled(true)
        SetRadioToStationName('OFF')
        activeRadioZone = nil
    end
end

local function StreamRadios()
    if #AllRadioData == 0 then return end
    local playerCoords = GetEntityCoords(PlayerPedId())
    local renderDist = Config.RadioRenderDistance or Config.RenderDistance
    for _, data in ipairs(AllRadioData) do
        local dist = #(playerCoords - vector3(data.x, data.y, data.z))
        if dist <= renderDist then
            if not SpawnedRadios[data.id] then SpawnRadio(data) end
        else
            if SpawnedRadios[data.id] then DespawnRadio(data.id) end
        end
    end
end

-- Radio zone loop — plays GTA radio when player is near a speaker
-- Uses mobile phone radio (same system GTA uses for strip club / nightclub)
CreateThread(function()
    while true do
        Wait(500)
        if not isLoggedIn or #AllRadioData == 0 then Wait(3000) goto radioSkip end

        local playerPos = GetEntityCoords(PlayerPedId())
        local closestId = nil
        local closestDist = 999.0

        for _, data in ipairs(AllRadioData) do
            -- Home Control: skip speakers inside an area whose music is off
            local muted = false
            for _, a in pairs(DisabledRadioAreas) do
                local dx, dy = data.x - a.x, data.y - a.y
                if (dx * dx + dy * dy) <= (a.r * a.r) then muted = true break end
            end
            if not muted then
                local radioPos = vector3(data.x, data.y, data.z)
                local dist = #(playerPos - radioPos)
                local range = Config.RadioRenderDistance or 25.0
                if dist < range and dist < closestDist then
                    closestDist = dist
                    closestId = data.id
                end
            end
        end

        if closestId then
            if activeRadioZone ~= closestId then
                -- Find the data for this radio
                local radioData
                for _, data in ipairs(AllRadioData) do
                    if data.id == closestId then radioData = data break end
                end
                if radioData then
                    activeRadioZone = closestId
                    SetRadioToStationName(radioData.station or 'RADIO_01_CLASS_ROCK')
                    SetMobileRadioEnabledDuringGameplay(true)
                    SetMobilePhoneRadioState(true)
                    SetUserRadioControlEnabled(false)
                    print('[qb-pedplacer] Radio zone entered: ' .. (radioData.label or 'Unknown'))
                end
            end
        else
            if activeRadioZone then
                SetMobileRadioEnabledDuringGameplay(false)
                SetMobilePhoneRadioState(false)
                SetUserRadioControlEnabled(true)
                SetRadioToStationName('OFF')
                activeRadioZone = nil
            end
        end

        ::radioSkip::
    end
end)

-- ═══════════════════════════════════════════════════════════
--  METAL DETECTOR SPAWNING + SCAN
--  Mirrors the radio pattern: stream the archway prop by distance, and
--  scan the LOCAL player — if they walk through armed, fire the alarm.
--  The prop model + beep both come from the "metal-detectors" resource:
--  the beep is broadcast through its shared `DetectorAlarm` event so other
--  nearby players hear it too. A local beep is used as a fallback if that
--  resource is stopped.
-- ═══════════════════════════════════════════════════════════

local function SpawnDetector(data)
    if SpawnedDetectors[data.id] then return end

    local propHash = LoadModel(Config.MetalDetector.model)
    if not propHash then
        print('^1[qb-pedplacer]^0 Failed to load metal-detector prop (' .. tostring(Config.MetalDetector.model) .. ') — is the metal-detectors resource started?')
        return
    end

    local prop = CreateObject(propHash, data.x, data.y, data.z, false, false, false)
    SetModelAsNoLongerNeeded(propHash)
    if not DoesEntityExist(prop) then return end

    SetEntityAsMissionEntity(prop, true, true)
    PlaceObjectOnGroundProperly(prop)
    SetEntityHeading(prop, data.heading or 0.0)
    FreezeEntityPosition(prop, true)
    SetEntityInvincible(prop, true)
    SetEntityCanBeDamaged(prop, false)

    SpawnedDetectors[data.id] = { prop = prop, data = data }
end

local function DespawnDetector(detectorId)
    local entry = SpawnedDetectors[detectorId]
    if entry then
        if entry.prop and DoesEntityExist(entry.prop) then
            SetEntityAsMissionEntity(entry.prop, true, true)
            DeleteObject(entry.prop)
        end
        SpawnedDetectors[detectorId] = nil
    end
    DetectorTriggered[detectorId] = nil
end

local function DespawnAllDetectors()
    for id, entry in pairs(SpawnedDetectors) do
        if entry.prop and DoesEntityExist(entry.prop) then
            SetEntityAsMissionEntity(entry.prop, true, true)
            DeleteObject(entry.prop)
        end
    end
    SpawnedDetectors = {}
    DetectorTriggered = {}
end

local function StreamDetectors()
    if #AllDetectorData == 0 then return end
    local playerCoords = GetEntityCoords(PlayerPedId())
    local renderDist = Config.MetalDetector.renderDist or Config.RenderDistance
    for _, data in ipairs(AllDetectorData) do
        local dist = #(playerCoords - vector3(data.x, data.y, data.z))
        if dist <= renderDist then
            if not SpawnedDetectors[data.id] then SpawnDetector(data) end
        else
            if SpawnedDetectors[data.id] then DespawnDetector(data.id) end
        end
    end
end

-- Local fallback beep (same sound/pattern as the metal-detectors resource)
local function DetectorBeepLocal(x, y, z, range)
    CreateThread(function()
        for i = 1, 6 do
            PlaySoundFromCoord(-1, 'Beep_Red', x, y, z, 'DLC_HEIST_HACKING_SNAKE_SOUNDS', false, range, false)
            Wait(130)
        end
    end)
end

-- Scan loop — fires the alarm once each time the local (armed) player enters
-- a detector's radius. Flag 7 = melee | gun | thrown weapons.
CreateThread(function()
    while true do
        Wait(200)
        if not isLoggedIn or #AllDetectorData == 0 then goto detectorSkip end

        local ped = PlayerPedId()
        local playerPos = GetEntityCoords(ped)
        local armed = IsPedArmed(ped, 7)

        for _, data in ipairs(AllDetectorData) do
            -- Horizontal distance + a vertical gate: a walk-through archway should
            -- trigger at floor level regardless of the prop's origin height, but
            -- not cross-trigger with a detector stacked on another floor.
            local dx, dy = playerPos.x - data.x, playerPos.y - data.y
            local horiz = math.sqrt(dx * dx + dy * dy)
            local vert  = math.abs(playerPos.z - data.z)
            if horiz < (data.radius or Config.MetalDetector.radius) and vert < 3.0 then
                if not DetectorTriggered[data.id] then
                    DetectorTriggered[data.id] = true
                    if armed then
                        local detector = {
                            coords = { x = data.x, y = data.y, z = data.z },
                            info   = { id = 'pp_' .. data.id, sound = { range = Config.MetalDetector.soundRange } },
                        }
                        if GetResourceState('metal-detectors') == 'started' then
                            -- Reuse the metal-detectors alarm (broadcast to all nearby players)
                            TriggerServerEvent('DetectorAlarm', GetPlayerServerId(PlayerId()), detector)
                        else
                            DetectorBeepLocal(data.x, data.y, data.z, Config.MetalDetector.soundRange)
                        end
                    end
                end
            else
                DetectorTriggered[data.id] = nil
            end
        end

        ::detectorSkip::
    end
end)

-- ═══════════════════════════════════════════════════════════
--  INITIAL LOAD
-- ═══════════════════════════════════════════════════════════

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function() isLoggedIn = true end)
AddEventHandler('QBCore:Client:OnPlayerLoaded', function() isLoggedIn = true end)
RegisterNetEvent('QBCore:Client:OnPlayerUnload', function()
    isLoggedIn = false
    DespawnAllPeds()
    DespawnAllRadios()
    DespawnAllDetectors()
    AllPedData = {}
    AllRadioData = {}
    AllDetectorData = {}
    -- Everything above is now empty, so the streaming loop must refetch on the
    -- next character load — otherwise it streams nothing forever.
    PlacerDataLoaded = false
end)

--- Pull every placed row (plus current hidden state) from the server.
--- Run on first spawn AND again after every character load: OnPlayerUnload above
--- empties the local tables, so without a refetch a relog or a multicharacter
--- switch left the client with nothing to stream and the peds only came back if
--- you restarted the resource.
local function LoadPlacerData()
    AllPedData = lib.callback.await('qb-pedplacer:server:getPeds', false) or {}
    AllRadioData = lib.callback.await('qb-pedplacer:server:getRadios', false) or {}
    AllDetectorData = lib.callback.await('qb-pedplacer:server:getDetectors', false) or {}
    -- Sync any groups currently hidden (e.g. a business closed before we joined)
    for _, g in ipairs(lib.callback.await('qb-pedplacer:server:getHiddenGroups', false) or {}) do
        HiddenGroups[g] = true
    end
    -- ...and any hidden areas (closed venues)
    local areas = lib.callback.await('qb-pedplacer:server:getHiddenAreas', false) or {}
    for key, a in pairs(areas) do HiddenAreas[key] = a end
    print('^2[qb-pedplacer]^0 Loaded ' .. #AllPedData .. ' peds, ' .. #AllRadioData .. ' radios, ' .. #AllDetectorData .. ' metal detectors')
end

CreateThread(function()
    local timeout = 0
    while not isLoggedIn do
        if LocalPlayer.state and LocalPlayer.state.isLoggedIn then isLoggedIn = true break end
        Wait(500)
        timeout = timeout + 500
        if timeout >= 60000 then isLoggedIn = true break end
    end
    Wait(3000)

    local streamErrorLogged = false
    while true do
        if isLoggedIn and not PlacerDataLoaded then
            PlacerDataLoaded = true
            LoadPlacerData()
        end

        if PlacerDataLoaded then
            -- Guarded: an error thrown by any one of these would kill this
            -- thread outright, and a dead streaming thread means no ped ever
            -- spawns again until the resource is restarted. Log it once, keep
            -- streaming.
            local ok, err = pcall(function()
                StreamPeds()
                StreamRadios()
                StreamDetectors()
            end)
            if not ok and not streamErrorLogged then
                streamErrorLogged = true
                print(('^1[qb-pedplacer]^0 Streaming error (streaming continues): %s'):format(tostring(err)))
            end
        end

        Wait(Config.StreamCheckInterval)
    end
end)

-- ═══════════════════════════════════════════════════════════
--  NET EVENTS
-- ═══════════════════════════════════════════════════════════

RegisterNetEvent('qb-pedplacer:client:spawnPed', function(data)
    table.insert(AllPedData, data)
    local playerCoords = GetEntityCoords(PlayerPedId())
    if #(playerCoords - vector3(data.x, data.y, data.z)) <= Config.RenderDistance then
        SpawnPed(data)
    end
end)

-- Hide / show every ped in a group (e.g. when a business opens or closes).
RegisterNetEvent('qb-pedplacer:client:setGroupHidden', function(group, hidden)
    if not group or group == '' then return end
    if hidden then
        HiddenGroups[group] = true
        local toRemove = {}
        for id, entry in pairs(SpawnedPeds) do
            if entry.data and entry.data.group_name == group then toRemove[#toRemove + 1] = id end
        end
        for _, id in ipairs(toRemove) do DespawnPed(id) end
    else
        HiddenGroups[group] = nil  -- StreamPeds will respawn them when in range
    end
end)

-- Hide / show every ped within an area (e.g. when a venue opens or closes).
RegisterNetEvent('qb-pedplacer:client:setAreaHidden', function(key, area)
    if not key or key == '' then return end
    if area then
        HiddenAreas[key] = area
        local toRemove = {}
        for id, entry in pairs(SpawnedPeds) do
            local d = entry.data
            if d then
                local dx, dy = d.x - area.x, d.y - area.y
                if (dx * dx + dy * dy) <= (area.r * area.r) then toRemove[#toRemove + 1] = id end
            end
        end
        for _, id in ipairs(toRemove) do DespawnPed(id) end
    else
        HiddenAreas[key] = nil  -- StreamPeds will respawn them when in range
    end
end)

-- ═══════════════════════════════════════════════════════════
--  HOME CONTROL BRIDGE EVENTS (rr-homecontrol)
-- ═══════════════════════════════════════════════════════════

-- Drive every placed ped in an area. `mode`:
--   'party' → dance loops (area.anims), 'chill' → restore placed behavior,
--   'away'  → walk to area.exit, then stay despawned until mode changes.
RegisterNetEvent('qb-pedplacer:client:homecontrolGuests', function(key, area, mode)
    if not key or not area then return end
    local prev = PartyAreas[key]

    if mode == 'chill' then
        if not prev then return end   -- nothing overridden, placed behavior already active
        PartyAreas[key] = nil
        for id, entry in pairs(SpawnedPeds) do
            local d = entry.data
            if d and PedMatchesArea(d, prev) and DoesEntityExist(entry.handle) then
                StopBehavior(id)
                ClearPedTasksImmediately(entry.handle)
                SetEntityCoords(entry.handle, d.x, d.y, d.z, false, false, false, false)
                SetEntityHeading(entry.handle, d.heading or 0.0)
                StartBehavior(entry.handle, d)
            end
        end
        return
    end

    if mode ~= 'party' and mode ~= 'away' then return end
    if prev and prev.mode == mode then return end
    area.mode = mode
    PartyAreas[key] = area

    if mode == 'party' then
        for id, entry in pairs(SpawnedPeds) do
            local d = entry.data
            if d and PedMatchesArea(d, area) and DoesEntityExist(entry.handle) then
                ApplyPartyAnim(id, entry.handle, d, area)
            end
        end
    else -- away: everyone walks out, StreamPeds culls them after the grace period
        area.graceUntil = GetGameTimer() + (area.walkMs or 20000)
        local exit = area.exit
        for id, entry in pairs(SpawnedPeds) do
            local d = entry.data
            if d and PedMatchesArea(d, area) and DoesEntityExist(entry.handle) then
                StopBehavior(id)
                FreezeEntityPosition(entry.handle, false)
                ClearPedTasksImmediately(entry.handle)
                if exit then
                    TaskGoStraightToCoord(entry.handle, exit.x, exit.y, exit.z, 1.0, area.walkMs or 20000, 0.0, 0.5)
                end
            end
        end
    end
end)

-- Mute / unmute every placed speaker zone in an area (home music toggle).
RegisterNetEvent('qb-pedplacer:client:homecontrolRadios', function(key, area, enabled)
    if not key then return end
    DisabledRadioAreas[key] = (not enabled) and area or nil
end)

RegisterNetEvent('qb-pedplacer:client:despawnPed', function(pedId)
    DespawnPed(pedId)
    FailedPeds[pedId] = nil
    for i, data in ipairs(AllPedData) do
        if data.id == pedId then table.remove(AllPedData, i) break end
    end
end)

RegisterNetEvent('qb-pedplacer:client:despawnAllPeds', function()
    DespawnAllPeds()
    AllPedData = {}
end)

RegisterNetEvent('qb-pedplacer:client:updatePedPosition', function(pedId, x, y, z, heading)
    for _, data in ipairs(AllPedData) do
        if data.id == pedId then data.x = x data.y = y data.z = z data.heading = heading break end
    end
    local entry = SpawnedPeds[pedId]
    if entry and DoesEntityExist(entry.handle) then
        SetEntityCoords(entry.handle, x, y, z, false, false, false, false)
        SetEntityHeading(entry.handle, heading)
    end
end)

-- ═══════════════════════════════════════════════════════════
--  RADIO NET EVENTS
-- ═══════════════════════════════════════════════════════════

RegisterNetEvent('qb-pedplacer:client:spawnRadio', function(data)
    AllRadioData[#AllRadioData + 1] = data
    local playerCoords = GetEntityCoords(PlayerPedId())
    if #(playerCoords - vector3(data.x, data.y, data.z)) <= (Config.RadioRenderDistance or Config.RenderDistance) then
        SpawnRadio(data)
    end
end)

RegisterNetEvent('qb-pedplacer:client:despawnRadio', function(radioId)
    DespawnRadio(radioId)
    for i, data in ipairs(AllRadioData) do
        if data.id == radioId then table.remove(AllRadioData, i) break end
    end
end)

-- ═══════════════════════════════════════════════════════════
--  METAL DETECTOR NET EVENTS
-- ═══════════════════════════════════════════════════════════

RegisterNetEvent('qb-pedplacer:client:spawnDetector', function(data)
    AllDetectorData[#AllDetectorData + 1] = data
    local playerCoords = GetEntityCoords(PlayerPedId())
    if #(playerCoords - vector3(data.x, data.y, data.z)) <= (Config.MetalDetector.renderDist or Config.RenderDistance) then
        SpawnDetector(data)
    end
end)

RegisterNetEvent('qb-pedplacer:client:despawnDetector', function(detectorId)
    DespawnDetector(detectorId)
    for i, data in ipairs(AllDetectorData) do
        if data.id == detectorId then table.remove(AllDetectorData, i) break end
    end
end)

RegisterNetEvent('qb-pedplacer:client:despawnAllDetectors', function()
    DespawnAllDetectors()
    AllDetectorData = {}
end)

RegisterNetEvent('qb-pedplacer:client:updatePatrolPoints', function(pedId, points)
    for _, data in ipairs(AllPedData) do
        if data.id == pedId then data.patrol_points = points break end
    end
    -- Restart patrol if this ped is spawned
    local entry = SpawnedPeds[pedId]
    if entry and DoesEntityExist(entry.handle) then
        StopBehavior(pedId)
        Wait(100)
        if points and #points >= 2 then
            ClearPedTasks(entry.handle)
            StartPatrolBehavior(pedId, entry.handle, points, entry.data.patrol_speed or Config.DefaultPatrolSpeed)
        end
    end
end)

-- ═══════════════════════════════════════════════════════════
--  PLACEMENT MODE
-- ═══════════════════════════════════════════════════════════

local function StartPlacement(modelName, label, scenario, weapon, invincible, frozen, behavior, wanderRadius, interactType, groupName, animDict, animName, emoteProps, startHeading)
    local hash = LoadModel(modelName)
    if not hash then
        lib.notify({ title = 'Ped Placer', description = 'Invalid model: ' .. tostring(modelName), type = 'error' })
        return
    end

    IsPlacing = true
    local playerPed = PlayerPedId()
    local coords = GetEntityCoords(playerPed)

    PreviewPed = CreatePed(4, hash, coords.x, coords.y, coords.z, 0.0, false, true)
    SetModelAsNoLongerNeeded(hash)
    ApplyAddonPedVariation(PreviewPed, modelName)
    SetEntityAsMissionEntity(PreviewPed, true, true)
    SetEntityAlpha(PreviewPed, 200, false)
    SetEntityInvincible(PreviewPed, true)
    FreezeEntityPosition(PreviewPed, true)
    SetEntityCollision(PreviewPed, false, false)
    SetBlockingOfNonTemporaryEvents(PreviewPed, true)

    lib.notify({ title = 'Ped Placer', description = 'RMB = Place  |  Scroll = Rotate  |  LMB = Cancel', type = 'inform', duration = 8000 })

    local heading = startHeading or GetEntityHeading(playerPed)

    CreateThread(function()
        while IsPlacing do
            Wait(0)
            local hitCoords = GetCoordsFromCam(20.0)
            SetEntityCoords(PreviewPed, hitCoords.x, hitCoords.y, hitCoords.z, false, false, false, false)
            PlaceObjectOnGroundProperly(PreviewPed)
            SetEntityHeading(PreviewPed, heading)

            DrawText3D(hitCoords.x, hitCoords.y, hitCoords.z + 1.2, '~g~RMB~w~ Place  |  ~y~Scroll~w~ Rotate  |  ~r~LMB~w~ Cancel')

            if IsControlPressed(0, 241) then heading = heading + 3.0 if heading > 360.0 then heading = heading - 360.0 end end
            if IsControlPressed(0, 242) then heading = heading - 3.0 if heading < 0.0 then heading = heading + 360.0 end end

            if IsControlJustPressed(0, 25) then
                IsPlacing = false
                local finalCoords = GetEntityCoords(PreviewPed)
                if DoesEntityExist(PreviewPed) then DeletePed(PreviewPed) end
                PreviewPed = nil

                TriggerServerEvent('qb-pedplacer:server:placePed', {
                    model        = modelName,
                    x            = finalCoords.x,
                    y            = finalCoords.y,
                    z            = finalCoords.z,
                    heading      = heading,
                    scenario     = scenario or '',
                    weapon       = weapon or '',
                    invincible   = invincible,
                    frozen       = frozen,
                    label        = label or 'Custom Ped',
                    behavior     = behavior or 'idle',
                    wander_radius = wanderRadius or Config.DefaultWanderRadius,
                    interact_type = interactType or '',
                    group_name   = groupName or '',
                    animDict     = animDict or '',
                    animName     = animName or '',
                    emote_props  = emoteProps or nil,
                })
                break
            end

            if IsControlJustPressed(0, 24) then
                IsPlacing = false
                if DoesEntityExist(PreviewPed) then DeletePed(PreviewPed) end
                PreviewPed = nil
                lib.notify({ title = 'Ped Placer', description = 'Cancelled.', type = 'error' })
                break
            end
        end
    end)
end

-- ═══════════════════════════════════════════════════════════
--  CASINO DEALER (BLACKJACK) PLACEMENT
--  Place the dealer AT an existing blackjack table -> snaps to that table's
--  exact origin (so cards/chips line up) and registers a PLAYABLE dealer with
--  the casino engine via rr-casino-placer. No table within range -> falls back
--  to a normal decorative dealer ped placed through qb-pedplacer.
-- ═══════════════════════════════════════════════════════════
local function FindNearestCasinoTable(coords)
    local best, bestDist = 0, math.huge
    for _, name in ipairs(Config.CasinoTableModels) do
        local obj = GetClosestObjectOfType(coords.x, coords.y, coords.z, Config.CasinoSnapRadius, joaat(name), false, false, false)
        if obj ~= 0 and DoesEntityExist(obj) then
            local d = #(coords - GetEntityCoords(obj))
            if d < bestDist then best, bestDist = obj, d end
        end
    end
    if best ~= 0 then
        local pos = GetEntityCoords(best)
        return { x = pos.x, y = pos.y, z = pos.z, w = GetEntityHeading(best) }
    end
    return nil
end

local function StartCasinoDealerPlacement(highStakes, modelName, label, groupName)
    local model = modelName or 's_f_y_casino_01'
    local hash = LoadModel(model)
    if not hash then
        lib.notify({ title = 'Casino Dealer', description = 'Invalid model: ' .. tostring(model), type = 'error' })
        return
    end

    IsPlacing = true
    local playerPed = PlayerPedId()
    local coords = GetEntityCoords(playerPed)

    PreviewPed = CreatePed(4, hash, coords.x, coords.y, coords.z, 0.0, false, true)
    SetModelAsNoLongerNeeded(hash)
    ApplyAddonPedVariation(PreviewPed, model)
    SetEntityAsMissionEntity(PreviewPed, true, true)
    SetEntityAlpha(PreviewPed, 200, false)
    SetEntityInvincible(PreviewPed, true)
    FreezeEntityPosition(PreviewPed, true)
    SetEntityCollision(PreviewPed, false, false)
    SetBlockingOfNonTemporaryEvents(PreviewPed, true)

    lib.notify({ title = 'Casino Dealer', description = 'Place the dealer AT a blackjack table.  RMB = Place  |  Scroll = Rotate  |  LMB = Cancel', type = 'inform', duration = 9000 })

    local heading = GetEntityHeading(playerPed)

    CreateThread(function()
        while IsPlacing do
            Wait(0)
            local hitCoords = GetCoordsFromCam(20.0)
            SetEntityCoords(PreviewPed, hitCoords.x, hitCoords.y, hitCoords.z, false, false, false, false)
            PlaceObjectOnGroundProperly(PreviewPed)
            SetEntityHeading(PreviewPed, heading)

            local nearTable = FindNearestCasinoTable(GetEntityCoords(PreviewPed)) ~= nil
            DrawText3D(hitCoords.x, hitCoords.y, hitCoords.z + 1.2,
                (nearTable and '~g~At a table — PLAYABLE~w~' or '~o~No table near — decorative~w~') ..
                '\n~g~RMB~w~ Place  |  ~y~Scroll~w~ Rotate  |  ~r~LMB~w~ Cancel')

            if IsControlPressed(0, 241) then heading = heading + 3.0 if heading > 360.0 then heading = heading - 360.0 end end
            if IsControlPressed(0, 242) then heading = heading - 3.0 if heading < 0.0 then heading = heading + 360.0 end end

            if IsControlJustPressed(0, 25) then
                IsPlacing = false
                local finalCoords = GetEntityCoords(PreviewPed)
                if DoesEntityExist(PreviewPed) then DeletePed(PreviewPed) end
                PreviewPed = nil

                local t = FindNearestCasinoTable(finalCoords)
                if t and GetResourceState(Config.CasinoPlacer) == 'started' then
                    -- PLAYABLE: snap to the table origin and register with the casino engine
                    TriggerServerEvent('rr-casino-placer:save', {
                        x = t.x, y = t.y, z = t.z, w = t.w, highStakes = highStakes,
                    })
                    lib.notify({ title = 'Casino Dealer', description = 'Snapped to the table — playable dealer registered. The casino engine will respawn dealers.', type = 'success', duration = 8000 })
                else
                    -- DECORATIVE fallback: a standing dealer ped via qb-pedplacer
                    if t then
                        lib.notify({ title = 'Casino Dealer', description = Config.CasinoPlacer .. ' is not running — placed a decorative dealer instead.', type = 'warning', duration = 9000 })
                    else
                        lib.notify({ title = 'Casino Dealer', description = 'No blackjack table within range — placed a decorative dealer.', type = 'warning', duration = 9000 })
                    end
                    TriggerServerEvent('qb-pedplacer:server:placePed', {
                        model        = model,
                        x            = finalCoords.x,
                        y            = finalCoords.y,
                        z            = finalCoords.z,
                        heading      = heading,
                        scenario     = 'WORLD_HUMAN_STAND_IMPATIENT',
                        weapon       = '',
                        invincible   = true,
                        frozen       = true,
                        label        = label or 'Casino Dealer',
                        behavior     = 'scenario',
                        group_name   = groupName or '',
                    })
                end
                break
            end

            if IsControlJustPressed(0, 24) then
                IsPlacing = false
                if DoesEntityExist(PreviewPed) then DeletePed(PreviewPed) end
                PreviewPed = nil
                lib.notify({ title = 'Casino Dealer', description = 'Cancelled.', type = 'error' })
                break
            end
        end
    end)
end

-- ═══════════════════════════════════════════════════════════
--  PATROL POINT RECORDING MODE
-- ═══════════════════════════════════════════════════════════

local function RecordPatrolPoints(pedId)
    local points = {}
    local recording = true

    lib.notify({ title = 'Patrol Recorder', description = 'Walk to each waypoint and press ~g~E~w~ to mark it. Press ~r~Backspace~w~ to finish.', type = 'inform', duration = 15000 })

    CreateThread(function()
        while recording do
            Wait(0)

            local coords = GetEntityCoords(PlayerPedId())
            DrawText3D(coords.x, coords.y, coords.z + 1.0, '~g~E~w~ = Mark Point (' .. #points .. ' saved)  |  ~r~Backspace~w~ = Done')

            -- Draw existing points
            for i, pt in ipairs(points) do
                DrawMarker(28, pt.x, pt.y, pt.z, 0, 0, 0, 0, 0, 0, 0.5, 0.5, 0.5, 0, 200, 0, 150, false, true, 2, false, nil, nil, false)
                DrawText3D(pt.x, pt.y, pt.z + 0.6, '~g~#' .. i)
                if i > 1 then
                    -- Draw line between points (visual aid)
                    local prev = points[i - 1]
                    DrawLine(prev.x, prev.y, prev.z + 0.3, pt.x, pt.y, pt.z + 0.3, 0, 200, 0, 200)
                end
            end

            -- E key to mark
            if IsControlJustPressed(0, 38) then
                table.insert(points, { x = coords.x, y = coords.y, z = coords.z })
                lib.notify({ title = 'Patrol Recorder', description = 'Point #' .. #points .. ' marked!', type = 'success' })
            end

            -- Backspace to finish
            if IsControlJustPressed(0, 177) then
                recording = false
            end
        end

        if #points >= 2 then
            TriggerServerEvent('qb-pedplacer:server:savePatrolPoints', pedId, points)
        else
            lib.notify({ title = 'Patrol Recorder', description = 'Need at least 2 points! Route not saved.', type = 'error' })
        end
    end)
end

-- ═══════════════════════════════════════════════════════════
--  MENU SYSTEM
-- ═══════════════════════════════════════════════════════════

-- BEHAVIOR SELECTION MENU
local function OpenBehaviorMenu(modelName, label, weapon, invincible, frozen, groupName)
    local options = {}

    -- Idle
    options[#options + 1] = {
        title = '🧍 Idle (Stand Still)',
        description = 'Ped stands in place, no animation',
        onSelect = function()
            StartPlacement(modelName, label, '', weapon, invincible, frozen, 'idle', nil, nil, groupName)
        end,
    }

    -- Scenario — shows scenario submenu
    options[#options + 1] = {
        title = '🎬 Play Scenario',
        description = 'Choose an animation for the ped to loop',
        arrow = true,
        onSelect = function()
            OpenScenarioMenu(modelName, label, weapon, invincible, frozen, groupName)
        end,
    }

    -- Wander
    options[#options + 1] = {
        title = '🚶 Wander in Area',
        description = 'Ped roams freely within a radius',
        onSelect = function()
            local input = lib.inputDialog('Wander Settings', {
                { type = 'number', label = 'Wander Radius (meters)', default = Config.DefaultWanderRadius, min = 5, max = 100 },
            })
            local radius = (input and input[1]) or Config.DefaultWanderRadius
            StartPlacement(modelName, label, '', weapon, invincible, false, 'wander', radius, nil, groupName)
        end,
    }

    -- Patrol
    options[#options + 1] = {
        title = '📍 Patrol Route',
        description = 'Place ped, then record waypoints for it to walk between',
        onSelect = function()
            local input = lib.inputDialog('Patrol Settings', {
                { type = 'number', label = 'Walk Speed (1.0 = walk, 2.0 = run)', default = Config.DefaultPatrolSpeed, min = 0.5, max = 3.0 },
            })
            local speed = (input and input[1]) or Config.DefaultPatrolSpeed
            -- Place ped first, then record patrol after
            lib.notify({ title = 'Ped Placer', description = 'Place the ped first, then you\'ll record patrol points.', type = 'inform', duration = 5000 })

            local hash = LoadModel(modelName)
            if not hash then return end

            IsPlacing = true
            local playerPed = PlayerPedId()
            local coords = GetEntityCoords(playerPed)
            PreviewPed = CreatePed(4, hash, coords.x, coords.y, coords.z, 0.0, false, true)
            SetModelAsNoLongerNeeded(hash)
            ApplyAddonPedVariation(PreviewPed, modelName)
            SetEntityAsMissionEntity(PreviewPed, true, true)
            SetEntityAlpha(PreviewPed, 200, false)
            SetEntityInvincible(PreviewPed, true)
            FreezeEntityPosition(PreviewPed, true)
            SetEntityCollision(PreviewPed, false, false)
            SetBlockingOfNonTemporaryEvents(PreviewPed, true)
            local heading = GetEntityHeading(playerPed)

            CreateThread(function()
                while IsPlacing do
                    Wait(0)
                    local hitCoords = GetCoordsFromCam(20.0)
                    SetEntityCoords(PreviewPed, hitCoords.x, hitCoords.y, hitCoords.z, false, false, false, false)
                    PlaceObjectOnGroundProperly(PreviewPed)
                    SetEntityHeading(PreviewPed, heading)
                    DrawText3D(hitCoords.x, hitCoords.y, hitCoords.z + 1.2, '~g~RMB~w~ Place  |  ~y~Scroll~w~ Rotate  |  ~r~LMB~w~ Cancel')
                    if IsControlPressed(0, 241) then heading = heading + 3.0 end
                    if IsControlPressed(0, 242) then heading = heading - 3.0 end

                    if IsControlJustPressed(0, 25) then
                        IsPlacing = false
                        local finalCoords = GetEntityCoords(PreviewPed)
                        if DoesEntityExist(PreviewPed) then DeletePed(PreviewPed) end
                        PreviewPed = nil

                        -- Place with patrol behavior and speed, but no points yet
                        TriggerServerEvent('qb-pedplacer:server:placePed', {
                            model = modelName, x = finalCoords.x, y = finalCoords.y, z = finalCoords.z,
                            heading = heading, scenario = '', weapon = weapon or '',
                            invincible = invincible, frozen = false,
                            label = label or 'Custom Ped', behavior = 'patrol',
                            patrol_speed = speed, group_name = groupName or '',
                        })

                        -- Wait a moment for the ped to be inserted, then start recording
                        Wait(1500)
                        -- Find the newest ped (highest ID)
                        local newestId = 0
                        for _, d in ipairs(AllPedData) do
                            if d.id > newestId then newestId = d.id end
                        end
                        if newestId > 0 then
                            RecordPatrolPoints(newestId)
                        end
                        break
                    end

                    if IsControlJustPressed(0, 24) then
                        IsPlacing = false
                        if DoesEntityExist(PreviewPed) then DeletePed(PreviewPed) end
                        PreviewPed = nil
                        break
                    end
                end
            end)
        end,
    }

    -- Interact
    options[#options + 1] = {
        title = '💬 Interact with Nearby',
        description = 'Ped faces nearest ped and performs social animations',
        arrow = true,
        onSelect = function()
            local interactOptions = {}
            for _, ia in ipairs(Config.Interactions) do
                interactOptions[#interactOptions + 1] = {
                    title = ia.label,
                    onSelect = function()
                        StartPlacement(modelName, label, '', weapon, invincible, false, 'interact', nil, ia.scenario, groupName)
                    end,
                }
            end
            lib.registerContext({ id = 'pedplacer_interact', title = '💬 Interaction Type', menu = 'pedplacer_behavior', options = interactOptions })
            lib.showContext('pedplacer_interact')
        end,
    }

    -- Bartender — serves drinks via rr-bartender (order over the bar)
    options[#options + 1] = {
        title = '🍸 Bartender (Serves Drinks)',
        description = 'Players can walk up and order a drink — served over the bar',
        onSelect = function()
            StartPlacement(modelName, label, 'WORLD_HUMAN_STAND_IMPATIENT', weapon, invincible, false, 'bartender', nil, nil, groupName)
        end,
    }

    -- Casino Dealer — playable blackjack when placed at a table (via rr-casino-placer)
    options[#options + 1] = {
        title = '🎰 Casino Dealer — Standard',
        description = 'Place AT a blackjack table → playable (cash bets up to $50k). No table = decorative.',
        onSelect = function()
            StartCasinoDealerPlacement(false, modelName, label, groupName)
        end,
    }
    options[#options + 1] = {
        title = '🎰 Casino Dealer — High-Limit',
        description = 'Place AT a blackjack table → playable high-stakes. No table = decorative.',
        onSelect = function()
            StartCasinoDealerPlacement(true, modelName, label, groupName)
        end,
    }

    lib.registerContext({ id = 'pedplacer_behavior', title = '🎭 Choose Behavior', menu = 'pedplacer_weapon', options = options })
    lib.showContext('pedplacer_behavior')
end

-- ═══════════════════════════════════════════════════════════
--  EMOTE MENU (scully_emotemenu bridge)
-- ═══════════════════════════════════════════════════════════
local EMOTE_BROWSE_CAP = 100   -- max emotes listed when browsing a category (use search for the rest)
local EMOTE_SEARCH_CAP = 200   -- max search results shown at once

--- Resolve a scully emote and hand it to the normal placement flow as a looping
--- scenario (with any held props threaded through to the ped).
local function PlaceEmote(modelName, label, weapon, invincible, frozen, groupName, emote)
    local dict, anim, props = ResolveEmote(emote)
    if not dict or not anim or dict == '' or anim == '' then
        lib.notify({ title = 'Ped Placer', description = 'That emote has no playable animation.', type = 'error' })
        return
    end
    -- Only carry/store props for emotes that actually need them; propless
    -- emotes (most dances, leaning, etc.) save nothing (DB stays NULL).
    if not props or #props == 0 then props = nil end
    StartPlacement(modelName, label, '', weapon, invincible, frozen, 'scenario', nil, nil, groupName, dict, anim, props)
end

--- Build one context-menu row for an emote.
local function EmoteOption(modelName, label, weapon, invincible, frozen, groupName, e, categoryName)
    local hasProps = e.Options and e.Options.Props and #e.Options.Props > 0
    local desc = ('/e %s'):format(e.Command or '?')
    if categoryName then desc = ('%s  ·  %s'):format(categoryName, desc) end
    if hasProps then desc = desc .. '  ·  🎒 prop' end
    return {
        title = e.Label or e.Command or 'Emote',
        description = desc,
        onSelect = function() PlaceEmote(modelName, label, weapon, invincible, frozen, groupName, e) end,
    }
end

--- Search emotes by label/command. `cat` nil = search every category.
function OpenEmoteSearch(modelName, label, weapon, invincible, frozen, groupName, cat)
    local input = lib.inputDialog('Search Emotes', {
        { type = 'input', label = 'Search', description = 'Name or command — e.g. "smoke", "lean", "beer"', required = true },
    })
    if not input or not input[1] then return end

    local q = tostring(input[1]):lower()
    local pools = cat and { cat } or EmoteCategories
    local results = {}
    for _, c in ipairs(pools) do
        for _, e in ipairs(c.options) do
            if not e.Hide then
                local lbl = (e.Label or ''):lower()
                local cmd = (e.Command or ''):lower()
                if lbl:find(q, 1, true) or cmd:find(q, 1, true) then
                    results[#results + 1] = { c = c, e = e }
                    if #results >= EMOTE_SEARCH_CAP then break end
                end
            end
        end
        if #results >= EMOTE_SEARCH_CAP then break end
    end

    if #results == 0 then
        lib.notify({ title = 'Ped Placer', description = 'No emotes match "' .. q .. '".', type = 'error' })
        return
    end

    local options = {}
    for _, r in ipairs(results) do
        options[#options + 1] = EmoteOption(modelName, label, weapon, invincible, frozen, groupName, r.e, r.c.name)
    end
    lib.registerContext({ id = 'pedplacer_emote_search', title = ('🔍 Results (%d)'):format(#results), menu = 'pedplacer_emote_root', options = options })
    lib.showContext('pedplacer_emote_search')
end

--- Browse a single emote category (capped; leads with a scoped search).
function OpenEmoteCategory(modelName, label, weapon, invincible, frozen, groupName, cat)
    local options = {
        { title = '🔍 Search ' .. cat.name, description = 'Filter this category', onSelect = function()
            OpenEmoteSearch(modelName, label, weapon, invincible, frozen, groupName, cat)
        end },
    }

    local shown = 0
    for _, e in ipairs(cat.options) do
        if not e.Hide then
            shown = shown + 1
            if shown > EMOTE_BROWSE_CAP then break end
            options[#options + 1] = EmoteOption(modelName, label, weapon, invincible, frozen, groupName, e)
        end
    end
    if shown > EMOTE_BROWSE_CAP then
        options[#options + 1] = { title = '… more not shown — use Search above', disabled = true }
    end

    lib.registerContext({ id = 'pedplacer_emote_cat', title = cat.icon .. ' ' .. cat.name, menu = 'pedplacer_emote_root', options = options })
    lib.showContext('pedplacer_emote_cat')
end

--- Root of the emote branch: search, exact-command, and per-category browse.
function OpenEmoteRootMenu(modelName, label, weapon, invincible, frozen, groupName)
    if not LoadEmoteLibrary() then
        lib.notify({ title = 'Ped Placer', description = EMOTE_RESOURCE .. ' is not started — emote library unavailable.', type = 'error', duration = 8000 })
        return
    end

    local options = {
        {
            title = '🔍 Search Emotes',
            description = 'Search by name or command across all categories',
            onSelect = function() OpenEmoteSearch(modelName, label, weapon, invincible, frozen, groupName, nil) end,
        },
        {
            title = '⌨️ Enter Exact Command',
            description = 'Straight from /e — e.g. dance3, beer, cigar, lean',
            onSelect = function()
                local input = lib.inputDialog('Emote Command', {
                    { type = 'input', label = 'Command', description = 'The /e command, e.g. "lean"', required = true },
                })
                if not input or not input[1] then return end
                local cmd = tostring(input[1]):gsub('%s+', ''):lower()
                local emote = EmoteByCommand[cmd]
                if not emote then
                    lib.notify({ title = 'Ped Placer', description = 'No emote with command "' .. cmd .. '".', type = 'error' })
                    return
                end
                PlaceEmote(modelName, label, weapon, invincible, frozen, groupName, emote)
            end,
        },
    }

    for _, cat in ipairs(EmoteCategories) do
        options[#options + 1] = {
            title = cat.icon .. ' ' .. cat.name,
            description = #cat.options .. ' emotes',
            arrow = true,
            onSelect = function() OpenEmoteCategory(modelName, label, weapon, invincible, frozen, groupName, cat) end,
        }
    end

    lib.registerContext({ id = 'pedplacer_emote_root', title = '🕺 Emote Menu', menu = 'pedplacer_scenario', options = options })
    lib.showContext('pedplacer_emote_root')
end

-- SCENARIO MENU
function OpenScenarioMenu(modelName, label, weapon, invincible, frozen, groupName)
    local options = {}
    -- Emote Menu (scully) bridge — full animation / dance / prop-emote library
    if EmotesAvailable() then
        options[#options + 1] = {
            title = '🕺 Emote Menu (Scully)…',
            description = 'Use any emote / dance / prop emote from your /e menu',
            arrow = true,
            onSelect = function() OpenEmoteRootMenu(modelName, label, weapon, invincible, frozen, groupName) end,
        }
    end
    for _, s in ipairs(Config.Scenarios) do
        local desc = s.scenario ~= '' and s.scenario or (s.animDict and s.animDict ~= '' and s.animDict or 'Ped stands idle')
        options[#options + 1] = {
            title = s.label,
            description = desc,
            onSelect = function()
                StartPlacement(modelName, label, s.scenario, weapon, invincible, frozen, 'scenario', nil, nil, groupName, s.animDict, s.animName)
            end,
        }
    end
    lib.registerContext({ id = 'pedplacer_scenario', title = '🎬 Choose Scenario', menu = 'pedplacer_behavior', options = options })
    lib.showContext('pedplacer_scenario')
end

-- WEAPON MENU
local function OpenWeaponMenu(modelName, label, invincible, frozen, groupName)
    local options = {}
    for _, w in ipairs(Config.Weapons) do
        options[#options + 1] = {
            title = w.label,
            onSelect = function()
                OpenBehaviorMenu(modelName, label, w.weapon, invincible, frozen, groupName)
            end,
        }
    end
    lib.registerContext({ id = 'pedplacer_weapon', title = '🔫 Choose Weapon', menu = 'pedplacer_settings', options = options })
    lib.showContext('pedplacer_weapon')
end

-- SETTINGS MENU
local function OpenSettingsMenu(modelName, label, groupName)
    lib.registerContext({
        id = 'pedplacer_settings',
        title = '⚙️ Ped Settings',
        menu = 'pedplacer_model_select',
        options = {
            { title = 'Invincible + Frozen (Default)', description = 'Best for static scenario peds', onSelect = function() OpenWeaponMenu(modelName, label, true, true, groupName) end },
            { title = 'Invincible + Unfrozen', description = 'Best for wandering/patrol peds', onSelect = function() OpenWeaponMenu(modelName, label, true, false, groupName) end },
            { title = 'Mortal + Frozen', description = 'Can be killed but stays put', onSelect = function() OpenWeaponMenu(modelName, label, false, true, groupName) end },
            { title = 'Mortal + Unfrozen', description = 'Fully interactive', onSelect = function() OpenWeaponMenu(modelName, label, false, false, groupName) end },
        },
    })
    lib.showContext('pedplacer_settings')
end

-- MODEL SELECT
local function OpenPresetModels(category)
    local options = {}
    for _, m in ipairs(category.models) do
        options[#options + 1] = {
            title = m.label, description = m.model,
            onSelect = function() OpenSettingsMenu(m.model, m.label) end,
        }
    end
    lib.registerContext({ id = 'pedplacer_model_select', title = category.label, menu = 'pedplacer_place', options = options })
    lib.showContext('pedplacer_model_select')
end

local function OpenCustomModelInput()
    local input = lib.inputDialog('Custom Ped Model', {
        { type = 'input', label = 'Model Name', description = 'e.g. s_m_y_cop_01', required = true },
        { type = 'input', label = 'Label (optional)', required = false },
    })
    if not input then return end
    local modelName = input[1]
    local label = (input[2] and input[2] ~= '') and input[2] or modelName
    if not IsModelValid(joaat(modelName)) then
        lib.notify({ title = 'Ped Placer', description = 'Invalid model: ' .. modelName, type = 'error' })
        return
    end
    OpenSettingsMenu(modelName, label)
end

-- PLACE MENU
local function OpenPlaceMenu()
    local options = {}
    for _, cat in ipairs(Config.Presets) do
        options[#options + 1] = {
            title = cat.label, description = #cat.models .. ' models', arrow = true,
            onSelect = function() OpenPresetModels(cat) end,
        }
    end
    options[#options + 1] = {
        title = '✏️ Custom Model', description = 'Type any ped model name',
        onSelect = function() OpenCustomModelInput() end,
    }
    lib.registerContext({ id = 'pedplacer_place', title = '➕ Place New Ped', menu = 'pedplacer_main', options = options })
    lib.showContext('pedplacer_place')
end

-- ═══════════════════════════════════════════════════════════
--  MANAGE / ACTIONS MENUS
-- ═══════════════════════════════════════════════════════════

function OpenPedActionsMenu(data)
    local actionOptions = {
        {
            title = '📍 Teleport To Ped',
            onSelect = function()
                SetEntityCoords(PlayerPedId(), data.x, data.y, data.z, false, false, false, false)
            end,
        },
        {
            title = '🔄 Move Ped Here',
            onSelect = function()
                local c = GetEntityCoords(PlayerPedId())
                TriggerServerEvent('qb-pedplacer:server:updatePedPosition', data.id, c.x, c.y, c.z, GetEntityHeading(PlayerPedId()))
            end,
        },
    }

    -- Add patrol point recording for patrol peds
    if data.behavior == 'patrol' then
        actionOptions[#actionOptions + 1] = {
            title = '📍 Record Patrol Route',
            description = 'Walk and mark waypoints for this ped',
            onSelect = function() RecordPatrolPoints(data.id) end,
        }
    end

    actionOptions[#actionOptions + 1] = {
        title = '🗑️ Delete This Ped',
        onSelect = function()
            local confirm = lib.alertDialog({ header = 'Delete Ped #' .. data.id .. '?', content = 'Permanently delete **' .. (data.label or data.model) .. '**?', centered = true, cancel = true })
            if confirm == 'confirm' then TriggerServerEvent('qb-pedplacer:server:deletePed', data.id) end
        end,
    }

    lib.registerContext({ id = 'pedplacer_actions', title = '#' .. data.id .. ' — ' .. (data.label or data.model), menu = 'pedplacer_manage', options = actionOptions })
    lib.showContext('pedplacer_actions')
end

local function OpenManageMenu()
    local options = {}
    if #AllPedData == 0 then
        options[#options + 1] = { title = 'No peds placed yet', disabled = true }
    else
        for _, data in ipairs(AllPedData) do
            local dist = #(GetEntityCoords(PlayerPedId()) - vector3(data.x, data.y, data.z))
            local beh = data.behavior or 'idle'
            options[#options + 1] = {
                title = string.format('#%d — %s', data.id, data.label or data.model),
                description = string.format('%s | %s | %.0fm', data.model, beh, dist),
                onSelect = function() OpenPedActionsMenu(data) end,
            }
        end
    end
    lib.registerContext({ id = 'pedplacer_manage', title = '📋 Manage (' .. #AllPedData .. ' peds)', menu = 'pedplacer_main', options = options })
    lib.showContext('pedplacer_manage')
end

local function OpenNearbyMenu()
    local playerCoords = GetEntityCoords(PlayerPedId())
    local nearby = {}
    for _, data in ipairs(AllPedData) do
        local dist = #(playerCoords - vector3(data.x, data.y, data.z))
        if dist <= 30.0 then nearby[#nearby + 1] = { data = data, dist = dist } end
    end
    table.sort(nearby, function(a, b) return a.dist < b.dist end)

    local options = {}
    if #nearby == 0 then
        options[#options + 1] = { title = 'No peds within 30m', disabled = true }
    else
        for _, entry in ipairs(nearby) do
            options[#options + 1] = {
                title = string.format('#%d — %s (%.1fm)', entry.data.id, entry.data.label or entry.data.model, entry.dist),
                onSelect = function() OpenPedActionsMenu(entry.data) end,
            }
        end
    end
    lib.registerContext({ id = 'pedplacer_nearby', title = '📡 Nearby (30m)', menu = 'pedplacer_main', options = options })
    lib.showContext('pedplacer_nearby')
end

-- ═══════════════════════════════════════════════════════════
--  GROUP MENUS
-- ═══════════════════════════════════════════════════════════

--- Place a preset group at your location
--- Get the correct ground Z at a world position (works on MLO floors, Cayo, terrain)
--- Probes CLOSE first so we find the MLO floor we're on, not outdoor terrain above/below.
local function GetGroundZ(x, y, z)
    -- Request collision so MLO/interior geometry is loaded at the target
    RequestCollisionAtCoord(x, y, z)
    local waited = 0
    while not HasCollisionLoadedAroundEntity(PlayerPedId()) and waited < 500 do
        Wait(10)
        waited = waited + 10
    end

    -- Raycast: tight range first (best for MLO floors — won't escape through ceiling)
    local ray1 = StartShapeTestRay(x, y, z + 3.0, x, y, z - 3.0, 1 + 16, PlayerPedId(), 0)
    local _, hit1, hitCoords1 = GetShapeTestResult(ray1)
    if hit1 == 1 and math.abs(hitCoords1.z - z) < 4.0 then
        return hitCoords1.z
    end

    -- Raycast: medium range (multi-story MLOs, slight elevation changes)
    local ray2 = StartShapeTestRay(x, y, z + 10.0, x, y, z - 10.0, 1 + 16, PlayerPedId(), 0)
    local _, hit2, hitCoords2 = GetShapeTestResult(ray2)
    if hit2 == 1 and math.abs(hitCoords2.z - z) < 12.0 then
        return hitCoords2.z
    end

    -- GetGroundZFor_3dCoord: close probes only (safe for outdoor terrain + Cayo)
    local probeOffsets = { 2.0, 5.0, 10.0 }
    for _, offset in ipairs(probeOffsets) do
        local found, groundZ = GetGroundZFor_3dCoord(x, y, z + offset, false)
        if found and math.abs(groundZ - z) < 12.0 then
            return groundZ
        end
    end

    -- Last resort: wide raycast for extreme terrain (cliffs, Cayo hills)
    local ray3 = StartShapeTestRay(x, y, z + 50.0, x, y, z - 50.0, 1 + 16, PlayerPedId(), 0)
    local _, hit3, hitCoords3 = GetShapeTestResult(ray3)
    if hit3 == 1 then
        return hitCoords3.z
    end

    return z -- absolute fallback: use provided Z
end

local function PlacePresetGroup(group)
    local baseCoords = GetEntityCoords(PlayerPedId())
    local baseHeading = GetEntityHeading(PlayerPedId())
    local rad = math.rad(baseHeading)

    lib.notify({ title = 'Ped Placer', description = 'Placing "' .. group.label .. '" (' .. #group.peds .. ' peds)...', type = 'inform' })

    for _, pedDef in ipairs(group.peds) do
        -- Rotate offsets by player heading
        local rotX = pedDef.offsetX * math.cos(rad) - pedDef.offsetY * math.sin(rad)
        local rotY = pedDef.offsetX * math.sin(rad) + pedDef.offsetY * math.cos(rad)

        local finalX = baseCoords.x + rotX
        local finalY = baseCoords.y + rotY
        local finalZ = GetGroundZ(finalX, finalY, baseCoords.z + (pedDef.offsetZ or 0.0))

        -- A preset ped may opt out of the defaults: gang houses place MORTAL
        -- peds (rr-gangwar fights them), everything else keeps the old
        -- invincible + frozen-when-stationary behaviour.
        local invincible = pedDef.invincible
        if invincible == nil then invincible = true end
        local frozen = pedDef.frozen
        if frozen == nil then frozen = (pedDef.behavior == 'idle' or pedDef.behavior == 'scenario') end

        TriggerServerEvent('qb-pedplacer:server:placePed', {
            model         = pedDef.model,
            x             = finalX,
            y             = finalY,
            z             = finalZ,
            heading       = baseHeading + (pedDef.heading or 0.0),
            scenario      = pedDef.scenario or '',
            weapon        = pedDef.weapon or '',
            invincible    = invincible,
            frozen        = frozen,
            label         = pedDef.label or pedDef.model,
            behavior      = pedDef.behavior or 'scenario',
            wander_radius = pedDef.wander_radius or Config.DefaultWanderRadius,
            interact_type = pedDef.interact_type or '',
            group_name    = group.label,
        })
        Wait(200) -- stagger to avoid overloading
    end
end

--- Place a saved custom group
local function PlaceSavedGroup(groupData)
    local baseCoords = GetEntityCoords(PlayerPedId())
    local baseHeading = GetEntityHeading(PlayerPedId())
    local rad = math.rad(baseHeading)

    local peds = json.decode(groupData.data)
    if not peds or #peds == 0 then
        lib.notify({ title = 'Ped Placer', description = 'Group has no peds!', type = 'error' })
        return
    end

    lib.notify({ title = 'Ped Placer', description = 'Placing "' .. groupData.name .. '" (' .. #peds .. ' peds)...', type = 'inform' })

    for _, pedDef in ipairs(peds) do
        local rotX = (pedDef.offsetX or 0) * math.cos(rad) - (pedDef.offsetY or 0) * math.sin(rad)
        local rotY = (pedDef.offsetX or 0) * math.sin(rad) + (pedDef.offsetY or 0) * math.cos(rad)

        local finalX = baseCoords.x + rotX
        local finalY = baseCoords.y + rotY
        local finalZ = GetGroundZ(finalX, finalY, baseCoords.z + (pedDef.offsetZ or 0.0))

        TriggerServerEvent('qb-pedplacer:server:placePed', {
            model         = pedDef.model,
            x             = finalX,
            y             = finalY,
            z             = finalZ,
            heading       = baseHeading + (pedDef.heading or 0.0),
            scenario      = pedDef.scenario or '',
            weapon        = pedDef.weapon or '',
            invincible    = true,
            frozen        = (pedDef.behavior == 'idle' or pedDef.behavior == 'scenario'),
            label         = pedDef.label or pedDef.model,
            behavior      = pedDef.behavior or 'idle',
            wander_radius = pedDef.wander_radius or Config.DefaultWanderRadius,
            interact_type = pedDef.interact_type or '',
            group_name    = groupData.name,
            animDict      = pedDef.anim_dict or '',
            animName      = pedDef.anim_name or '',
            emote_props   = pedDef.emote_props,
        })
        Wait(200)
    end
end

--- Save nearby peds as a custom group
local function SaveNearbyAsGroup()
    local input = lib.inputDialog('Save Group', {
        { type = 'input', label = 'Group Name', required = true },
        { type = 'input', label = 'Description', required = false },
        { type = 'number', label = 'Radius (meters) to capture peds', default = 30, min = 5, max = 200 },
    })
    if not input or not input[1] then return end

    local name = input[1]
    local desc = input[2] or ''
    local radius = input[3] or 30

    local playerCoords = GetEntityCoords(PlayerPedId())
    local captured = {}

    for _, data in ipairs(AllPedData) do
        local dist = #(playerCoords - vector3(data.x, data.y, data.z))
        if dist <= radius then
            captured[#captured + 1] = {
                model         = data.model,
                label         = data.label or data.model,
                offsetX       = data.x - playerCoords.x,
                offsetY       = data.y - playerCoords.y,
                offsetZ       = data.z - playerCoords.z,
                heading       = data.heading or 0.0,
                scenario      = data.scenario or '',
                weapon        = data.weapon or '',
                behavior      = data.behavior or 'idle',
                wander_radius = data.wander_radius or Config.DefaultWanderRadius,
                interact_type = data.interact_type or '',
                -- Preserve anim-based scenarios (drug/stripper) AND emote peds
                anim_dict     = data.anim_dict or '',
                anim_name     = data.anim_name or '',
                emote_props   = data.emote_props,
            }
        end
    end

    if #captured == 0 then
        lib.notify({ title = 'Ped Placer', description = 'No peds found within ' .. radius .. 'm!', type = 'error' })
        return
    end

    TriggerServerEvent('qb-pedplacer:server:saveGroup', name, desc, captured)
end

local function OpenGroupMenu()
    local options = {}

    -- Preset groups
    options[#options + 1] = {
        title = '📦 Preset Groups',
        description = #Config.PresetGroups .. ' built-in groups',
        arrow = true,
        onSelect = function()
            local presetOptions = {}
            for _, group in ipairs(Config.PresetGroups) do
                presetOptions[#presetOptions + 1] = {
                    title = group.label,
                    description = group.description,
                    onSelect = function()
                        local confirm = lib.alertDialog({ header = 'Place ' .. group.label .. '?', content = 'This will spawn **' .. #group.peds .. ' peds** at your current location.', centered = true, cancel = true })
                        if confirm == 'confirm' then PlacePresetGroup(group) end
                    end,
                }
            end
            lib.registerContext({ id = 'pedplacer_preset_groups', title = '📦 Preset Groups', menu = 'pedplacer_groups', options = presetOptions })
            lib.showContext('pedplacer_preset_groups')
        end,
    }

    -- Custom saved groups
    options[#options + 1] = {
        title = '💾 Saved Groups',
        description = 'Load or manage custom saved groups',
        arrow = true,
        onSelect = function()
            local groups = lib.callback.await('qb-pedplacer:server:getGroups', false) or {}
            local savedOptions = {}
            if #groups == 0 then
                savedOptions[#savedOptions + 1] = { title = 'No saved groups yet', disabled = true }
            else
                for _, g in ipairs(groups) do
                    local pedCount = 0
                    local parsed = json.decode(g.data)
                    if parsed then pedCount = #parsed end
                    savedOptions[#savedOptions + 1] = {
                        title = g.name,
                        description = (g.description ~= '' and g.description or pedCount .. ' peds'),
                        metadata = { { label = 'Peds', value = tostring(pedCount) } },
                        onSelect = function()
                            lib.registerContext({
                                id = 'pedplacer_saved_actions',
                                title = g.name,
                                menu = 'pedplacer_saved_groups',
                                options = {
                                    { title = '📍 Place Here', description = 'Spawn this group at your location', onSelect = function() PlaceSavedGroup(g) end },
                                    { title = '🗑️ Delete Group', onSelect = function()
                                        local confirm = lib.alertDialog({ header = 'Delete "' .. g.name .. '"?', content = 'This removes the saved group template (not placed peds).', centered = true, cancel = true })
                                        if confirm == 'confirm' then TriggerServerEvent('qb-pedplacer:server:deleteGroup', g.id) end
                                    end },
                                    { title = '🗑️ Delete All Placed Peds from this Group', onSelect = function()
                                        local confirm = lib.alertDialog({ header = 'Delete all "' .. g.name .. '" peds?', content = 'This removes every ped placed under this group name.', centered = true, cancel = true })
                                        if confirm == 'confirm' then TriggerServerEvent('qb-pedplacer:server:deleteGroupPeds', g.name) end
                                    end },
                                },
                            })
                            lib.showContext('pedplacer_saved_actions')
                        end,
                    }
                end
            end
            lib.registerContext({ id = 'pedplacer_saved_groups', title = '💾 Saved Groups', menu = 'pedplacer_groups', options = savedOptions })
            lib.showContext('pedplacer_saved_groups')
        end,
    }

    -- Save current nearby peds as group
    options[#options + 1] = {
        title = '💾 Save Nearby Peds as Group',
        description = 'Capture nearby placed peds into a reusable group',
        onSelect = function() SaveNearbyAsGroup() end,
    }

    lib.registerContext({ id = 'pedplacer_groups', title = '👥 Groups', menu = 'pedplacer_main', options = options })
    lib.showContext('pedplacer_groups')
end

-- ═══════════════════════════════════════════════════════════
--  MAIN MENU
-- ═══════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════════════════════
--  RADIO PLACEMENT
-- ═══════════════════════════════════════════════════════════

local function StartRadioPlacement(speakerModel, speakerLabel, station, stationLabel)
    local hash = LoadModel(speakerModel)
    if not hash then
        lib.notify({ title = 'Ped Placer', description = 'Invalid speaker model: ' .. tostring(speakerModel), type = 'error' })
        return
    end

    IsPlacing = true
    local playerPed = PlayerPedId()
    local coords = GetEntityCoords(playerPed)

    local previewObj = CreateObject(hash, coords.x, coords.y, coords.z, false, false, false)
    SetModelAsNoLongerNeeded(hash)
    SetEntityAsMissionEntity(previewObj, true, true)
    SetEntityAlpha(previewObj, 200, false)
    FreezeEntityPosition(previewObj, true)
    SetEntityCollision(previewObj, false, false)

    lib.notify({ title = 'Radio Placer', description = 'RMB = Place  |  Scroll = Rotate  |  LMB = Cancel\nStation: ' .. stationLabel, type = 'inform', duration = 8000 })

    local heading = GetEntityHeading(playerPed)

    CreateThread(function()
        while IsPlacing do
            Wait(0)
            local hitCoords = GetCoordsFromCam(15.0)
            SetEntityCoords(previewObj, hitCoords.x, hitCoords.y, hitCoords.z, false, false, false, false)
            PlaceObjectOnGroundProperly(previewObj)
            SetEntityHeading(previewObj, heading)

            DrawText3D(hitCoords.x, hitCoords.y, hitCoords.z + 0.8, '~g~RMB~w~ Place  |  ~y~Scroll~w~ Rotate  |  ~r~LMB~w~ Cancel')

            if IsControlPressed(0, 241) then heading = heading + 3.0 end
            if IsControlPressed(0, 242) then heading = heading - 3.0 end

            if IsControlJustPressed(0, 25) then
                IsPlacing = false
                local finalCoords = GetEntityCoords(previewObj)
                if DoesEntityExist(previewObj) then DeleteObject(previewObj) end

                TriggerServerEvent('qb-pedplacer:server:placeRadio', {
                    model   = speakerModel,
                    station = station,
                    x       = finalCoords.x,
                    y       = finalCoords.y,
                    z       = finalCoords.z,
                    heading = heading,
                    label   = speakerLabel .. ' — ' .. stationLabel,
                })
                break
            end

            if IsControlJustPressed(0, 24) then
                IsPlacing = false
                if DoesEntityExist(previewObj) then DeleteObject(previewObj) end
                lib.notify({ title = 'Radio Placer', description = 'Cancelled.', type = 'error' })
                break
            end
        end
    end)
end

-- ═══════════════════════════════════════════════════════════
--  RADIO MENUS
-- ═══════════════════════════════════════════════════════════

local function OpenRadioStationMenu(speakerModel, speakerLabel)
    local options = {}
    for _, s in ipairs(Config.RadioStations) do
        options[#options + 1] = {
            title = s.label,
            description = s.station,
            onSelect = function()
                StartRadioPlacement(speakerModel, speakerLabel, s.station, s.label)
            end,
        }
    end
    lib.registerContext({ id = 'pedplacer_radio_station', title = '📻 Choose Station', menu = 'pedplacer_radio_speaker', options = options })
    lib.showContext('pedplacer_radio_station')
end

local function OpenRadioSpeakerMenu()
    local options = {}
    for _, sp in ipairs(Config.SpeakerModels) do
        options[#options + 1] = {
            title = sp.label,
            description = sp.model,
            onSelect = function()
                OpenRadioStationMenu(sp.model, sp.label)
            end,
        }
    end
    lib.registerContext({ id = 'pedplacer_radio_speaker', title = '🔊 Choose Speaker', menu = 'pedplacer_radio', options = options })
    lib.showContext('pedplacer_radio_speaker')
end

local function OpenRadioManageMenu()
    local options = {}
    if #AllRadioData == 0 then
        options[#options + 1] = { title = 'No radios placed yet', disabled = true }
    else
        local playerCoords = GetEntityCoords(PlayerPedId())
        for _, data in ipairs(AllRadioData) do
            local dist = #(playerCoords - vector3(data.x, data.y, data.z))
            options[#options + 1] = {
                title = '#' .. data.id .. ' — ' .. (data.label or data.model),
                description = string.format('%.0fm away | %s', dist, data.station),
                onSelect = function()
                    local confirm = lib.alertDialog({
                        header = 'Delete Radio #' .. data.id .. '?',
                        content = 'Permanently delete **' .. (data.label or 'Radio') .. '**?',
                        centered = true, cancel = true,
                    })
                    if confirm == 'confirm' then
                        TriggerServerEvent('qb-pedplacer:server:deleteRadio', data.id)
                    end
                end,
            }
        end
    end
    lib.registerContext({ id = 'pedplacer_radio_manage', title = '📋 Manage Radios (' .. #AllRadioData .. ')', menu = 'pedplacer_radio', options = options })
    lib.showContext('pedplacer_radio_manage')
end

local function OpenRadioMenu()
    lib.registerContext({
        id = 'pedplacer_radio',
        title = '📻 Radio Placer',
        menu = 'pedplacer_main',
        options = {
            { title = '🔊 Place New Radio', description = 'Choose a speaker and station', arrow = true, onSelect = function() OpenRadioSpeakerMenu() end },
            { title = '📋 Manage Radios', description = #AllRadioData .. ' radios placed', arrow = true, onSelect = function() OpenRadioManageMenu() end },
        },
    })
    lib.showContext('pedplacer_radio')
end

-- ═══════════════════════════════════════════════════════════
--  METAL DETECTOR PLACEMENT
-- ═══════════════════════════════════════════════════════════

local function StartDetectorPlacement()
    local hash = LoadModel(Config.MetalDetector.model)
    if not hash then
        lib.notify({ title = 'Ped Placer', description = 'Could not load the metal-detector prop. Make sure the metal-detectors resource is started.', type = 'error' })
        return
    end

    IsPlacing = true
    local playerPed = PlayerPedId()
    local coords = GetEntityCoords(playerPed)

    local previewObj = CreateObject(hash, coords.x, coords.y, coords.z, false, false, false)
    SetModelAsNoLongerNeeded(hash)
    SetEntityAsMissionEntity(previewObj, true, true)
    SetEntityAlpha(previewObj, 200, false)
    FreezeEntityPosition(previewObj, true)
    SetEntityCollision(previewObj, false, false)

    lib.notify({ title = 'Metal Detector', description = 'RMB = Place  |  Scroll = Rotate  |  LMB = Cancel', type = 'inform', duration = 8000 })

    local heading = GetEntityHeading(playerPed)

    CreateThread(function()
        while IsPlacing do
            Wait(0)
            local hitCoords = GetCoordsFromCam(15.0)
            SetEntityCoords(previewObj, hitCoords.x, hitCoords.y, hitCoords.z, false, false, false, false)
            PlaceObjectOnGroundProperly(previewObj)
            SetEntityHeading(previewObj, heading)

            DrawText3D(hitCoords.x, hitCoords.y, hitCoords.z + 1.5, '~g~RMB~w~ Place  |  ~y~Scroll~w~ Rotate  |  ~r~LMB~w~ Cancel')

            if IsControlPressed(0, 241) then heading = heading + 3.0 end
            if IsControlPressed(0, 242) then heading = heading - 3.0 end

            if IsControlJustPressed(0, 25) then
                IsPlacing = false
                local finalCoords = GetEntityCoords(previewObj)
                if DoesEntityExist(previewObj) then DeleteObject(previewObj) end

                TriggerServerEvent('qb-pedplacer:server:placeDetector', {
                    x       = finalCoords.x,
                    y       = finalCoords.y,
                    z       = finalCoords.z,
                    heading = heading,
                    radius  = Config.MetalDetector.radius,
                    label   = Config.MetalDetector.label,
                })
                break
            end

            if IsControlJustPressed(0, 24) then
                IsPlacing = false
                if DoesEntityExist(previewObj) then DeleteObject(previewObj) end
                lib.notify({ title = 'Metal Detector', description = 'Cancelled.', type = 'error' })
                break
            end
        end
    end)
end

-- ═══════════════════════════════════════════════════════════
--  METAL DETECTOR MENUS
-- ═══════════════════════════════════════════════════════════

local function OpenDetectorManageMenu()
    local options = {}
    if #AllDetectorData == 0 then
        options[#options + 1] = { title = 'No metal detectors placed yet', disabled = true }
    else
        local playerCoords = GetEntityCoords(PlayerPedId())
        for _, data in ipairs(AllDetectorData) do
            local dist = #(playerCoords - vector3(data.x, data.y, data.z))
            options[#options + 1] = {
                title = '#' .. data.id .. ' — ' .. (data.label or 'Metal Detector'),
                description = string.format('%.0fm away | radius %.1fm', dist, data.radius or Config.MetalDetector.radius),
                onSelect = function()
                    local confirm = lib.alertDialog({
                        header = 'Delete Metal Detector #' .. data.id .. '?',
                        content = 'Permanently delete **' .. (data.label or 'Metal Detector') .. '**?',
                        centered = true, cancel = true,
                    })
                    if confirm == 'confirm' then
                        TriggerServerEvent('qb-pedplacer:server:deleteDetector', data.id)
                    end
                end,
            }
        end
    end
    lib.registerContext({ id = 'pedplacer_detector_manage', title = '📋 Manage Detectors (' .. #AllDetectorData .. ')', menu = 'pedplacer_detector', options = options })
    lib.showContext('pedplacer_detector_manage')
end

local function OpenDetectorMenu()
    lib.registerContext({
        id = 'pedplacer_detector',
        title = '🔍 Metal Detector',
        menu = 'pedplacer_main',
        options = {
            { title = '🚪 Place New Detector', description = 'Beeps when an armed player walks through', arrow = true, onSelect = function() StartDetectorPlacement() end },
            { title = '📋 Manage Detectors', description = #AllDetectorData .. ' placed', arrow = true, onSelect = function() OpenDetectorManageMenu() end },
            { title = '🗑️ Delete ALL Detectors', description = 'Wipe every placed metal detector',
                onSelect = function()
                    local confirm = lib.alertDialog({ header = 'Delete ALL Metal Detectors?', content = 'Permanently delete **every placed metal detector** from the database.', centered = true, cancel = true })
                    if confirm == 'confirm' then TriggerServerEvent('qb-pedplacer:server:deleteAllDetectors') end
                end,
            },
        },
    })
    lib.showContext('pedplacer_detector')
end

-- ═══════════════════════════════════════════════════════════

local function OpenMainMenu()
    lib.registerContext({
        id = 'pedplacer_main',
        title = '🧑 Ped Placer',
        options = {
            { title = '➕ Place New Ped', description = 'Single ped with custom behavior', arrow = true, onSelect = function() OpenPlaceMenu() end },
            { title = '👥 Groups', description = 'Place preset or saved groups of peds', arrow = true, onSelect = function() OpenGroupMenu() end },
            { title = '📻 Radios', description = 'Place speakers with radio stations', arrow = true, onSelect = function() OpenRadioMenu() end },
            { title = '🔍 Metal Detectors', description = 'Place archways that beep at armed players', arrow = true, onSelect = function() OpenDetectorMenu() end },
            { title = '📋 Manage All Peds', description = #AllPedData .. ' peds in database', arrow = true, onSelect = function() OpenManageMenu() end },
            { title = '📡 Nearby Peds', description = 'Find & manage peds within 30m', arrow = true, onSelect = function() OpenNearbyMenu() end },
            { title = '🗑️ Delete ALL Peds', description = 'Wipe everything',
                onSelect = function()
                    local confirm = lib.alertDialog({ header = 'Delete ALL Peds?', content = 'Permanently delete **every placed ped** from the database.', centered = true, cancel = true })
                    if confirm == 'confirm' then TriggerServerEvent('qb-pedplacer:server:deleteAllPeds') end
                end,
            },
        },
    })
    lib.showContext('pedplacer_main')
end

-- ═══════════════════════════════════════════════════════════
--  EVENTS
-- ═══════════════════════════════════════════════════════════

RegisterNetEvent('qb-pedplacer:client:openMenu', function() OpenPlacerUI() end)

AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    DespawnAllPeds()
    DespawnAllRadios()
    DespawnAllDetectors()
    if PreviewPed and DoesEntityExist(PreviewPed) then DeletePed(PreviewPed) end
end)

print('^2[qb-pedplacer]^0 Client loaded (v2 — behaviors + groups)')

-- ═══════════════════════════════════════════════════════════
--  PUBLIC EXPORTS (for other resources to bind to placed peds)
-- ═══════════════════════════════════════════════════════════

--- Returns the ped entity handle for a placed_peds row id, or 0 if not currently spawned/streamed.
exports('GetPedHandle', function(dbId)
    local entry = SpawnedPeds[dbId]
    if entry and DoesEntityExist(entry.handle) then
        return entry.handle
    end
    return 0
end)

--- Returns an array of placed_peds rows whose group_name matches.
--- Each row is the same data row qb-pedplacer caches client-side.
exports('GetPedsByGroup', function(groupName)
    local out = {}
    for _, data in ipairs(AllPedData) do
        if data.group_name == groupName then
            out[#out + 1] = data
        end
    end
    return out
end)

--- Returns the cached row for a single placed_peds id (whether streamed or not).
exports('GetPedData', function(dbId)
    for _, data in ipairs(AllPedData) do
        if data.id == dbId then return data end
    end
    return nil
end)

--- rr-girlfriend bridge: hand a currently-spawned placed ped over to another
--- resource. Stops our behavior/anim threads, removes held emote props, drops
--- the tracking entry WITHOUT deleting the entity (the claimer keeps it), and
--- blocks this row from respawning until UnclaimPed. Returns the placed_peds
--- data row, or nil if the entity isn't one of ours.
--- Hand a placed ped over to another resource: stops its behaviour, drops it
--- from the streaming table so the loop cannot despawn it, claims the row so no
--- duplicate respawns, and unfreezes it.
---
--- Give it back with UnclaimPed(data.id) and the streaming loop puts it back on
--- its placed spot.
---
--- ReleasePedToGirlfriend is the original name, kept because rr-girlfriend
--- calls it; this is the same function for everyone else.
local function ReleasePlacedPed(entity)
    for dbId, entry in pairs(SpawnedPeds) do
        if entry.handle == entity then
            StopBehavior(dbId)
            DeleteEmoteProps(entry.props)
            if entry.data and entry.data.behavior == 'bartender' and GetResourceState('rr-bartender') == 'started' then
                exports['rr-bartender']:RemoveBartenderTarget(entity)
            end
            SpawnedPeds[dbId] = nil
            ClaimedPeds[dbId] = true
            FreezeEntityPosition(entity, false)
            SetEntityInvincible(entity, false)
            ClearPedTasksImmediately(entity)
            return entry.data
        end
    end
    return nil
end

exports('ReleasePlacedPed', ReleasePlacedPed)
exports('ReleasePedToGirlfriend', ReleasePlacedPed)

--- Mark a placed ped row claimed by id (relog path — the claimer spawns its own
--- copy near the player, so despawn ours if it already streamed in).
exports('ClaimPedById', function(dbId)
    if not dbId then return end
    ClaimedPeds[dbId] = true
    if SpawnedPeds[dbId] then DespawnPed(dbId) end
end)

--- Release a claim; the streaming loop respawns the ped at its placed spot.
exports('UnclaimPed', function(dbId)
    if dbId then ClaimedPeds[dbId] = nil end
end)

--- rr-gangwar bridge: let another resource drive a placed ped's FIGHT while
--- we keep owning the entity. HoldPed(id, true) stops the row's behaviour
--- thread and suspends the stray snap-back for that row; HoldPed(id, false)
--- hands it back and restarts the placed behaviour from wherever the ped now
--- stands (walk it home first, or the stray check will teleport it).
--- Returns true when the row is known to this client.
exports('HoldPed', function(dbId, held)
    if not dbId then return false end
    if held then
        HeldPeds[dbId] = true
        StopBehavior(dbId)
        return true
    end
    HeldPeds[dbId] = nil
    local entry = SpawnedPeds[dbId]
    if entry and entry.handle and DoesEntityExist(entry.handle)
       and not IsPedDeadOrDying(entry.handle, true) and entry.data then
        StartBehavior(entry.handle, entry.data)
    end
    return entry ~= nil
end)

exports('IsPedHeld', function(dbId)
    return dbId ~= nil and HeldPeds[dbId] == true
end)

--- Returns ped entity handles for every currently-spawned placed_peds row
--- that has a non-empty weapon assigned. rr-guardai uses this to identify
--- which placed peds are "guards" (armed) vs scenery (unarmed).
exports('GetGuardPeds', function()
    local list = {}
    for _, entry in pairs(SpawnedPeds) do
        if entry.handle and DoesEntityExist(entry.handle)
           and not IsPedDeadOrDying(entry.handle, true)
           and entry.data and entry.data.weapon
           and entry.data.weapon ~= '' then
            list[#list + 1] = entry.handle
        end
    end
    return list
end)

-- ═══════════════════════════════════════════════════════════
--  NUI — PED PLACER DASHBOARD (purple command-center shell)
--  The /pedplacer command now opens this. The old ox_lib menus are all still
--  here and reachable from the sidebar ("Classic Menu" / Groups / Radios /
--  Metal Detectors), so nothing was removed — the NUI drives the exact same
--  StartPlacement / casino / patrol / emote flows.
-- ═══════════════════════════════════════════════════════════
local UIOpen = false

local function ClosePlacerUI()
    UIOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
end

function OpenPlacerUI()
    local ped = PlayerPedId()
    local c = GetEntityCoords(ped)
    UIOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = 'open',
        data = {
            categories   = Config.Presets,
            scenarios    = Config.Scenarios,
            weapons      = Config.Weapons,
            interactions = Config.Interactions,
            peds         = AllPedData,
            coords       = { x = c.x, y = c.y, z = c.z },
            heading      = GetEntityHeading(ped),
        },
    })
end

-- Patrol needs its own placement pass (place → then record waypoints), same as
-- the classic menu's patrol flow.
local function StartPatrolPlacementNUI(modelName, label, weapon, invincible, speed, groupName, startHeading)
    local hash = LoadModel(modelName)
    if not hash then
        lib.notify({ title = 'Ped Placer', description = 'Invalid model: ' .. tostring(modelName), type = 'error' })
        return
    end
    lib.notify({ title = 'Ped Placer', description = 'Place the ped first, then you\'ll record patrol points.', type = 'inform', duration = 5000 })

    IsPlacing = true
    local playerPed = PlayerPedId()
    local coords = GetEntityCoords(playerPed)
    PreviewPed = CreatePed(4, hash, coords.x, coords.y, coords.z, 0.0, false, true)
    SetModelAsNoLongerNeeded(hash)
    ApplyAddonPedVariation(PreviewPed, modelName)
    SetEntityAsMissionEntity(PreviewPed, true, true)
    SetEntityAlpha(PreviewPed, 200, false)
    SetEntityInvincible(PreviewPed, true)
    FreezeEntityPosition(PreviewPed, true)
    SetEntityCollision(PreviewPed, false, false)
    SetBlockingOfNonTemporaryEvents(PreviewPed, true)
    local heading = startHeading or GetEntityHeading(playerPed)

    CreateThread(function()
        while IsPlacing do
            Wait(0)
            local hitCoords = GetCoordsFromCam(20.0)
            SetEntityCoords(PreviewPed, hitCoords.x, hitCoords.y, hitCoords.z, false, false, false, false)
            PlaceObjectOnGroundProperly(PreviewPed)
            SetEntityHeading(PreviewPed, heading)
            DrawText3D(hitCoords.x, hitCoords.y, hitCoords.z + 1.2, '~g~RMB~w~ Place  |  ~y~Scroll~w~ Rotate  |  ~r~LMB~w~ Cancel')
            if IsControlPressed(0, 241) then heading = heading + 3.0 end
            if IsControlPressed(0, 242) then heading = heading - 3.0 end

            if IsControlJustPressed(0, 25) then
                IsPlacing = false
                local finalCoords = GetEntityCoords(PreviewPed)
                if DoesEntityExist(PreviewPed) then DeletePed(PreviewPed) end
                PreviewPed = nil

                TriggerServerEvent('qb-pedplacer:server:placePed', {
                    model = modelName, x = finalCoords.x, y = finalCoords.y, z = finalCoords.z,
                    heading = heading, scenario = '', weapon = weapon or '',
                    invincible = invincible, frozen = false,
                    label = label or 'Custom Ped', behavior = 'patrol',
                    patrol_speed = speed, group_name = groupName or '',
                })

                Wait(1500)
                local newestId = 0
                for _, d in ipairs(AllPedData) do
                    if d.id > newestId then newestId = d.id end
                end
                if newestId > 0 then
                    RecordPatrolPoints(newestId)
                end
                break
            end

            if IsControlJustPressed(0, 24) then
                IsPlacing = false
                if DoesEntityExist(PreviewPed) then DeletePed(PreviewPed) end
                PreviewPed = nil
                break
            end
        end
    end)
end

RegisterNUICallback('close', function(_, cb)
    UIOpen = false
    SetNuiFocus(false, false)
    cb('ok')
end)

RegisterNUICallback('getState', function(_, cb)
    local c = GetEntityCoords(PlayerPedId())
    cb({ peds = AllPedData, coords = { x = c.x, y = c.y, z = c.z } })
end)

RegisterNUICallback('placePed', function(data, cb)
    cb('ok')
    ClosePlacerUI()
    CreateThread(function()
        Wait(100)
        local behavior = data.behavior or 'idle'
        local model, label = data.model, data.label
        local group = data.groupName or ''
        local heading = tonumber(data.heading)

        if behavior == 'casino_standard' then
            StartCasinoDealerPlacement(false, model, label, group)
            return
        end
        if behavior == 'casino_high' then
            StartCasinoDealerPlacement(true, model, label, group)
            return
        end
        if behavior == 'patrol' then
            StartPatrolPlacementNUI(model, label, data.weapon or '', data.invincible,
                tonumber(data.patrolSpeed) or Config.DefaultPatrolSpeed, group, heading)
            return
        end

        local frozen = data.frozen
        if behavior == 'wander' or behavior == 'interact' or behavior == 'bartender' then frozen = false end

        local scenario = data.scenario or ''
        local animDict, animName = data.animDict or '', data.animName or ''
        if behavior == 'idle' then scenario, animDict, animName = '', '', '' end
        if behavior == 'bartender' and scenario == '' and animDict == '' then
            scenario = 'WORLD_HUMAN_STAND_IMPATIENT'
        end

        StartPlacement(model, label, scenario, data.weapon or '', data.invincible, frozen, behavior,
            tonumber(data.wanderRadius) or Config.DefaultWanderRadius,
            (behavior == 'interact') and data.interactType or nil,
            group, animDict, animName, nil, heading)
    end)
end)

RegisterNUICallback('openEmotes', function(data, cb)
    cb('ok')
    ClosePlacerUI()
    CreateThread(function()
        Wait(100)
        OpenEmoteRootMenu(data.model, data.label, data.weapon or '', data.invincible, data.frozen, data.groupName or '')
    end)
end)

RegisterNUICallback('openTool', function(data, cb)
    cb('ok')
    ClosePlacerUI()
    CreateThread(function()
        Wait(100)
        if data.tool == 'groups' then OpenGroupMenu()
        elseif data.tool == 'radios' then OpenRadioMenu()
        elseif data.tool == 'detectors' then OpenDetectorMenu()
        elseif data.tool == 'classic' then OpenMainMenu() end
    end)
end)

RegisterNUICallback('managePed', function(data, cb)
    cb('ok')
    local id = tonumber(data.id)
    if not id then return end
    local target
    for _, d in ipairs(AllPedData) do
        if d.id == id then target = d break end
    end

    if data.action == 'teleport' and target then
        ClosePlacerUI()
        SetEntityCoords(PlayerPedId(), target.x, target.y, target.z, false, false, false, false)
    elseif data.action == 'move' then
        local c = GetEntityCoords(PlayerPedId())
        TriggerServerEvent('qb-pedplacer:server:updatePedPosition', id, c.x, c.y, c.z, GetEntityHeading(PlayerPedId()))
    elseif data.action == 'record' then
        ClosePlacerUI()
        RecordPatrolPoints(id)
    elseif data.action == 'delete' then
        TriggerServerEvent('qb-pedplacer:server:deletePed', id)
    end
end)

RegisterNUICallback('deleteAllPeds', function(_, cb)
    cb('ok')
    TriggerServerEvent('qb-pedplacer:server:deleteAllPeds')
end)

--- Returns ALL currently-spawned placed peds (armed or not), each as
--- { handle, model, weapon, group, id }. rr-checkpoint uses this to find
--- army-model peds and turn them into clearance-gated checkpoint guards,
--- without requiring the ped to be placed with a weapon.
exports('GetSpawnedPeds', function()
    local list = {}
    for _, entry in pairs(SpawnedPeds) do
        if entry.handle and DoesEntityExist(entry.handle)
           and not IsPedDeadOrDying(entry.handle, true) then
            local d = entry.data or {}
            list[#list + 1] = {
                handle = entry.handle,
                model  = d.model,
                weapon = d.weapon,
                group  = d.group_name,
                id     = d.id,
            }
        end
    end
    return list
end)

-- ═══════════════════════════════════════════════════════════
--  MODEL DIAGNOSTIC  —  /pedmodelcheck <model>
--  Add-on peds (k9_retriever, etc.) can fail in several different places and
--  most of them look identical in game ("I click Place and nothing happens").
--  This walks the exact same path StartPlacement takes and prints where it
--  stops, so the failure can be named instead of guessed at.
-- ═══════════════════════════════════════════════════════════
RegisterCommand('pedmodelcheck', function(_, args)
    local modelName = args[1]
    if not modelName then
        print('^3[pedmodelcheck]^0 usage: /pedmodelcheck <model>   e.g. /pedmodelcheck k9_retriever')
        return
    end

    local hash = joaat(modelName)
    print(('^5[pedmodelcheck]^0 ── %s (hash %s) ──'):format(modelName, hash))
    print(('  IsModelValid      : %s'):format(tostring(IsModelValid(hash))))
    print(('  IsModelInCdimage  : %s'):format(tostring(IsModelInCdimage(hash))))
    print(('  IsModelAPed       : %s'):format(tostring(IsModelAPed(hash))))

    if not IsModelValid(hash) then
        print('^1  → NOT REGISTERED on this client. The peds.meta entry never reached you:')
        print('^1    fully quit FiveM and rejoin (streamed peds register at join, not on restart).^0')
        return
    end

    RequestModel(hash)
    local waited = 0
    while not HasModelLoaded(hash) and waited < 15000 do
        Wait(50); waited = waited + 50
    end
    print(('  HasModelLoaded    : %s  (after %sms)'):format(tostring(HasModelLoaded(hash)), waited))
    if not HasModelLoaded(hash) then
        print('^1  → model is registered but its stream files never arrive. Clear your FiveM')
        print('^1    cache (Application Data/FiveM/FiveM.app/data/cache) and rejoin.^0')
        return
    end

    local min, max = GetModelDimensions(hash)
    print(('  Model dimensions  : %.2f,%.2f,%.2f → %.2f,%.2f,%.2f'):format(min.x, min.y, min.z, max.x, max.y, max.z))

    -- Spawn one ped per candidate treatment, in a row, each with its letter
    -- floating above it. Whichever letters you can SEE names the fix.
    local TREATMENTS = {
        { letter = 'A', note = 'raw CreatePed (control)',            pedType = 4,  apply = function() end },
        { letter = 'B', note = 'SetPedDefaultComponentVariation',    pedType = 4,  apply = function(p) SetPedDefaultComponentVariation(p) end },
        { letter = 'C', note = 'forced component 0 / texture 0',     pedType = 4,  apply = function(p)
            SetPedDefaultComponentVariation(p)
            for comp = 0, 11 do SetPedComponentVariation(p, comp, 0, 0, 0) end
        end },
        { letter = 'D', note = 'pedType 28 (ANIMAL) + forced comps', pedType = 28, apply = function(p)
            SetPedDefaultComponentVariation(p)
            for comp = 0, 11 do SetPedComponentVariation(p, comp, 0, 0, 0) end
        end },
    }

    local base = GetEntityCoords(PlayerPedId())
    local fwd  = GetEntityForwardVector(PlayerPedId())
    -- Lay them out along the player's right, 1.5m apart, 3m in front.
    local right = vector3(-fwd.y, fwd.x, 0.0)
    local spawned = {}

    for i, t in ipairs(TREATMENTS) do
        local off = base + (fwd * 3.0) + (right * ((i - 2.5) * 1.5))
        -- Snap to the floor: a ped buried in a step would read as "invisible"
        -- for the wrong reason and wreck the whole comparison.
        local gz = GetGroundZ(off.x, off.y, off.z) or off.z
        local p = CreatePed(t.pedType, hash, off.x, off.y, gz, 0.0, false, true)
        if DoesEntityExist(p) then
            SetEntityInvincible(p, true)
            FreezeEntityPosition(p, true)
            SetBlockingOfNonTemporaryEvents(p, true)
            t.apply(p)
            Wait(150)
            spawned[#spawned + 1] = { handle = p, letter = t.letter }
            local drawables = {}
            for comp = 0, 11 do
                local n = GetNumberOfPedDrawableVariations(p, comp)
                if n > 0 then
                    drawables[#drawables + 1] = ('%d:%dv/d%d/t%d')
                        :format(comp, n, GetPedDrawableVariation(p, comp), GetPedTextureVariation(p, comp))
                end
            end
            print(('  [%s] %-38s visible=%s alpha=%s comps=%s')
                :format(t.letter, t.note, tostring(IsEntityVisible(p)), tostring(GetEntityAlpha(p)),
                        #drawables > 0 and table.concat(drawables, ' ') or '^1NONE^0'))
        else
            print(('^1  [%s] %s — CreatePed returned nothing^0'):format(t.letter, t.note))
        end
    end

    if #spawned == 0 then
        print('^1  → nothing spawned at all even though the model loaded.^0')
        SetModelAsNoLongerNeeded(hash)
        return
    end

    print('^3  → LOOK IN FRONT OF YOU. Four peds, labelled A B C D, 20 seconds.')
    print('^3    Tell me which letters you can actually SEE — that names the fix.^0')

    local until_ = GetGameTimer() + 20000
    while GetGameTimer() < until_ do
        for _, s in ipairs(spawned) do
            if DoesEntityExist(s.handle) then
                local c = GetEntityCoords(s.handle)
                DrawText3D(c.x, c.y, c.z + 1.0, s.letter)
            end
        end
        Wait(0)
    end

    for _, s in ipairs(spawned) do
        if DoesEntityExist(s.handle) then DeletePed(s.handle) end
    end
    print('^5[pedmodelcheck]^0 test peds removed.')
    SetModelAsNoLongerNeeded(hash)
end, false)
