-- Safe QBCore init (works with Qbox bridge)
local QBCore = nil
local ok, res = pcall(function() return exports['qb-core']:GetCoreObject() end)
if ok and res then QBCore = res end

-- permission check

local function IsAdmin(src)
    if IsPlayerAceAllowed(src, 'command') then return true end
    if QBCore and QBCore.Functions and QBCore.Functions.HasPermission then
        local s, r = pcall(function() return QBCore.Functions.HasPermission(src, Config.RequiredPermission) end)
        if s and r then return true end
    end
    return false
end

local function GetCitizenId(src)
    if QBCore and QBCore.Functions and QBCore.Functions.GetPlayer then
        local Player = QBCore.Functions.GetPlayer(src)
        if Player and Player.PlayerData then
            return Player.PlayerData.citizenid or 'unknown'
        end
    end
    return 'unknown'
end

--  bartender rr-bartender sync
--  Bartender peds (behavior = 'bartender') register their coords with
--  rr-bartender so its server-side proximity check accepts drink orders
--  placed at them. All calls are guarded so qb-pedplacer works fine with
--  rr-bartender absent.
local bartenderPeds = {}  -- [pedId] = true

local function rrBartenderReady()
    return GetResourceState('rr-bartender') == 'started'
end

local function RegisterBartender(id, x, y, z)
    bartenderPeds[id] = true
    if rrBartenderReady() then
        exports['rr-bartender']:RegisterBarLocation('pedplacer:' .. id, { x = x, y = y, z = z })
    end
end

local function UnregisterBartender(id)
    if not bartenderPeds[id] then return end
    bartenderPeds[id] = nil
    if rrBartenderReady() then
        exports['rr-bartender']:RemoveBarLocation('pedplacer:' .. id)
    end
end

local function RegisterAllBartenders()
    local rows = MySQL.query.await("SELECT id, x, y, z FROM placed_peds WHERE behavior = 'bartender'", {})
    if not rows then return end
    for _, row in ipairs(rows) do
        RegisterBartender(row.id, row.x, row.y, row.z)
    end
    if #rows > 0 then
        print('^2[qb-pedplacer]^0 Registered ' .. #rows .. ' bartender ped(s) with rr-bartender')
    end
end

-- Re-register everything if rr-bartender (re)starts after us
AddEventHandler('onResourceStart', function(res)
    if res ~= 'rr-bartender' then return end
    CreateThread(function()
        Wait(1000)
        RegisterAllBartenders()
    end)
end)

-- callbacks

lib.callback.register('qb-pedplacer:server:getPeds', function(source)
    local result = MySQL.query.await('SELECT * FROM placed_peds', {})
    return result or {}
end)

--  group visibility (hide/show a whole ped group, e.g. a closed business)
--  Session-only (resets on resource restart). Authoritative so late joiners
--  see the same state.
local HiddenGroups = {}  -- [group_name] = true

lib.callback.register('qb-pedplacer:server:getHiddenGroups', function(source)
    local list = {}
    for g in pairs(HiddenGroups) do list[#list + 1] = g end
    return list
end)

-- exports['qb-pedplacer']:SetGroupHidden('lifeinvader_office', true)  -> despawn for everyone
exports('SetGroupHidden', function(group, hidden)
    if type(group) ~= 'string' or group == '' then return false end
    if hidden then HiddenGroups[group] = true else HiddenGroups[group] = nil end
    TriggerClientEvent('qb-pedplacer:client:setGroupHidden', -1, group, hidden and true or false)
    return true
end)

-- area visibility, hide every placed ped within a 2D radius of a point
-- regardless of group (for venues whose peds aren't in a dedicated group).
-- Keyed so each business manages its own area independently.
local HiddenAreas = {}  -- [key] = { x, y, r }

lib.callback.register('qb-pedplacer:server:getHiddenAreas', function(source)
    return HiddenAreas
end)

-- exports['qb-pedplacer']:SetAreaHidden('vanillaunicorn', x, y, radius, true)
exports('SetAreaHidden', function(key, x, y, radius, hidden)
    if type(key) ~= 'string' or key == '' then return false end
    if hidden then
        HiddenAreas[key] = { x = (x or 0) + 0.0, y = (y or 0) + 0.0, r = (radius or 40) + 0.0 }
    else
        HiddenAreas[key] = nil
    end
    TriggerClientEvent('qb-pedplacer:client:setAreaHidden', -1, key, HiddenAreas[key])
    return true
end)

lib.callback.register('qb-pedplacer:server:getGroups', function(source)
    local result = MySQL.query.await('SELECT * FROM ped_groups ORDER BY name', {})
    return result or {}
end)

lib.callback.register('qb-pedplacer:server:getRadios', function(source)
    local result = MySQL.query.await('SELECT * FROM placed_radios', {})
    return result or {}
end)

lib.callback.register('qb-pedplacer:server:getDetectors', function(source)
    local result = MySQL.query.await('SELECT * FROM placed_metaldetectors', {})
    return result or {}
end)

-- radio crud

RegisterNetEvent('qb-pedplacer:server:placeRadio', function(data)
    local src = source
    if not IsAdmin(src) then
        TriggerClientEvent('ox_lib:notify', src, { title = 'Ped Placer', description = 'No permission.', type = 'error' })
        return
    end

    data.placed_by = GetCitizenId(src)

    MySQL.insert(
        'INSERT INTO placed_radios (model, station, x, y, z, heading, label, placed_by) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
        { data.model, data.station, data.x, data.y, data.z, data.heading or 0.0, data.label or 'Radio', data.placed_by },
        function(id)
            if id then
                data.id = id
                TriggerClientEvent('qb-pedplacer:client:spawnRadio', -1, data)
                TriggerClientEvent('ox_lib:notify', src, { title = 'Ped Placer', description = 'Radio placed! (ID: ' .. id .. ')', type = 'success' })
            else
                TriggerClientEvent('ox_lib:notify', src, { title = 'Ped Placer', description = 'Database error.', type = 'error' })
            end
        end
    )
end)

RegisterNetEvent('qb-pedplacer:server:deleteRadio', function(radioId)
    local src = source
    if not IsAdmin(src) then return end
    MySQL.query('DELETE FROM placed_radios WHERE id = ?', { radioId }, function()
        TriggerClientEvent('qb-pedplacer:client:despawnRadio', -1, radioId)
        TriggerClientEvent('ox_lib:notify', src, { title = 'Ped Placer', description = 'Radio #' .. radioId .. ' deleted.', type = 'success' })
    end)
end)

-- metal detector crud

RegisterNetEvent('qb-pedplacer:server:placeDetector', function(data)
    local src = source
    if not IsAdmin(src) then
        TriggerClientEvent('ox_lib:notify', src, { title = 'Ped Placer', description = 'No permission.', type = 'error' })
        return
    end

    data.placed_by = GetCitizenId(src)

    MySQL.insert(
        'INSERT INTO placed_metaldetectors (x, y, z, heading, radius, label, placed_by) VALUES (?, ?, ?, ?, ?, ?, ?)',
        { data.x, data.y, data.z, data.heading or 0.0, data.radius or 1.2, data.label or 'Metal Detector', data.placed_by },
        function(id)
            if id then
                data.id = id
                TriggerClientEvent('qb-pedplacer:client:spawnDetector', -1, data)
                TriggerClientEvent('ox_lib:notify', src, { title = 'Ped Placer', description = 'Metal detector placed! (ID: ' .. id .. ')', type = 'success' })
            else
                TriggerClientEvent('ox_lib:notify', src, { title = 'Ped Placer', description = 'Database error.', type = 'error' })
            end
        end
    )
end)

RegisterNetEvent('qb-pedplacer:server:deleteDetector', function(detectorId)
    local src = source
    if not IsAdmin(src) then return end
    MySQL.query('DELETE FROM placed_metaldetectors WHERE id = ?', { detectorId }, function()
        TriggerClientEvent('qb-pedplacer:client:despawnDetector', -1, detectorId)
        TriggerClientEvent('ox_lib:notify', src, { title = 'Ped Placer', description = 'Metal detector #' .. detectorId .. ' deleted.', type = 'success' })
    end)
end)

RegisterNetEvent('qb-pedplacer:server:deleteAllDetectors', function()
    local src = source
    if not IsAdmin(src) then return end
    MySQL.query('DELETE FROM placed_metaldetectors', {}, function()
        TriggerClientEvent('qb-pedplacer:client:despawnAllDetectors', -1)
        TriggerClientEvent('ox_lib:notify', src, { title = 'Ped Placer', description = 'All metal detectors deleted.', type = 'success' })
    end)
end)

-- PED crud

RegisterNetEvent('qb-pedplacer:server:placePed', function(data)
    local src = source
    if not IsAdmin(src) then
        TriggerClientEvent('ox_lib:notify', src, { title = 'Ped Placer', description = 'No permission.', type = 'error' })
        return
    end

    data.placed_by = GetCitizenId(src)
    local patrolJson = data.patrol_points and json.encode(data.patrol_points) or nil

    -- Emote-held props (beer/cigar/clipboard/etc.). Accept either a Lua table
    -- (fresh placement) or an already-encoded JSON string (re-placed from a saved
    -- group) so both paths round-trip cleanly.
    local emotePropsJson
    if type(data.emote_props) == 'table' then
        emotePropsJson = json.encode(data.emote_props)
    elseif type(data.emote_props) == 'string' and data.emote_props ~= '' then
        emotePropsJson = data.emote_props
    end

    MySQL.insert(
        'INSERT INTO placed_peds (model, x, y, z, heading, scenario, weapon, invincible, frozen, label, placed_by, behavior, wander_radius, patrol_speed, patrol_points, interact_type, group_name, anim_dict, anim_name, emote_props) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        {
            data.model, data.x, data.y, data.z, data.heading,
            data.scenario or '', data.weapon or '',
            data.invincible and 1 or 0, data.frozen and 1 or 0,
            data.label or 'Custom Ped', data.placed_by,
            data.behavior or 'idle',
            data.wander_radius or Config.DefaultWanderRadius,
            data.patrol_speed or Config.DefaultPatrolSpeed,
            patrolJson,
            data.interact_type or '',
            data.group_name or '',
            data.animDict or '',
            data.animName or '',
            emotePropsJson,
        },
        function(id)
            if id then
                data.id = id
                if (data.behavior or '') == 'bartender' then
                    RegisterBartender(id, data.x, data.y, data.z)
                end
                TriggerClientEvent('qb-pedplacer:client:spawnPed', -1, data)
                TriggerClientEvent('ox_lib:notify', src, { title = 'Ped Placer', description = 'Ped placed! (ID: ' .. id .. ')', type = 'success' })
            else
                TriggerClientEvent('ox_lib:notify', src, { title = 'Ped Placer', description = 'Database error.', type = 'error' })
            end
        end
    )
end)

RegisterNetEvent('qb-pedplacer:server:deletePed', function(pedId)
    local src = source
    if not IsAdmin(src) then return end
    MySQL.query('DELETE FROM placed_peds WHERE id = ?', { pedId }, function()
        UnregisterBartender(pedId)
        TriggerClientEvent('qb-pedplacer:client:despawnPed', -1, pedId)
        TriggerClientEvent('ox_lib:notify', src, { title = 'Ped Placer', description = 'Ped #' .. pedId .. ' deleted.', type = 'success' })
    end)
end)

RegisterNetEvent('qb-pedplacer:server:deleteAllPeds', function()
    local src = source
    if not IsAdmin(src) then return end
    MySQL.query('DELETE FROM placed_peds', {}, function()
        for id in pairs(bartenderPeds) do UnregisterBartender(id) end
        TriggerClientEvent('qb-pedplacer:client:despawnAllPeds', -1)
        TriggerClientEvent('ox_lib:notify', src, { title = 'Ped Placer', description = 'All peds deleted.', type = 'success' })
    end)
end)

RegisterNetEvent('qb-pedplacer:server:updatePedPosition', function(pedId, x, y, z, heading)
    local src = source
    if not IsAdmin(src) then return end
    MySQL.query('UPDATE placed_peds SET x = ?, y = ?, z = ?, heading = ? WHERE id = ?', { x, y, z, heading, pedId }, function()
        if bartenderPeds[pedId] then RegisterBartender(pedId, x, y, z) end
        TriggerClientEvent('qb-pedplacer:client:updatePedPosition', -1, pedId, x, y, z, heading)
        TriggerClientEvent('ox_lib:notify', src, { title = 'Ped Placer', description = 'Ped #' .. pedId .. ' moved.', type = 'success' })
    end)
end)

-- group crud

-- Save nearby peds as a custom group
RegisterNetEvent('qb-pedplacer:server:saveGroup', function(name, description, pedDataList)
    local src = source
    if not IsAdmin(src) then return end

    local dataJson = json.encode(pedDataList)
    local citizenId = GetCitizenId(src)

    -- Upsert, replace if name already exists
    MySQL.query('DELETE FROM ped_groups WHERE name = ?', { name }, function()
        MySQL.insert(
            'INSERT INTO ped_groups (name, description, data, created_by) VALUES (?, ?, ?, ?)',
            { name, description or '', dataJson, citizenId },
            function(id)
                if id then
                    TriggerClientEvent('ox_lib:notify', src, { title = 'Ped Placer', description = 'Group "' .. name .. '" saved!', type = 'success' })
                end
            end
        )
    end)
end)

-- Delete a custom group
RegisterNetEvent('qb-pedplacer:server:deleteGroup', function(groupId)
    local src = source
    if not IsAdmin(src) then return end
    MySQL.query('DELETE FROM ped_groups WHERE id = ?', { groupId }, function()
        TriggerClientEvent('ox_lib:notify', src, { title = 'Ped Placer', description = 'Group deleted.', type = 'success' })
    end)
end)

-- Delete all peds belonging to a group name
RegisterNetEvent('qb-pedplacer:server:deleteGroupPeds', function(groupName)
    local src = source
    if not IsAdmin(src) then return end
    MySQL.query('SELECT id FROM placed_peds WHERE group_name = ?', { groupName }, function(results)
        if results then
            for _, row in ipairs(results) do
                UnregisterBartender(row.id)
                TriggerClientEvent('qb-pedplacer:client:despawnPed', -1, row.id)
            end
        end
        MySQL.query('DELETE FROM placed_peds WHERE group_name = ?', { groupName })
        TriggerClientEvent('ox_lib:notify', src, { title = 'Ped Placer', description = 'All peds in group "' .. groupName .. '" deleted.', type = 'success' })
    end)
end)

-- patrol points

RegisterNetEvent('qb-pedplacer:server:savePatrolPoints', function(pedId, points)
    local src = source
    if not IsAdmin(src) then return end
    local pointsJson = json.encode(points)
    MySQL.query('UPDATE placed_peds SET patrol_points = ? WHERE id = ?', { pointsJson, pedId }, function()
        TriggerClientEvent('qb-pedplacer:client:updatePatrolPoints', -1, pedId, points)
        TriggerClientEvent('ox_lib:notify', src, { title = 'Ped Placer', description = 'Patrol route saved for ped #' .. pedId, type = 'success' })
    end)
end)

-- command

RegisterCommand(Config.Command, function(source)
    local src = source
    if src == 0 then print('[qb-pedplacer] In-game only.') return end
    if not IsAdmin(src) then
        TriggerClientEvent('ox_lib:notify', src, { title = 'Ped Placer', description = 'No permission.', type = 'error' })
        return
    end
    TriggerClientEvent('qb-pedplacer:client:openMenu', src)
end, false)

ExecuteCommand('add_ace group.admin command.' .. Config.Command .. ' allow')

-- Auto-migrate: add anim columns if missing
CreateThread(function()
    Wait(5000) -- wait for DB to be ready

    -- Check if anim_dict column exists
    local cols = MySQL.query.await("SHOW COLUMNS FROM placed_peds LIKE 'anim_dict'", {})
    if not cols or #cols == 0 then
        MySQL.query.await("ALTER TABLE placed_peds ADD COLUMN anim_dict VARCHAR(200) NOT NULL DEFAULT '' AFTER group_name", {})
        MySQL.query.await("ALTER TABLE placed_peds ADD COLUMN anim_name VARCHAR(200) NOT NULL DEFAULT '' AFTER anim_dict", {})
        print('^2[qb-pedplacer]^0 Auto-migrated: added anim_dict and anim_name columns')
    end

    -- Emote-held props column (added when the scully emote bridge landed)
    local propCols = MySQL.query.await("SHOW COLUMNS FROM placed_peds LIKE 'emote_props'", {})
    if not propCols or #propCols == 0 then
        MySQL.query.await("ALTER TABLE placed_peds ADD COLUMN emote_props LONGTEXT NULL DEFAULT NULL AFTER anim_name", {})
        print('^2[qb-pedplacer]^0 Auto-migrated: added emote_props column')
    end

    -- One-time data fix: every drug/stripper "scenario" the placer originally
    -- shipped used an invalid animation dict/clip (AI-guessed, not in the game)
    -- so those placed peds silently stood idle. Each {oldDict, oldClip} below is
    -- rewritten to a dict/clip verified against the GTA V animation dump. The
    -- where clauses only match the old bad values, so this is idempotent, a
    -- no-op once a server has already been healed.
    --
    -- the coke-packer pair also covers counting-money peds that an earlier
    -- (flawed) build of this fix rewrote to that value, so they end up counting
    -- money as intended. If you placed any literal "Coke, Packing" peds, just
    -- re-place them from the menu (they'll use the corrected press-operator clip).
    local animFixes = {
        -- counting money (original + earlier-migrated value)
        { 'anim@heists@money_grab@briefcase', 'idle', 'anim@amb@business@cfm@cfm_counting_notes@', 'note_counting_v2_counter' },
        { 'anim@amb@business@coc@coc_packer_table_idles@', 'coke_idle_a_cokepacker', 'anim@amb@business@cfm@cfm_counting_notes@', 'note_counting_v2_counter' },
        -- drug handoff
        { 'anim@heists@narcotics@trash', 'drop_front', 'mp_common', 'givetake1_a' },
        -- weed
        { 'anim@amb@business@weed@weed_inspecting_lo_med_hi@', 'weed_inspecting_idle_01_inspector', 'anim@amb@business@weed@weed_inspecting_lo_med_hi@', 'weed_stand_checkingleaves_idle_01_inspector' },
        { 'anim@amb@business@weed@weed_inspecting_lo_med_hi@', 'weed_inspecting_2_inspector', 'anim@amb@business@weed@weed_inspecting_lo_med_hi@', 'weed_stand_checkingleaves_idle_02_inspector' },
        { 'anim@amb@business@weed@weed_pruning_lo_med_hi@', 'weed_pruning_2_inspector', 'anim@amb@business@weed@weed_sorting_seated@', 'sorter_left_sort_v2_chair01' },
        -- coke
        { 'anim@amb@business@coc@coc_unpack_cut_left_table@', 'coc_unpack_cut_idle_a_cokecutter', 'anim@amb@business@coc@coc_unpack_cut_left@', 'coke_cut_v1_coccutter' },
        { 'anim@amb@business@bgen@bgen_no_work@', 'idle_b', 'anim@amb@business@bgen@bgen_no_work@', 'stand_phone_idle_01_nowork' },
        -- meth
        { 'anim@amb@business@meth@meth_unloadingbags@', 'unloading_bags_idle_b_meth_cooker', 'anim@amb@business@meth@meth_monitoring_cooking@cooking@', 'base_idle_tank_cooker' },
        { 'anim@amb@business@meth@meth_unloadingbags@', 'unloading_bags_idle_a_meth_cooker', 'anim@amb@business@meth@meth_monitoring_no_work@', 'base_lazycook' },
        -- weighing/grinding -> cash press operator
        { 'anim@amb@business@cfm@cfm_machine_idles@', 'weigh_and_grind_idle_b_worker', 'anim@amb@business@cfm@cfm_machine_no_work@', 'hanging_out_operator' },
        -- gang hangout (finale -> funding)
        { 'anim@heists@narcotics@finale@gang_idle', 'gang_chatting_idle01', 'anim@heists@narcotics@funding@gang_idle', 'gang_chatting_idle01' },
        -- stripper pole dances (clip name was 'pole_dance' for all three)
        { 'mini@strip_club@pole_dance@pole_dance1', 'pole_dance', 'mini@strip_club@pole_dance@pole_dance1', 'pd_dance_01' },
        { 'mini@strip_club@pole_dance@pole_dance2', 'pole_dance', 'mini@strip_club@pole_dance@pole_dance2', 'pd_dance_02' },
        { 'mini@strip_club@pole_dance@pole_dance3', 'pole_dance', 'mini@strip_club@pole_dance@pole_dance3', 'pd_dance_03' },
        -- stripper lap dance (needs gendered clip suffix)
        { 'mini@strip_club@lap_dance@ld_girl_a_song_a_p1', 'ld_girl_a_song_a_p1', 'mini@strip_club@lap_dance@ld_girl_a_song_a_p1', 'ld_girl_a_song_a_p1_f' },
    }
    local totalFixed = 0
    for _, f in ipairs(animFixes) do
        local n = MySQL.update.await(
            'UPDATE placed_peds SET anim_dict = ?, anim_name = ? WHERE anim_dict = ? AND anim_name = ?',
            { f[3], f[4], f[1], f[2] })
        totalFixed = totalFixed + (n or 0)
    end
    -- "Gang, Idle w/ Gun" had no valid anim at all; convert those peds to a
    -- guard-stand scenario (pair with a weapon in-game for the armed-lookout look).
    local gunFixed = MySQL.update.await(
        "UPDATE placed_peds SET scenario = 'WORLD_HUMAN_GUARD_STAND', anim_dict = '', anim_name = '' WHERE anim_dict = 'anim@amb@business@bgen@bgen_idle@' AND anim_name = 'idle_a_drugs_gun'",
        {})
    totalFixed = totalFixed + (gunFixed or 0)
    if totalFixed > 0 then
        print(('^2[qb-pedplacer]^0 Healed %s placed ped(s) that were using invalid animations.'):format(tostring(totalFixed)))
    end

    -- Auto-create placed_radios table
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `placed_radios` (
            `id`            INT(11)       NOT NULL AUTO_INCREMENT,
            `model`         VARCHAR(100)  NOT NULL,
            `station`       VARCHAR(100)  NOT NULL DEFAULT 'RADIO_01_CLASS_ROCK',
            `x`             FLOAT         NOT NULL,
            `y`             FLOAT         NOT NULL,
            `z`             FLOAT         NOT NULL,
            `heading`       FLOAT         NOT NULL DEFAULT 0.0,
            `label`         VARCHAR(100)  NOT NULL DEFAULT 'Radio',
            `placed_by`     VARCHAR(100)  NOT NULL DEFAULT 'unknown',
            `created_at`    TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]], {})

    -- Auto-create placed_metaldetectors table
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `placed_metaldetectors` (
            `id`            INT(11)       NOT NULL AUTO_INCREMENT,
            `x`             FLOAT         NOT NULL,
            `y`             FLOAT         NOT NULL,
            `z`             FLOAT         NOT NULL,
            `heading`       FLOAT         NOT NULL DEFAULT 0.0,
            `radius`        FLOAT         NOT NULL DEFAULT 1.2,
            `label`         VARCHAR(100)  NOT NULL DEFAULT 'Metal Detector',
            `placed_by`     VARCHAR(100)  NOT NULL DEFAULT 'unknown',
            `created_at`    TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]], {})

    local result = MySQL.query.await('SELECT COUNT(*) as cnt FROM placed_peds', {})
    local count = result and result[1] and result[1].cnt or 0
    local radioResult = MySQL.query.await('SELECT COUNT(*) as cnt FROM placed_radios', {})
    local radioCount = radioResult and radioResult[1] and radioResult[1].cnt or 0
    local detResult = MySQL.query.await('SELECT COUNT(*) as cnt FROM placed_metaldetectors', {})
    local detCount = detResult and detResult[1] and detResult[1].cnt or 0
    print('^2[qb-pedplacer]^0 Server loaded - /' .. Config.Command .. ' - ' .. count .. ' peds, ' .. radioCount .. ' radios, ' .. detCount .. ' metal detectors in database')

    -- Register existing bartender peds with rr-bartender (wait for it to start)
    local waited = 0
    while not rrBartenderReady() and waited < 30000 do
        Wait(1000)
        waited = waited + 1000
    end
    if rrBartenderReady() then RegisterAllBartenders() end
end)
