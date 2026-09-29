Config = {}

-- Command to open the ped placer menu (admin only)
Config.Command = 'pedplacer'

-- QBCore permission group required (e.g. 'admin', 'god', 'mod')
Config.RequiredPermission = 'admin'

-- persistence mode
-- When true, a placed ped is spawned the first time you come within range and
-- then kept loaded for the rest of the session, it is never despawned just
-- because you walked away. This fixes the "peds in some MLOs don't load (or load
-- wrong) until I reset the resource" problem: the ped is created once, while
-- you're there and the interior is fully streamed in, and then it simply stays.
-- If the engine ever culls it, the script notices the next tick and recreates
-- it automatically, no resource reset needed.
--
-- (Peds are only ever spawned when you're nearby, never blindly across the whole
-- map, so an unstreamed area can never spawn a broken/falling ped.)
--
-- The real limit here is not your RAM, it's GTA's PED pool, a hard engine
-- cap (~256 peds) shared with every ambient NPC. Permanent mode is fine for a
-- few dozen placed peds. If you roam the whole map they accumulate as loaded
-- peds; if you ever hit the cap, set this back to false to stream them instead.
-- this server has ~1,100 placed peds, which is far more than GTA's ped
-- pool (~256, shared with ambient NPCs) can hold at once. So this must stay
-- false, peds stream in/out by distance to stay under the cap. The "peds in
-- MLOs vanish until I reset" bug is fixed separately by the auto-respawn
-- (cull-detection) in StreamPeds, which works in this streaming mode too.
-- Only flip this to true if you ever cut down to a few dozen total peds.
Config.PermanentPeds = false

-- Render distance for spawned peds (in units), how close you must get for a ped
-- to spawn. In PermanentPeds mode it then stays loaded; in streaming mode
-- (PermanentPeds = false) it despawns again once you pass back beyond this.
-- 80 -> 350 (load early, no pop-in) -> 100 (2026-08-05).
-- 350 was too far: scenario/wander peds spawn unfrozen so gravity can settle
-- them, and at 350 units they were being created out in unloaded space with no
-- collision and no navmesh under them. They then physics-settled and their
-- scenario task re-anchored to whatever facing it could find, so peds you had
-- placed perfectly were rotated (often a full 180) by the time you walked up
-- the "my peds are backwards after a restart" bug. 100 keeps them inside loaded
-- world space while still spawning them well before they're visible.
Config.RenderDistance = 100.0

-- How often (ms) to check player distance for streaming peds in/out
-- Lowered from 5000 -> 1000 so the loop catches you entering the radius
-- almost immediately instead of up to 5 seconds after.
Config.StreamCheckInterval = 1000

-- Whether placed peds are invincible by default
Config.Invincible = true

-- Whether placed peds are frozen (stationary) by default
Config.Frozen = true

-- Block ped from fleeing / reacting to events by default
Config.BlockEvents = true

-- behavior types
--  idle     = stands still (legacy)
--  scenario = plays a GTA scenario animation
--  patrol   = walks between waypoints you define
--  wander   = roams freely within a radius
--  interact = pairs with nearby peds (chat, dance, argue, etc.)
Config.BehaviorTypes = {
    { label = 'Idle (Stand Still)',      value = 'idle' },
    { label = 'Play Scenario',           value = 'scenario' },
    { label = 'Patrol Route',            value = 'patrol' },
    { label = 'Wander in Area',          value = 'wander' },
    { label = 'Interact with Nearby',    value = 'interact' },
    { label = 'Bartender (Serves Drinks)', value = 'bartender' }, -- requires rr-bartender
}

-- Default patrol walk speed: 1.0 = walk, 2.0 = run
Config.DefaultPatrolSpeed = 1.0

-- Default wander radius (units)
Config.DefaultWanderRadius = 15.0

-- Wander min/max wait time (seconds) between moves
Config.WanderMinWait = 3
Config.WanderMaxWait = 10

--  interaction animations  (ped-to-ped behaviors)
Config.Interactions = {
    { label = 'Conversation',            scenario = 'WORLD_HUMAN_STAND_IMPATIENT' },
    { label = 'Argue',                   scenario = 'WORLD_HUMAN_HANG_OUT_STREET' },
    { label = 'Dancing Together',        scenario = 'WORLD_HUMAN_PARTYING' },
    { label = 'Cheering',               scenario = 'WORLD_HUMAN_CHEERING' },
    { label = 'Drinking Together',       scenario = 'WORLD_HUMAN_DRINKING' },
    { label = 'Strip Watch',            scenario = 'WORLD_HUMAN_STRIP_WATCH_STAND' },
    { label = 'Musician & Audience',    scenario = 'WORLD_HUMAN_MUSICIAN' },
}

--  casino dealer (blackjack) integration
--  When a casino dealer is placed AT a blackjack table it snaps to that
--  table and registers a playable dealer with the casino engine. No table
--  in range -> a normal decorative dealer ped is placed instead.
Config.CasinoPlacer = 'rr-casino-placer'   -- resource that owns the playable-dealer registry
Config.CasinoSnapRadius = 3.5               -- how close (m) to a table prop counts as "at the table"
Config.CasinoTableModels = {
    'vw_prop_casino_blckjack_01', 'vw_prop_casino_blckjack_01b',
    'vw_prop_casino_3cardpoker_01', 'vw_prop_casino_3cardpoker_01b',
    'h4_prop_casino_3cardpoker_01a', 'h4_prop_casino_3cardpoker_01b',
    'h4_prop_casino_3cardpoker_01c', 'h4_prop_casino_3cardpoker_01e',
}

--  add-ON PEDS
-- Add-on ("streamed gfx") peds ship their body parts as loose ^component .ydd
-- files plus a .ymt listing the variations. Some add-on ymts never get a
-- variation auto-applied on CreatePed, so the ped spawns with NO geometry, it
-- exists, it's solid, it blocks bullets, you just can't see it. That looks
-- exactly like "the placer did nothing". Listing a model here makes the placer
-- force component drawable 0 / texture 0 on it right after spawning.
--
-- Vanilla peds must stay out of this list. Forcing drawable 0 on them would
-- strip their random clothing roll and make every copy of a model identical.
Config.AddonPeds = {
    ['k9_retriever'] = true,   -- Police K9, retriever_k9 in resources/[assets]
}

-- preset categories
Config.Presets = {
    {
        label = '🎰 Casino',
        models = {
            { label = 'Blackjack Dealer (Female)', model = 's_f_y_casino_01' },
            { label = 'Blackjack Dealer (Male)',   model = 's_m_y_casino_01' },
        },
    },
    {
        label = '👮 Police',
        models = {
            { label = 'LSPD Male',          model = 's_m_y_cop_01' },
            { label = 'LSPD Female',        model = 's_f_y_cop_01' },
            { label = 'Highway Patrol',     model = 's_m_y_hwaycop_01' },
            { label = 'Sheriff Male',       model = 's_m_y_sheriff_01' },
            { label = 'Sheriff Female',     model = 's_f_y_sheriff_01' },
            { label = 'SWAT',              model = 's_m_y_swat_01' },
            { label = 'Ranger',            model = 's_m_y_ranger_01' },
            { label = 'Prison Guard',      model = 's_m_y_prison_01' },
            { label = 'FIB Male',          model = 's_m_m_fibsec_01' },
            { label = 'FIB Suit',          model = 's_m_m_fiboffice_01' },
            { label = 'FIB Suit 2',        model = 's_m_m_fiboffice_02' },
            { label = 'Detective (Beta)',   model = 'ig_mrs_thornhill' },
            { label = 'Prisoner Male',      model = 's_m_y_prisoner_01' },
            { label = 'Prisoner Muscle',    model = 's_m_y_prismuscl_01' },
            { label = 'Old Sheriff',        model = 's_m_m_ciasec_01' },
            { label = 'Cop (DLC)',          model = 'mp_m_freemode_01' },
            { label = 'Federal Agent',      model = 's_m_m_ciasec_01' },
        },
    },
    {
        label = '🛡️ Security / Guards',
        models = {
            { label = 'Security Guard',     model = 's_m_m_security_01' },
            { label = 'Bouncer',           model = 's_m_m_bouncer_01' },
            { label = 'Armored Guard',     model = 's_m_m_armoured_01' },
            { label = 'Armored Guard 2',   model = 's_m_m_armoured_02' },
            { label = 'High Security',     model = 's_m_m_highsec_01' },
            { label = 'High Security 2',   model = 's_m_m_highsec_02' },
            { label = 'Gaffer',            model = 's_m_m_gaffer_01' },
            { label = 'Gardener',          model = 's_m_m_gardener_01' },
            { label = 'Marine',            model = 's_m_m_marine_01' },
            { label = 'Marine 2',          model = 's_m_m_marine_02' },
            { label = 'Pilot',            model = 's_m_m_pilot_02' },
        },
    },
    {
        label = '🏥 Medical / Fire',
        models = {
            { label = 'Paramedic',          model = 's_m_m_paramedic_01' },
            { label = 'Doctor',            model = 's_m_m_doctor_01' },
            { label = 'Scientist',         model = 's_m_m_scientist_01' },
            { label = 'Scientist 2',       model = 's_m_y_scientist_01' },
            { label = 'Firefighter',       model = 's_m_y_fireman_01' },
            { label = 'Nurse',             model = 's_f_y_scrubs_01' },
            { label = 'Construction Medic',model = 's_m_y_construct_01' },
            { label = 'Dentist',           model = 's_m_m_doctor_01' },
        },
    },
    {
        label = '🧑‍🌾 Farmers / Rural',
        models = {
            { label = 'Farmer',             model = 'a_m_m_farmer_01' },
            { label = 'Farm Hand',          model = 'a_m_m_rurmeth_01' },
            { label = 'Redneck',            model = 'a_m_y_sunbathe_01' },
            { label = 'Hillbilly Male',     model = 'a_m_m_hillbilly_01' },
            { label = 'Hillbilly Male 2',   model = 'a_m_m_hillbilly_02' },
            { label = 'Rancher Male',       model = 's_m_m_cntrybar_01' },
            { label = 'Country Woman',      model = 'a_f_y_rurmeth_01' },
            { label = 'Trucker',            model = 's_m_m_trucker_01' },
        },
    },
    {
        label = '⛱️ Beach / Lifeguards',
        models = {
            { label = 'Lifeguard Male',     model = 's_m_y_baywatch_01' },
            { label = 'Lifeguard Female',   model = 's_f_y_baywatch_01' },
            { label = 'Beach Guy 1',        model = 'a_m_y_beach_01' },
            { label = 'Beach Guy 2',        model = 'a_m_y_beach_02' },
            { label = 'Beach Guy 3',        model = 'a_m_y_beach_03' },
            { label = 'Beach Girl 1',       model = 'a_f_y_beach_01' },
            { label = 'Muscle Beach',       model = 'a_m_m_beach_02' },
            { label = 'Surfer',             model = 'a_m_y_surfer_01' },
            { label = 'Sunbather M',        model = 'a_m_y_sunbathe_01' },
        },
    },
    {
        label = '🏖️ Beach Party',
        models = {
            { label = 'Bikini Girl',        model = 'a_f_y_topless_01' },
            { label = 'Beach Babe',         model = 'a_f_y_beach_01' },
            { label = 'Beach Woman',        model = 'a_f_m_beach_01' },
            { label = 'Party Guy 1',        model = 'a_m_y_beach_01' },
            { label = 'Party Guy 2',        model = 'a_m_y_beach_02' },
            { label = 'Party Guy 3',        model = 'a_m_y_beach_03' },
            { label = 'Beach Bro 1',        model = 'a_m_m_beach_01' },
            { label = 'Beach Bro 2',        model = 'a_m_m_beach_02' },
            { label = 'Old Beach Guy',      model = 'a_m_o_beach_01' },
            { label = 'Vespucci Local 1',   model = 'a_m_y_beachvesp_01' },
            { label = 'Vespucci Local 2',   model = 'a_m_y_beachvesp_02' },
            { label = 'Muscle Beach 1',     model = 'a_m_y_musclbeac_01' },
            { label = 'Muscle Beach 2',     model = 'a_m_y_musclbeac_02' },
            { label = 'Surfer Dude',        model = 'a_m_y_surfer_01' },
            { label = 'Hippie Girl',        model = 'a_f_y_hippie_01' },
            { label = 'Hippie Guy',         model = 'a_m_y_hippy_01' },
            { label = 'Raver Girl',         model = 'a_f_y_juggalo_01' },
            { label = 'Raver Guy',          model = 'a_m_y_juggalo_01' },
            { label = 'Club Girl 1',        model = 'a_f_y_clubcust_01' },
            { label = 'Club Girl 2',        model = 'a_f_y_clubcust_02' },
            { label = 'Club Girl 3',        model = 'a_f_y_clubcust_03' },
            { label = 'Club Guy 1',         model = 'a_m_y_clubcust_01' },
            { label = 'Club Guy 2',         model = 'a_m_y_clubcust_02' },
            { label = 'Club Guy 3',         model = 'a_m_y_clubcust_03' },
            { label = 'DJ Blamadon',        model = 'ig_djblamadon' },
            { label = 'Beach Bartender',    model = 's_f_y_bartender_01' },
        },
    },
    {
        label = '💃 Entertainers',
        models = {
            { label = 'Stripper 1',         model = 's_f_y_stripper_01' },
            { label = 'Stripper 2',         model = 's_f_y_stripper_02' },
            { label = 'Stripper Lite',      model = 'csb_stripper_01' },
            { label = 'Stripper Lite 2',    model = 'csb_stripper_02' },
            { label = 'Pole Dancer',        model = 'a_f_y_topless_01' },
            { label = 'Hooker 1',          model = 's_f_y_hooker_01' },
            { label = 'Hooker 2',          model = 's_f_y_hooker_02' },
            { label = 'Hooker 3',          model = 's_f_y_hooker_03' },
            { label = 'Bartender',         model = 's_f_y_bartender_01' },
            { label = 'Baywatch Female',   model = 's_f_y_baywatch_01' },
        },
    },
    {
        label = '🏪 Shopkeepers / Workers',
        models = {
            { label = 'Shopkeeper Male',    model = 'mp_m_shopkeep_01' },
            { label = 'Mechanic 1',        model = 's_m_m_autoshop_01' },
            { label = 'Mechanic 2',        model = 's_m_y_mechanic_02' },
            { label = 'Barber',            model = 's_m_m_hairdress_01' },
            { label = 'Chef',             model = 's_m_y_chef_01' },
            { label = 'Valet',            model = 's_m_y_valet_01' },
            { label = 'Tattoo Artist',    model = 'u_m_y_tattoo_01' },
            { label = 'Dealer',           model = 's_m_y_dealer_01' },
            { label = 'Auto Shop',        model = 's_m_y_autopsy_01' },
            { label = 'Busboy 1',         model = 's_m_y_busboy_01' },
            { label = 'Construction 1',   model = 's_m_y_construct_01' },
            { label = 'Construction 2',   model = 's_m_y_construct_02' },
            { label = 'Dock Worker 1',    model = 's_m_y_dockwork_01' },
            { label = 'Dock Worker 2',    model = 's_m_m_dockwork_01' },
            { label = 'Factory Worker',   model = 's_m_y_factory_01' },
            { label = 'Farmer',           model = 's_m_m_cntrybar_01' },
            { label = 'Garbage Man',      model = 's_m_y_garbage' },
            { label = 'Janitor',          model = 's_m_y_xmech_01' },
            { label = 'Waiter',           model = 's_m_y_waiter_01' },
            { label = 'Courier',          model = 's_m_m_postal_01' },
            { label = 'Postal 2',         model = 's_m_m_postal_02' },
            { label = 'Cable Guy',        model = 's_m_m_linecook' },
            { label = 'Gas Station Attn', model = 'mp_m_waremech_01' },
            { label = 'Movers Male',      model = 's_m_m_movalien_01' },
            { label = 'Car Wash',         model = 's_m_y_airworker' },
        },
    },
    {
        label = '💼 Business / Professionals',
        models = {
            { label = 'Business Suit M',    model = 'a_m_y_business_01' },
            { label = 'Business Suit M2',   model = 'a_m_y_business_02' },
            { label = 'Business Suit M3',   model = 'a_m_y_business_03' },
            { label = 'Business Man',       model = 'a_m_m_business_01' },
            { label = 'Business Woman 1',   model = 'a_f_y_business_01' },
            { label = 'Business Woman 2',   model = 'a_f_y_business_02' },
            { label = 'Business Woman 3',   model = 'a_f_y_business_03' },
            { label = 'Business Woman 4',   model = 'a_f_y_business_04' },
            { label = 'Lawyer',             model = 'cs_molly' },
            { label = 'Exec Male',          model = 'a_m_m_bevhills_01' },
            { label = 'Exec Female',        model = 'a_f_m_bevhills_01' },
            { label = 'Real Estate Agent',  model = 's_m_m_dockwork_01' },
            { label = 'Accountant',         model = 'ig_lester' },
        },
    },
    {
        label = '🎖️ Military',
        models = {
            { label = 'Marine',              model = 's_m_m_marine_01' },
            { label = 'Marine 2',            model = 's_m_m_marine_02' },
            { label = 'Army Soldier',        model = 's_m_y_armymech_01' },
            { label = 'Blackops Soldier',    model = 's_m_y_blackops_01' },
            { label = 'Blackops Soldier 2',  model = 's_m_y_blackops_02' },
            { label = 'Blackops Soldier 3',  model = 's_m_y_blackops_03' },
            { label = 'Military Pilot',      model = 's_m_m_pilot_02' },
            { label = 'Combat Medic',        model = 's_m_m_paramedic_01' },
            { label = 'Merc Soldier',        model = 'g_m_m_armboss_01' },
            { label = 'Merc Gunner',         model = 'g_m_m_armgoon_01' },
            { label = 'Merc Lieutenant',     model = 'g_m_m_armlieut_01' },
            { label = 'Private Security',    model = 's_m_m_highsec_01' },
            { label = 'Navy Officer',        model = 's_m_m_pilot_01' },
        },
    },
    {
        label = '👤 Civilians',
        models = {
            { label = 'Business Male',      model = 'a_m_y_business_03' },
            { label = 'Business Female',    model = 'a_f_y_business_04' },
            { label = 'Beach Male',        model = 'a_m_y_beach_03' },
            { label = 'Beach Female',      model = 'a_f_y_beach_01' },
            { label = 'Hipster Male',      model = 'a_m_y_hipster_01' },
            { label = 'Hipster Male 2',    model = 'a_m_y_hipster_02' },
            { label = 'Hipster Male 3',    model = 'a_m_y_hipster_03' },
            { label = 'Hipster Female',    model = 'a_f_y_hipster_02' },
            { label = 'Hipster Female 3',  model = 'a_f_y_hipster_03' },
            { label = 'Hipster Female 4',  model = 'a_f_y_hipster_04' },
            { label = 'Jogger Female',     model = 'a_f_y_runner_01' },
            { label = 'Jogger Male',       model = 'a_m_y_runner_01' },
            { label = 'Jogger Male 2',     model = 'a_m_y_runner_02' },
            { label = 'Tourist Male',      model = 'a_m_m_tourist_01' },
            { label = 'Tourist Male 2',    model = 'a_m_m_tourist_01' },
            { label = 'Tourist Female',    model = 'a_f_y_tourist_01' },
            { label = 'Tourist Female 2',  model = 'a_f_y_tourist_02' },
            { label = 'Homeless',          model = 'a_m_m_tramp_01' },
            { label = 'Homeless 2',        model = 'a_m_y_vindouche_01' },
            { label = 'Old Man 1',         model = 'a_m_m_og_boss_01' },
            { label = 'Old Man 2',         model = 'a_m_y_stbla_01' },
            { label = 'Yoga Female',       model = 'a_f_y_yoga_01' },
            { label = 'Golfer Male',       model = 'a_m_m_golfer_01' },
            { label = 'Golfer Female',     model = 'a_f_y_golfer_01' },
            { label = 'Skater Male',       model = 'a_m_y_skater_01' },
            { label = 'Skater Female',     model = 'a_f_y_skater_01' },
            { label = 'Smart Casual Male', model = 'a_m_y_smartcaspat_01' },
            { label = 'Clubber Male',      model = 'a_m_y_clubcust_01' },
            { label = 'Clubber Female',    model = 'a_f_y_clubcust_01' },
            { label = 'Epsilon Male',      model = 'a_m_m_eastsa_02' },
            { label = 'Downtown Female',   model = 'a_f_y_femaleagent' },
            { label = 'Vinewood Male',     model = 'a_m_m_soucent_01' },
            { label = 'Vinewood Female',   model = 'a_f_y_bevhills_02' },
            { label = 'Pregnant Female',   model = 'ig_magenta' },
        },
    },
    {
        label = '🎭 Gangs',
        models = {
            { label = 'Ballas Male 1',      model = 'g_m_y_ballaeast_01' },
            { label = 'Ballas Male 2',      model = 'g_m_y_ballaorig_01' },
            { label = 'Ballas Male 3',      model = 'g_m_y_ballasout_01' },
            { label = 'Ballas Female',      model = 'csb_ballasog' },
            { label = 'Families Male 1',    model = 'g_m_y_famca_01' },
            { label = 'Families Male 2',    model = 'g_m_y_famdnf_01' },
            { label = 'Families Male 3',    model = 'g_m_y_famfor_01' },
            { label = 'Vagos Male 1',       model = 'g_m_y_mexgoon_01' },
            { label = 'Vagos Male 2',       model = 'g_m_y_mexgoon_02' },
            { label = 'Vagos Male 3',       model = 'g_m_y_mexgoon_03' },
            { label = 'Vagos Biker',        model = 'g_m_y_mexgang_01' },
            { label = 'Lost MC 1',          model = 'g_m_y_lost_01' },
            { label = 'Lost MC 2',          model = 'g_m_y_lost_02' },
            { label = 'Lost MC 3',          model = 'g_m_y_lost_03' },
            { label = 'Lost MC Female',     model = 'g_f_y_lost_01' },
            { label = 'Ballas Female',      model = 'g_f_y_ballas_01' },
            { label = 'Families Female',    model = 'g_f_y_families_01' },
            { label = 'Families MP Male',   model = 'mp_m_famdd_01' },
            { label = 'Families Homie 1',   model = 'a_m_y_stbla_01' },
            { label = 'Families Homie 2',   model = 'a_m_y_stbla_02' },
            { label = 'Lamar Davis',        model = 'ig_lamardavis' },
            { label = 'Stretch',            model = 'ig_stretch' },
            { label = 'Vagos Female',       model = 'g_f_y_vagos_01' },
            { label = 'Import/Export F',    model = 'g_f_importexport_01' },
            { label = 'Undead Mage F',      model = 'g_f_m_undeadmage' },
            { label = 'Salva Goon 1',       model = 'g_m_y_salvagoon_01' },
            { label = 'Salva Goon 2',       model = 'g_m_y_salvagoon_02' },
            { label = 'Salva Goon 3',       model = 'g_m_y_salvagoon_03' },
            { label = 'Korean Gang 1',      model = 'g_m_m_korboss_01' },
            { label = 'Korean Gang 2',      model = 'g_m_y_korean_01' },
            { label = 'Korean Gang 3',      model = 'g_m_y_korean_02' },
            { label = 'Chinese Goon 1',     model = 'g_m_m_chigoon_01' },
            { label = 'Chinese Goon 2',     model = 'g_m_m_chigoon_02' },
            { label = 'Chinese Boss',       model = 'g_m_m_chiboss_01' },
            { label = 'Azteca 1',           model = 'g_m_y_azteca_01' },
            { label = 'Pole Gang',          model = 'g_m_y_pologoon_01' },
            { label = 'Street Punk 1',      model = 'g_m_y_strpunk_01' },
            { label = 'Street Punk 2',      model = 'g_m_y_strpunk_02' },
            { label = 'Cult Leader',        model = 'g_m_m_mexboss_01' },
            { label = 'Biker Gang Male',    model = 'g_m_m_prolsec_01' },
        },
    },
    {
        label = '💊 Drug / Criminal',
        models = {
            { label = 'Drug Dealer',        model = 's_m_y_dealer_01' },
            { label = 'Street Dealer',      model = 'g_m_y_mexgoon_02' },
            { label = 'Meth Cook M',        model = 'a_m_m_rurmeth_01' },
            { label = 'Meth Cook F',        model = 'a_f_y_rurmeth_01' },
            { label = 'Junkie M',           model = 'a_m_m_tramp_01' },
            { label = 'Junkie F',           model = 'a_f_m_tramp_01' },
            { label = 'Cartel Boss',        model = 'g_m_m_mexboss_01' },
            { label = 'Cartel Boss 2',      model = 'g_m_m_mexboss_02' },
            { label = 'Armenian Goon 1',    model = 'g_m_m_armgoon_01' },
            { label = 'Armenian Goon 2',    model = 'g_m_y_armgoon_02' },
            { label = 'Armenian Boss',      model = 'g_m_m_armboss_01' },
            { label = 'Armenian Lieut',     model = 'g_m_m_armlieut_01' },
            { label = 'Mafia Hitman',       model = 'g_m_m_mafia_01' },
            { label = 'Russian Hooligan',   model = 'csb_russiandrunk' },
        },
    },
    {
        label = '🦹 Unique / Story Characters',
        models = {
            { label = 'Michael',            model = 'player_zero' },
            { label = 'Franklin',           model = 'player_one' },
            { label = 'Trevor',             model = 'player_two' },
            { label = 'Lamar',              model = 'ig_lamardavis' },
            { label = 'Lester',             model = 'ig_lester' },
            { label = 'Jimmy',              model = 'ig_jimmydisanto' },
            { label = 'Tracey',             model = 'ig_tracydisanto' },
            { label = 'Amanda',             model = 'ig_amandatownley' },
            { label = 'Tonya',              model = 'ig_tonya' },
            { label = 'Stretch',            model = 'ig_stretch' },
            { label = 'Wade',               model = 'ig_wade' },
            { label = 'Ron',                model = 'ig_ron' },
            { label = 'Dave Norton',        model = 'ig_davenorton' },
            { label = 'Steve Haines',       model = 'ig_stevehains' },
            { label = 'Devin Weston',       model = 'ig_devin' },
            { label = 'Simeon',             model = 'ig_siemonyetarian' },
            { label = 'Solomon Richards',   model = 'ig_solomon' },
            { label = 'Dr Friedlander',     model = 'ig_drfriedlander' },
            { label = 'Impotent Rage',      model = 'u_m_y_imporage' },
        },
    },
    {
        label = '🧜 Animals',
        models = {
            { label = 'Police K9 (Retriever)', model = 'k9_retriever' },
            { label = 'Rottweiler',         model = 'a_c_rottweiler' },
            { label = 'Husky',              model = 'a_c_husky' },
            { label = 'Retriever',          model = 'a_c_retriever' },
            { label = 'Poodle',             model = 'a_c_poodle' },
            { label = 'Pug',                model = 'a_c_pug' },
            { label = 'Chop (Dog)',         model = 'a_c_chop' },
            { label = 'Cat',                model = 'a_c_cat_01' },
            { label = 'Chicken Hawk',       model = 'a_c_chickenhawk' },
            { label = 'Crow',               model = 'a_c_crow' },
            { label = 'Seagull',            model = 'a_c_seagull' },
            { label = 'Horse',              model = 'a_c_horse' },
            { label = 'Cow',                model = 'a_c_cow' },
            { label = 'Pig',                model = 'a_c_pig' },
            { label = 'Deer',               model = 'a_c_deer' },
            { label = 'Boar',               model = 'a_c_boar' },
            { label = 'Coyote',             model = 'a_c_coyote' },
            { label = 'Mountain Lion',      model = 'a_c_mtlion' },
            { label = 'Rabbit',             model = 'a_c_rabbit_01' },
            { label = 'Rat',                model = 'a_c_rat' },
            { label = 'Shark',              model = 'a_c_sharktiger' },
            { label = 'Dolphin',            model = 'a_c_dolphin' },
            { label = 'Killer Whale',       model = 'a_c_killerwhale' },
        },
    },
}

--  scenario list  (GTA V ambient animations)
-- All scenarios below are verified from GTA V's pedscenarios.meta.
-- Only scenarios that start cleanly with TaskStartScenarioInPlace (no
-- surface-alignment required) are included.
Config.Scenarios = {
    { label = 'None (Idle)',                scenario = '' },

    -- guard / law enforcement
    { label = 'Guard - Stand',             scenario = 'WORLD_HUMAN_GUARD_STAND' },
    { label = 'Guard - Patrol',            scenario = 'WORLD_HUMAN_GUARD_PATROL' },
    { label = 'Guard - Stand (Army)',      scenario = 'WORLD_HUMAN_GUARD_STAND_ARMY' },
    { label = 'Cop - Idle',                scenario = 'WORLD_HUMAN_COP_IDLES' },
    { label = 'Clipboard',                 scenario = 'WORLD_HUMAN_CLIPBOARD' },
    { label = 'Stand - Impatient',         scenario = 'WORLD_HUMAN_STAND_IMPATIENT' },

    -- smoking / drinking
    { label = 'Smoking',                   scenario = 'WORLD_HUMAN_SMOKING' },
    { label = 'Smoking - Pot',             scenario = 'WORLD_HUMAN_SMOKING_POT' },
    { label = 'Smoking - Aggressive',      scenario = 'WORLD_HUMAN_AA_SMOKE' },
    { label = 'Drinking Coffee',           scenario = 'WORLD_HUMAN_DRINKING' },
    { label = 'Drinking - Aggressive',     scenario = 'WORLD_HUMAN_AA_COFFEE' },

    -- sitting (prop-spawning, no floating)
    -- These scenarios spawn their own bench/chair/etc. No external prop required.
    { label = '🪑 Sit on Bench (w/ bench)', scenario = 'PROP_HUMAN_SEAT_BENCH' },
    { label = '🪑 Sit on Chair',            scenario = 'PROP_HUMAN_SEAT_CHAIR' },
    { label = '🪑 Sit on Office Chair',     scenario = 'PROP_HUMAN_SEAT_CHAIR_MP_PLAYER' },
    { label = '🪑 Sit at Computer',         scenario = 'PROP_HUMAN_SEAT_COMPUTER' },
    { label = '🪑 Sit on Deck Chair',       scenario = 'PROP_HUMAN_SEAT_DECKCHAIR' },
    { label = '🪑 Sunlounger',              scenario = 'PROP_HUMAN_SEAT_SUNLOUNGER' },
    { label = '🪑 Sit at Bus Stop',         scenario = 'PROP_HUMAN_SEAT_BUS_STOP_WAIT' },
    { label = '🪑 Sit at Strip Club',       scenario = 'PROP_HUMAN_SEAT_STRIP_WATCH' },
    { label = '🏋️ Chin-Ups Bar',             scenario = 'PROP_HUMAN_MUSCLE_CHIN_UPS' },

    -- standing / casual
    { label = 'Leaning on Wall',           scenario = 'WORLD_HUMAN_LEANING' },
    { label = 'Stand with Phone',          scenario = 'WORLD_HUMAN_STAND_MOBILE' },
    { label = 'Tourist Map',               scenario = 'WORLD_HUMAN_TOURIST_MAP' },
    { label = 'Binoculars',                scenario = 'WORLD_HUMAN_BINOCULARS' },
    { label = 'Window Shop',               scenario = 'WORLD_HUMAN_WINDOW_SHOP_BROWSE' },
    { label = 'Hiker',                     scenario = 'WORLD_HUMAN_HIKER' },

    -- fitness
    { label = 'Pushups',                   scenario = 'WORLD_HUMAN_PUSH_UPS' },
    { label = 'Situps',                    scenario = 'WORLD_HUMAN_SIT_UPS' },
    { label = 'Yoga',                      scenario = 'WORLD_HUMAN_YOGA' },
    { label = 'Muscle Flex',               scenario = 'WORLD_HUMAN_MUSCLE_FLEX' },
    { label = 'Muscle Free Weights',       scenario = 'WORLD_HUMAN_MUSCLE_FREE_WEIGHTS' },
    { label = 'Jogging (in place)',        scenario = 'WORLD_HUMAN_JOG_STANDING' },

    -- work scenarios
    { label = 'Fishing',                   scenario = 'WORLD_HUMAN_STAND_FISHING' },
    { label = 'Hammering',                 scenario = 'WORLD_HUMAN_HAMMERING' },
    { label = 'Welding',                   scenario = 'WORLD_HUMAN_WELDING' },
    { label = 'Janitor',                   scenario = 'WORLD_HUMAN_JANITOR' },
    { label = 'Maid - Clean',              scenario = 'WORLD_HUMAN_MAID_CLEAN' },
    { label = 'Gardener - Leaf Blower',    scenario = 'WORLD_HUMAN_GARDENER_LEAF_BLOWER' },
    { label = 'Gardener - Plant Seed',     scenario = 'WORLD_HUMAN_GARDENER_PLANT' },
    { label = 'Construction Drill',        scenario = 'WORLD_HUMAN_CONST_DRILL' },
    { label = 'Parking Attendant',         scenario = 'WORLD_HUMAN_CAR_PARK_ATTENDANT' },
    { label = 'Mechanic - Under Car',      scenario = 'WORLD_HUMAN_VEHICLE_MECHANIC' },
    { label = 'Human Statue',              scenario = 'WORLD_HUMAN_HUMAN_STATUE' },
    { label = 'Drug Dealer',               scenario = 'WORLD_HUMAN_DRUG_DEALER' },

    -- bum / homeless
    { label = 'Bum - Standing',            scenario = 'WORLD_HUMAN_BUM_STANDING' },
    { label = 'Bum - Freeway',             scenario = 'WORLD_HUMAN_BUM_FREEWAY' },
    { label = 'Bum - Wash Window',         scenario = 'WORLD_HUMAN_BUM_WASH' },

    -- social / entertainment
    { label = 'Cheering',                  scenario = 'WORLD_HUMAN_CHEERING' },
    { label = 'Hang Out - Street',         scenario = 'WORLD_HUMAN_HANG_OUT_STREET' },
    { label = 'Partying',                  scenario = 'WORLD_HUMAN_PARTYING' },
    { label = 'Picnic',                    scenario = 'WORLD_HUMAN_PICNIC' },
    { label = 'Musician',                  scenario = 'WORLD_HUMAN_MUSICIAN' },
    { label = 'Paparazzi',                 scenario = 'WORLD_HUMAN_PAPARAZZI' },
    { label = 'Prostitute - High Class',   scenario = 'WORLD_HUMAN_PROSTITUTE_HIGH_CLASS' },
    { label = 'Prostitute - Low Class',    scenario = 'WORLD_HUMAN_PROSTITUTE_LOW_CLASS' },
    { label = 'Strip Watch Stand',         scenario = 'WORLD_HUMAN_STRIP_WATCH_STAND' },
    { label = 'Sunbathe (Back)',           scenario = 'WORLD_HUMAN_SUNBATHE' },
    { label = 'Sunbathe (Belly)',          scenario = 'WORLD_HUMAN_SUNBATHE_BACK' },

    -- stripper animations (anim dicts, not scenarios)
    { label = 'Stripper - Pole Dance 1',   scenario = '', animDict = 'mini@strip_club@pole_dance@pole_dance1', animName = 'pd_dance_01' },
    { label = 'Stripper - Pole Dance 2',   scenario = '', animDict = 'mini@strip_club@pole_dance@pole_dance2', animName = 'pd_dance_02' },
    { label = 'Stripper - Pole Dance 3',   scenario = '', animDict = 'mini@strip_club@pole_dance@pole_dance3', animName = 'pd_dance_03' },
    { label = 'Stripper - Private Dance',  scenario = '', animDict = 'mini@strip_club@private_dance@part1', animName = 'priv_dance_p1' },
    { label = 'Stripper - Private Dance 2',scenario = '', animDict = 'mini@strip_club@private_dance@part2', animName = 'priv_dance_p2' },
    { label = 'Stripper - Private Dance 3',scenario = '', animDict = 'mini@strip_club@private_dance@part3', animName = 'priv_dance_p3' },
    { label = 'Stripper - Lap Dance',      scenario = '', animDict = 'mini@strip_club@lap_dance@ld_girl_a_song_a_p1', animName = 'ld_girl_a_song_a_p1_f' },

    -- drugs / criminal enterprise
    -- Every dict + clip below was verified against the authoritative GTA V
    -- animation dump (DurtyFree/gta-v-data-dumps). The previous values for this
    -- whole block were invalid dict/clip names (AI-guessed, never in the game)
    -- which is why the peds silently stood idle. Do not "tidy" these strings.
    -- Weed
    { label = '🌿 Weed - Inspecting',       scenario = '', animDict = 'anim@amb@business@weed@weed_inspecting_lo_med_hi@', animName = 'weed_stand_checkingleaves_idle_01_inspector' },
    { label = '🌿 Weed - Inspecting 2',     scenario = '', animDict = 'anim@amb@business@weed@weed_inspecting_lo_med_hi@', animName = 'weed_stand_checkingleaves_idle_02_inspector' },
    { label = '🌿 Weed - Sorting (seated)', scenario = '', animDict = 'anim@amb@business@weed@weed_sorting_seated@', animName = 'sorter_left_sort_v2_chair01' },

    -- Cocaine
    { label = '❄️ Coke - Cutting',           scenario = '', animDict = 'anim@amb@business@coc@coc_unpack_cut_left@', animName = 'coke_cut_v1_coccutter' },
    { label = '❄️ Coke - Packing (press)',  scenario = '', animDict = 'anim@amb@business@coc@coc_packing@', animName = 'idle_v1_pressoperator' },
    { label = '❄️ Coke - Lab Worker Idle',  scenario = '', animDict = 'anim@amb@business@bgen@bgen_no_work@', animName = 'stand_phone_idle_01_nowork' },
    { label = '❄️ Coke - Phone Putdown',    scenario = '', animDict = 'anim@amb@business@bgen@bgen_no_work@', animName = 'stand_phone_phoneputdown_idle_nowork' },

    -- Meth
    { label = '🧪 Meth - Cooking',           scenario = '', animDict = 'anim@amb@business@meth@meth_monitoring_cooking@cooking@', animName = 'base_idle_tank_cooker' },
    { label = '🧪 Meth - Cook (idle)',       scenario = '', animDict = 'anim@amb@business@meth@meth_monitoring_no_work@', animName = 'base_lazycook' },

    -- Generic criminal-enterprise ops
    { label = '💵 Counting Money',           scenario = '', animDict = 'anim@amb@business@cfm@cfm_counting_notes@', animName = 'note_counting_v2_counter' },
    { label = '💵 Cash Press - Operator',    scenario = '', animDict = 'anim@amb@business@cfm@cfm_machine_no_work@', animName = 'hanging_out_operator' },
    { label = '🤝 Drug Deal - Handoff',      scenario = '', animDict = 'mp_common', animName = 'givetake1_a' },
    { label = '🚬 Drug Dealer (street)',     scenario = 'WORLD_HUMAN_DRUG_DEALER' },
    { label = '👥 Gang - Hangout Idle',      scenario = '', animDict = 'anim@heists@narcotics@funding@gang_idle', animName = 'gang_chatting_idle01' },
    { label = '🔫 Armed Lookout (Guard)',   scenario = 'WORLD_HUMAN_GUARD_STAND' }, -- give a weapon via the Weapon menu
    { label = '🙇 Hostage - Kneel/Hands',    scenario = '', animDict = 'random@arrests', animName = 'kneeling_arrest_idle' },
    { label = '🙌 Hands Up (Robbery)',       scenario = '', animDict = 'missminuteman_1ig_2', animName = 'handsup_base' },

    -- animals
    { label = 'Dog - Barking (Rottweiler)',scenario = 'WORLD_DOG_BARKING_ROTTWEILER' },
    { label = 'Dog - Barking (Retriever)', scenario = 'WORLD_DOG_BARKING_RETRIEVER' },
    { label = 'Dog - Barking (Shepherd)',  scenario = 'WORLD_DOG_BARKING_SHEPHERD' },
    { label = 'Dog - Sleeping (yard)',     scenario = 'WORLD_DOG_SLEEPING_IN_YARD' },
    { label = 'Dog - Sleeping (pavement)', scenario = 'WORLD_DOG_SLEEPING_PAVEMENT' },
    { label = 'Cat - Sleeping (ground)',   scenario = 'WORLD_CAT_SLEEPING_GROUND' },
    { label = 'Cat - Sleeping (ledge)',    scenario = 'WORLD_CAT_SLEEPING_LEDGE' },
}

--  weapons  (optional, give a ped a weapon in-hand)
Config.Weapons = {
    { label = 'None',                weapon = '' },
    { label = 'Pistol',             weapon = 'WEAPON_PISTOL' },
    { label = 'Combat Pistol',      weapon = 'WEAPON_COMBATPISTOL' },
    { label = 'SMG',                weapon = 'WEAPON_SMG' },
    { label = 'Carbine Rifle',      weapon = 'WEAPON_CARBINERIFLE' },
    { label = 'Pump Shotgun',       weapon = 'WEAPON_PUMPSHOTGUN' },
    { label = 'Nightstick',         weapon = 'WEAPON_NIGHTSTICK' },
    { label = 'Flashlight',         weapon = 'WEAPON_FLASHLIGHT' },
    { label = 'Stungun',            weapon = 'WEAPON_STUNGUN' },
    { label = 'Bat',                weapon = 'WEAPON_BAT' },
    { label = 'Knife',              weapon = 'WEAPON_KNIFE' },
    { label = 'Assault Rifle',      weapon = 'WEAPON_ASSAULTRIFLE' },
    { label = 'Advanced Rifle',     weapon = 'WEAPON_ADVANCEDRIFLE' },
    { label = 'MG',                 weapon = 'WEAPON_MG' },
    { label = 'Combat MG',          weapon = 'WEAPON_COMBATMG' },
    { label = 'Sniper Rifle',       weapon = 'WEAPON_SNIPERRIFLE' },
    { label = 'RPG',                weapon = 'WEAPON_RPG' },
    { label = 'Grenade Launcher',   weapon = 'WEAPON_GRENADELAUNCHER' },
    { label = 'Micro SMG',          weapon = 'WEAPON_MICROSMG' },
}

--  radio, speaker props + stations
-- Radio speaker prop render distance (visual only, radio audio range is
-- still controlled by the per-radio range in the closest-zone loop below).
-- Bumped 80 -> 350 to match ped render distance.
Config.RadioRenderDistance = 60.0

Config.SpeakerModels = {
    { label = 'Boombox',            model = 'prop_boombox_01' },
    { label = 'Ghetto Blaster',     model = 'prop_ghettoblast_01' },
    { label = 'Ghetto Blaster 2',   model = 'prop_ghettoblast_02' },
    { label = 'Portable HiFi',     model = 'prop_portable_hifi_01' },
    { label = 'Large Speaker',      model = 'prop_speaker_01' },
    { label = 'Speaker 2',          model = 'prop_speaker_02' },
    { label = 'Speaker 3',          model = 'prop_speaker_03' },
    { label = 'Speaker 5',          model = 'prop_speaker_05' },
    { label = 'Speaker 6',          model = 'prop_speaker_06' },
    { label = 'Speaker 7',          model = 'prop_speaker_07' },
    { label = 'Club Speaker 8',     model = 'prop_speaker_08' },
}

Config.RadioStations = {
    { label = 'Los Santos Rock Radio',      station = 'RADIO_01_CLASS_ROCK' },
    { label = 'Non-Stop-Pop FM',            station = 'RADIO_02_POP' },
    { label = 'Radio Los Santos (Hip Hop)', station = 'RADIO_03_HIPHOP_NEW' },
    { label = 'Channel X (Punk)',           station = 'RADIO_04_PUNK' },
    { label = 'West Coast Talk Radio',      station = 'RADIO_05_TALK_01' },
    { label = 'Rebel Radio (Country)',      station = 'RADIO_06_COUNTRY' },
    { label = 'Soulwax FM (Dance)',         station = 'RADIO_07_DANCE_01' },
    { label = 'East Los FM (Mexican)',      station = 'RADIO_08_MEXICAN' },
    { label = 'West Coast Classics',        station = 'RADIO_09_HIPHOP_OLD' },
    { label = 'Blaine County Radio',        station = 'RADIO_11_TALK_02' },
    { label = 'Blue Ark (Reggae)',          station = 'RADIO_12_REGGAE' },
    { label = 'WorldWide FM (Jazz)',        station = 'RADIO_13_JAZZ' },
    { label = 'FlyLo FM (Electronic)',      station = 'RADIO_14_DANCE_02' },
    { label = 'The Lowdown 91.1 (Motown)',  station = 'RADIO_15_MOTOWN' },
    { label = 'Radio Mirror Park',          station = 'RADIO_16_SILVERLAKE' },
    { label = 'Space 103.2 (Funk)',         station = 'RADIO_17_FUNK' },
    { label = 'Vinewood Boulevard Radio',   station = 'RADIO_18_90S_ROCK' },
    { label = 'The Lab',                    station = 'RADIO_20_THELAB' },
    { label = 'Blonded Los Santos',         station = 'RADIO_21_DLC_XM17' },
    { label = 'LS Underground Radio',       station = 'RADIO_22_DLC_BATTLE_MIX1_RADIO' },
}

--  metal detector, placeable archway that beeps at armed peds
-- Reuses the prop + alarm sound from the "metal-detectors" resource: the
-- model is streamed by that resource and the beep is fired through its
-- shared `DetectorAlarm` event (so other nearby players hear it too). If
-- metal-detectors is stopped, a local fallback beep is played instead.
Config.MetalDetector = {
    model       = 'ch_prop_ch_metal_detector_01a', -- streamed by the metal-detectors resource
    radius      = 1.2,    -- how close (m) a player must get before it scans
    soundRange  = 5.0,    -- how far the alarm beep can be heard
    renderDist  = 150.0,  -- prop stream-in distance
    label       = 'Metal Detector',
}

--  preset groups, pre-built formations you can place at once
Config.PresetGroups = {
    {
        label = '🏢 Police Station Crew',
        description = '8 peds - cops at desks, patrolling, guarding entrance',
        peds = {
            { model = 's_m_y_cop_01',    label = 'Desk Cop 1',       offsetX = 0.0,  offsetY = 0.0,  offsetZ = 0.0, heading = 0.0,   behavior = 'scenario', scenario = 'WORLD_HUMAN_CLIPBOARD',    weapon = '' },
            { model = 's_f_y_cop_01',    label = 'Desk Cop 2',       offsetX = 2.0,  offsetY = 0.0,  offsetZ = 0.0, heading = 180.0, behavior = 'scenario', scenario = 'WORLD_HUMAN_CLIPBOARD',    weapon = '' },
            { model = 's_m_y_cop_01',    label = 'Coffee Cop',       offsetX = 4.0,  offsetY = 2.0,  offsetZ = 0.0, heading = 90.0,  behavior = 'scenario', scenario = 'WORLD_HUMAN_DRINKING',     weapon = '' },
            { model = 's_m_y_cop_01',    label = 'Phone Cop',        offsetX = -2.0, offsetY = 3.0,  offsetZ = 0.0, heading = 270.0, behavior = 'scenario', scenario = 'WORLD_HUMAN_STAND_MOBILE', weapon = '' },
            { model = 's_m_y_cop_01',    label = 'Front Guard',      offsetX = 0.0,  offsetY = -6.0, offsetZ = 0.0, heading = 180.0, behavior = 'scenario', scenario = 'WORLD_HUMAN_GUARD_STAND',  weapon = 'WEAPON_PISTOL' },
            { model = 's_f_y_cop_01',    label = 'Front Guard 2',    offsetX = 3.0,  offsetY = -6.0, offsetZ = 0.0, heading = 180.0, behavior = 'scenario', scenario = 'WORLD_HUMAN_COP_IDLES',   weapon = '' },
            { model = 's_m_y_cop_01',    label = 'Patrol Cop 1',     offsetX = -4.0, offsetY = -3.0, offsetZ = 0.0, heading = 0.0,   behavior = 'wander',   scenario = '',                         weapon = '' },
            { model = 's_m_y_cop_01',    label = 'Patrol Cop 2',     offsetX = 5.0,  offsetY = -3.0, offsetZ = 0.0, heading = 0.0,   behavior = 'wander',   scenario = '',                         weapon = 'WEAPON_NIGHTSTICK' },
        },
    },
    {
        label = '💃 Strip Club Staff',
        description = '6 peds - strippers, bouncer, bartender',
        peds = {
            { model = 's_f_y_stripper_01', label = 'Dancer 1',     offsetX = 0.0,  offsetY = 0.0,  offsetZ = 0.0, heading = 0.0,   behavior = 'scenario', scenario = 'WORLD_HUMAN_PARTYING',                weapon = '' },
            { model = 's_f_y_stripper_02', label = 'Dancer 2',     offsetX = 2.0,  offsetY = 0.0,  offsetZ = 0.0, heading = 0.0,   behavior = 'scenario', scenario = 'WORLD_HUMAN_PARTYING',                weapon = '' },
            { model = 's_f_y_stripper_01', label = 'Stage Girl',   offsetX = 1.0,  offsetY = 2.0,  offsetZ = 0.0, heading = 180.0, behavior = 'scenario', scenario = 'WORLD_HUMAN_PROSTITUTE_HIGH_CLASS',   weapon = '' },
            { model = 's_f_y_hooker_01',   label = 'Lounge Girl',  offsetX = -3.0, offsetY = 1.0,  offsetZ = 0.0, heading = 90.0,  behavior = 'wander',   scenario = '',                                    weapon = '' },
            { model = 's_m_m_bouncer_01',  label = 'Bouncer',      offsetX = 0.0,  offsetY = -5.0, offsetZ = 0.0, heading = 180.0, behavior = 'scenario', scenario = 'WORLD_HUMAN_GUARD_STAND',             weapon = '' },
            { model = 's_f_y_bartender_01',label = 'Bartender',    offsetX = -5.0, offsetY = 0.0,  offsetZ = 0.0, heading = 0.0,   behavior = 'scenario', scenario = 'WORLD_HUMAN_DRINKING',                weapon = '' },
        },
    },
    {
        label = '🛡️ Guard Post',
        description = '4 peds - armed guards patrolling an area',
        peds = {
            { model = 's_m_m_security_01', label = 'Guard 1',       offsetX = 0.0,  offsetY = 0.0,  offsetZ = 0.0, heading = 0.0,   behavior = 'scenario', scenario = 'WORLD_HUMAN_GUARD_STAND', weapon = 'WEAPON_PISTOL' },
            { model = 's_m_m_security_01', label = 'Guard 2',       offsetX = 4.0,  offsetY = 0.0,  offsetZ = 0.0, heading = 180.0, behavior = 'scenario', scenario = 'WORLD_HUMAN_GUARD_STAND', weapon = 'WEAPON_PISTOL' },
            { model = 's_m_m_armoured_01', label = 'Patrol Guard',  offsetX = -2.0, offsetY = 3.0,  offsetZ = 0.0, heading = 0.0,   behavior = 'wander',   scenario = '',                        weapon = 'WEAPON_CARBINERIFLE' },
            { model = 's_m_m_armoured_02', label = 'Patrol Guard 2',offsetX = 6.0,  offsetY = 3.0,  offsetZ = 0.0, heading = 0.0,   behavior = 'wander',   scenario = '',                        weapon = 'WEAPON_PUMPSHOTGUN' },
        },
    },
    {
        label = '🏥 Hospital Staff',
        description = '4 peds - doctors and paramedics',
        peds = {
            { model = 's_m_m_doctor_01',    label = 'Doctor 1',     offsetX = 0.0,  offsetY = 0.0,  offsetZ = 0.0, heading = 0.0,   behavior = 'scenario', scenario = 'WORLD_HUMAN_CLIPBOARD', weapon = '' },
            { model = 's_m_m_doctor_01',    label = 'Doctor 2',     offsetX = 3.0,  offsetY = 0.0,  offsetZ = 0.0, heading = 180.0, behavior = 'interact', scenario = '',                      weapon = '' },
            { model = 's_m_m_paramedic_01', label = 'Paramedic 1',  offsetX = -2.0, offsetY = 3.0,  offsetZ = 0.0, heading = 90.0,  behavior = 'wander',   scenario = '',                      weapon = '' },
            { model = 's_m_m_paramedic_01', label = 'Paramedic 2',  offsetX = 5.0,  offsetY = 3.0,  offsetZ = 0.0, heading = 270.0, behavior = 'scenario', scenario = 'WORLD_HUMAN_SMOKING',   weapon = '' },
        },
    },
    {
        label = '🏪 Store Front',
        description = '3 peds - shopkeeper and loitering civilians',
        peds = {
            { model = 'mp_m_shopkeep_01',  label = 'Shopkeeper',    offsetX = 0.0,  offsetY = 0.0,  offsetZ = 0.0, heading = 180.0, behavior = 'scenario', scenario = 'WORLD_HUMAN_STAND_IMPATIENT', weapon = '' },
            { model = 'a_m_y_business_03', label = 'Customer 1',    offsetX = -2.0, offsetY = -3.0, offsetZ = 0.0, heading = 0.0,   behavior = 'wander',   scenario = '',                           weapon = '' },
            { model = 'a_f_y_business_04', label = 'Customer 2',    offsetX = 2.0,  offsetY = -3.0, offsetZ = 0.0, heading = 0.0,   behavior = 'scenario', scenario = 'WORLD_HUMAN_STAND_MOBILE',   weapon = '' },
        },
    },
    {
        label = '🎖️ Military Patrol Squad',
        description = '6 peds - armed soldiers patrolling and guarding (Cayo Island ready)',
        peds = {
            { model = 's_m_y_blackops_01',  label = 'Squad Leader',    offsetX = 0.0,  offsetY = 0.0,  offsetZ = 0.0, heading = 0.0,   behavior = 'scenario', scenario = 'WORLD_HUMAN_GUARD_STAND',  weapon = 'WEAPON_CARBINERIFLE' },
            { model = 's_m_y_blackops_02',  label = 'Rifleman 1',      offsetX = 3.0,  offsetY = 0.0,  offsetZ = 0.0, heading = 0.0,   behavior = 'scenario', scenario = 'WORLD_HUMAN_GUARD_STAND',  weapon = 'WEAPON_CARBINERIFLE' },
            { model = 's_m_y_blackops_03',  label = 'Rifleman 2',      offsetX = -3.0, offsetY = 0.0,  offsetZ = 0.0, heading = 180.0, behavior = 'scenario', scenario = 'WORLD_HUMAN_GUARD_PATROL', weapon = 'WEAPON_SMG' },
            { model = 's_m_m_marine_01',    label = 'Patrol 1',        offsetX = -5.0, offsetY = 3.0,  offsetZ = 0.0, heading = 0.0,   behavior = 'wander',   scenario = '',                         weapon = 'WEAPON_CARBINERIFLE' },
            { model = 's_m_m_marine_02',    label = 'Patrol 2',        offsetX = 5.0,  offsetY = 3.0,  offsetZ = 0.0, heading = 0.0,   behavior = 'wander',   scenario = '',                         weapon = 'WEAPON_PUMPSHOTGUN' },
            { model = 's_m_y_blackops_01',  label = 'Smoker',          offsetX = 2.0,  offsetY = -3.0, offsetZ = 0.0, heading = 90.0,  behavior = 'scenario', scenario = 'WORLD_HUMAN_SMOKING',      weapon = 'WEAPON_COMBATPISTOL' },
        },
    },
    {
        label = '🎖️ Military Checkpoint',
        description = '8 peds - fortified checkpoint with guards and patrols (Cayo Island ready)',
        peds = {
            { model = 's_m_y_blackops_01',  label = 'Gate Guard L',    offsetX = -2.0, offsetY = -6.0, offsetZ = 0.0, heading = 180.0, behavior = 'scenario', scenario = 'WORLD_HUMAN_GUARD_STAND',  weapon = 'WEAPON_CARBINERIFLE' },
            { model = 's_m_y_blackops_02',  label = 'Gate Guard R',    offsetX = 2.0,  offsetY = -6.0, offsetZ = 0.0, heading = 180.0, behavior = 'scenario', scenario = 'WORLD_HUMAN_GUARD_STAND',  weapon = 'WEAPON_CARBINERIFLE' },
            { model = 's_m_m_marine_01',    label = 'Tower Watch',     offsetX = 0.0,  offsetY = 0.0,  offsetZ = 0.0, heading = 0.0,   behavior = 'scenario', scenario = 'WORLD_HUMAN_GUARD_STAND',  weapon = 'WEAPON_SMG' },
            { model = 's_m_y_blackops_03',  label = 'Clipboard Check', offsetX = 0.0,  offsetY = -4.0, offsetZ = 0.0, heading = 180.0, behavior = 'scenario', scenario = 'WORLD_HUMAN_CLIPBOARD',    weapon = 'WEAPON_COMBATPISTOL' },
            { model = 's_m_m_marine_02',    label = 'Perimeter 1',     offsetX = -6.0, offsetY = 2.0,  offsetZ = 0.0, heading = 0.0,   behavior = 'wander',   scenario = '',                         weapon = 'WEAPON_CARBINERIFLE' },
            { model = 's_m_m_marine_01',    label = 'Perimeter 2',     offsetX = 6.0,  offsetY = 2.0,  offsetZ = 0.0, heading = 0.0,   behavior = 'wander',   scenario = '',                         weapon = 'WEAPON_PUMPSHOTGUN' },
            { model = 's_m_y_blackops_01',  label = 'Break Soldier',   offsetX = -4.0, offsetY = 4.0,  offsetZ = 0.0, heading = 270.0, behavior = 'scenario', scenario = 'WORLD_HUMAN_DRINKING',     weapon = '' },
            { model = 's_m_y_blackops_02',  label = 'Radio Operator',  offsetX = 4.0,  offsetY = 4.0,  offsetZ = 0.0, heading = 90.0,  behavior = 'scenario', scenario = 'WORLD_HUMAN_STAND_MOBILE', weapon = 'WEAPON_PISTOL' },
        },
    },
    {
        label = '🎉 Street Party',
        description = '6 peds - partying, dancing, drinking',
        peds = {
            { model = 'a_m_y_hipster_01',  label = 'Dancer 1',      offsetX = 0.0,  offsetY = 0.0,  offsetZ = 0.0, heading = 0.0,   behavior = 'scenario', scenario = 'WORLD_HUMAN_PARTYING',  weapon = '' },
            { model = 'a_f_y_hipster_02',  label = 'Dancer 2',      offsetX = 2.0,  offsetY = 0.0,  offsetZ = 0.0, heading = 180.0, behavior = 'scenario', scenario = 'WORLD_HUMAN_PARTYING',  weapon = '' },
            { model = 'a_m_y_beach_03',    label = 'Drinker',       offsetX = -2.0, offsetY = 2.0,  offsetZ = 0.0, heading = 90.0,  behavior = 'scenario', scenario = 'WORLD_HUMAN_DRINKING',  weapon = '' },
            { model = 'a_f_y_beach_01',    label = 'Cheerer',       offsetX = 3.0,  offsetY = 2.0,  offsetZ = 0.0, heading = 270.0, behavior = 'scenario', scenario = 'WORLD_HUMAN_CHEERING',  weapon = '' },
            { model = 'a_m_m_tourist_01',  label = 'Wanderer 1',    offsetX = -4.0, offsetY = -1.0, offsetZ = 0.0, heading = 0.0,   behavior = 'wander',   scenario = '',                      weapon = '' },
            { model = 'a_f_y_runner_01',   label = 'Wanderer 2',    offsetX = 5.0,  offsetY = -1.0, offsetZ = 0.0, heading = 0.0,   behavior = 'wander',   scenario = '',                      weapon = '' },
        },
    },
    {
        label = '🏖️ Beach Party',
        description = '16 peds - DJ, dancers, drinkers, sunbathers, muscle beach, bartender',
        peds = {
            -- DJ at the back, facing the dance floor
            { model = 'ig_djblamadon',      label = 'DJ',            offsetX = 0.0,  offsetY = 5.0,  offsetZ = 0.0, heading = 180.0, behavior = 'scenario', scenario = 'WORLD_HUMAN_MUSICIAN',       weapon = '' },
            -- Dance floor cluster
            { model = 'a_f_y_topless_01',   label = 'Bikini Dancer', offsetX = -1.5, offsetY = 2.0,  offsetZ = 0.0, heading = 0.0,   behavior = 'scenario', scenario = 'WORLD_HUMAN_PARTYING',       weapon = '' },
            { model = 'a_f_y_beach_01',     label = 'Beach Dancer',  offsetX = 0.5,  offsetY = 2.5,  offsetZ = 0.0, heading = 20.0,  behavior = 'scenario', scenario = 'WORLD_HUMAN_PARTYING',       weapon = '' },
            { model = 'a_f_y_clubcust_01',  label = 'Club Dancer',   offsetX = 2.0,  offsetY = 2.0,  offsetZ = 0.0, heading = 340.0, behavior = 'scenario', scenario = 'WORLD_HUMAN_PARTYING',       weapon = '' },
            { model = 'a_m_y_beach_01',     label = 'Party Guy 1',   offsetX = -0.8, offsetY = 0.8,  offsetZ = 0.0, heading = 180.0, behavior = 'scenario', scenario = 'WORLD_HUMAN_PARTYING',       weapon = '' },
            { model = 'a_m_y_beach_02',     label = 'Party Guy 2',   offsetX = 1.2,  offsetY = 1.0,  offsetZ = 0.0, heading = 200.0, behavior = 'scenario', scenario = 'WORLD_HUMAN_PARTYING',       weapon = '' },
            { model = 'a_m_y_juggalo_01',   label = 'Raver',         offsetX = 2.8,  offsetY = 0.5,  offsetZ = 0.0, heading = 160.0, behavior = 'scenario', scenario = 'WORLD_HUMAN_PARTYING',       weapon = '' },
            -- Hype crowd around the floor
            { model = 'a_f_y_juggalo_01',   label = 'Cheerer 1',     offsetX = -3.0, offsetY = 1.0,  offsetZ = 0.0, heading = 90.0,  behavior = 'scenario', scenario = 'WORLD_HUMAN_CHEERING',       weapon = '' },
            { model = 'a_m_y_beachvesp_01', label = 'Cheerer 2',     offsetX = 3.5,  offsetY = 1.5,  offsetZ = 0.0, heading = 270.0, behavior = 'scenario', scenario = 'WORLD_HUMAN_CHEERING',       weapon = '' },
            { model = 'a_m_m_beach_01',     label = 'Drinker 1',     offsetX = -4.0, offsetY = -1.0, offsetZ = 0.0, heading = 45.0,  behavior = 'scenario', scenario = 'WORLD_HUMAN_DRINKING',       weapon = '' },
            { model = 'a_f_y_hippie_01',    label = 'Drinker 2',     offsetX = 4.0,  offsetY = -1.0, offsetZ = 0.0, heading = 315.0, behavior = 'scenario', scenario = 'WORLD_HUMAN_DRINKING',       weapon = '' },
            -- Beach bar
            { model = 's_f_y_bartender_01', label = 'Beach Bartender', offsetX = -6.0, offsetY = 3.0, offsetZ = 0.0, heading = 90.0, behavior = 'scenario', scenario = 'WORLD_HUMAN_STAND_IMPATIENT', weapon = '' },
            -- Muscle beach showing off
            { model = 'a_m_y_musclbeac_01', label = 'Muscle Flex',   offsetX = 6.0,  offsetY = 1.0,  offsetZ = 0.0, heading = 270.0, behavior = 'scenario', scenario = 'WORLD_HUMAN_MUSCLE_FLEX',    weapon = '' },
            -- Sunbathers off to the side
            { model = 'a_m_y_beach_03',     label = 'Sunbather M',   offsetX = -3.5, offsetY = -4.5, offsetZ = 0.0, heading = 0.0,   behavior = 'scenario', scenario = 'WORLD_HUMAN_SUNBATHE',       weapon = '' },
            { model = 'a_f_m_beach_01',     label = 'Sunbather F',   offsetX = 3.5,  offsetY = -4.5, offsetZ = 0.0, heading = 0.0,   behavior = 'scenario', scenario = 'WORLD_HUMAN_SUNBATHE_BACK',  weapon = '' },
            -- Roamers keeping the scene alive
            { model = 'a_m_y_surfer_01',    label = 'Surfer',        offsetX = -5.5, offsetY = -2.5, offsetZ = 0.0, heading = 0.0,   behavior = 'wander',   scenario = '',                           weapon = '' },
        },
    },
    {
        label = '🟢 Families Gang Party',
        description = '17 peds - Families block party: dancers, hype crew, OGs, corner boy, arguing homies, armed lookouts',
        peds = {
            -- Party host at the back, facing the crowd
            { model = 'g_m_y_famca_01',     label = 'Party Host',          offsetX = 0.0,  offsetY = 5.5,  offsetZ = 0.0, heading = 180.0, behavior = 'scenario', scenario = 'WORLD_HUMAN_PARTYING',        weapon = '' },
            -- Dance floor cluster
            { model = 'g_f_y_families_01',  label = 'Families Girl 1',     offsetX = -1.5, offsetY = 2.0,  offsetZ = 0.0, heading = 0.0,   behavior = 'scenario', scenario = 'WORLD_HUMAN_PARTYING',        weapon = '' },
            { model = 'g_f_y_families_01',  label = 'Families Girl 2',     offsetX = 0.5,  offsetY = 2.5,  offsetZ = 0.0, heading = 20.0,  behavior = 'scenario', scenario = 'WORLD_HUMAN_PARTYING',        weapon = '' },
            { model = 'g_m_y_famfor_01',    label = 'Dancer 1',            offsetX = 2.0,  offsetY = 2.0,  offsetZ = 0.0, heading = 340.0, behavior = 'scenario', scenario = 'WORLD_HUMAN_PARTYING',        weapon = '' },
            { model = 'mp_m_famdd_01',      label = 'Dancer 2',            offsetX = -0.8, offsetY = 0.8,  offsetZ = 0.0, heading = 180.0, behavior = 'scenario', scenario = 'WORLD_HUMAN_PARTYING',        weapon = '' },
            { model = 'g_m_y_famdnf_01',    label = 'Dancer 3',            offsetX = 1.2,  offsetY = 1.0,  offsetZ = 0.0, heading = 200.0, behavior = 'scenario', scenario = 'WORLD_HUMAN_PARTYING',        weapon = '' },
            -- Hype crew around the floor
            { model = 'a_m_y_stbla_02',     label = 'Hype Man 1',          offsetX = -3.0, offsetY = 1.0,  offsetZ = 0.0, heading = 90.0,  behavior = 'scenario', scenario = 'WORLD_HUMAN_CHEERING',        weapon = '' },
            { model = 'g_m_y_famca_01',     label = 'Hype Man 2',          offsetX = 3.5,  offsetY = 1.5,  offsetZ = 0.0, heading = 270.0, behavior = 'scenario', scenario = 'WORLD_HUMAN_CHEERING',        weapon = '' },
            -- OGs chilling on the edge
            { model = 'g_m_y_famdnf_01',    label = 'OG Smoking',          offsetX = -4.5, offsetY = -1.0, offsetZ = 0.0, heading = 45.0,  behavior = 'scenario', scenario = 'WORLD_HUMAN_SMOKING_POT',     weapon = '' },
            { model = 'g_m_y_famfor_01',    label = 'OG Drinking',         offsetX = 4.5,  offsetY = -1.0, offsetZ = 0.0, heading = 315.0, behavior = 'scenario', scenario = 'WORLD_HUMAN_DRINKING',        weapon = '' },
            -- Corner business and a wall leaner
            { model = 'mp_m_famdd_01',      label = 'Corner Boy',          offsetX = -5.5, offsetY = 3.0,  offsetZ = 0.0, heading = 90.0,  behavior = 'scenario', scenario = 'WORLD_HUMAN_DRUG_DEALER',     weapon = '' },
            { model = 'a_m_y_stbla_01',     label = 'Wall Leaner',         offsetX = 5.5,  offsetY = 3.0,  offsetZ = 0.0, heading = 270.0, behavior = 'scenario', scenario = 'WORLD_HUMAN_LEANING',         weapon = '' },
            -- Two homies arguing (interact behavior pairs them with each other)
            { model = 'g_m_y_famca_01',     label = 'Arguing Homie 1',     offsetX = 3.0,  offsetY = 5.0,  offsetZ = 0.0, heading = 90.0,  behavior = 'interact', scenario = '', interact_type = 'WORLD_HUMAN_HANG_OUT_STREET', weapon = '' },
            { model = 'g_m_y_famdnf_01',    label = 'Arguing Homie 2',     offsetX = 4.5,  offsetY = 5.0,  offsetZ = 0.0, heading = 270.0, behavior = 'interact', scenario = '', interact_type = 'WORLD_HUMAN_HANG_OUT_STREET', weapon = '' },
            -- Armed lookouts behind the party, facing the street
            { model = 'g_m_y_famfor_01',    label = 'Lookout (Pistol)',    offsetX = -3.0, offsetY = -5.0, offsetZ = 0.0, heading = 180.0, behavior = 'scenario', scenario = 'WORLD_HUMAN_HANG_OUT_STREET', weapon = 'WEAPON_PISTOL' },
            { model = 'g_m_y_famca_01',     label = 'Lookout (Micro SMG)', offsetX = 3.0,  offsetY = -5.0, offsetZ = 0.0, heading = 180.0, behavior = 'scenario', scenario = 'WORLD_HUMAN_GUARD_STAND',     weapon = 'WEAPON_MICROSMG' },
            -- Roamer keeping the block alive
            { model = 'g_f_y_families_01',  label = 'Roamer',              offsetX = -6.0, offsetY = -3.0, offsetZ = 0.0, heading = 0.0,   behavior = 'wander',   scenario = '',                            weapon = '' },
        },
    },
    {
        label = '🎰 Casino Floor Crowd',
        description = '8 peds - high rollers, pit boss, security, wandering player (no partying)',
        peds = {
            { model = 'a_m_y_business_03',   label = 'High Roller 1',    offsetX = 0.0,  offsetY = 0.0,  offsetZ = 0.0, heading = 180.0, behavior = 'scenario', scenario = 'WORLD_HUMAN_STAND_IMPATIENT', weapon = '' },
            { model = 'a_m_m_bevhills_01',   label = 'High Roller 2',    offsetX = 2.0,  offsetY = 0.0,  offsetZ = 0.0, heading = 180.0, behavior = 'scenario', scenario = 'WORLD_HUMAN_DRINKING',        weapon = '' },
            { model = 'a_f_m_bevhills_01',   label = 'VIP Lady',         offsetX = -2.0, offsetY = 0.0,  offsetZ = 0.0, heading = 180.0, behavior = 'scenario', scenario = 'WORLD_HUMAN_STAND_MOBILE',    weapon = '' },
            { model = 'a_f_y_business_02',   label = 'Cocktail Sipper',  offsetX = 4.0,  offsetY = 1.0,  offsetZ = 0.0, heading = 90.0,  behavior = 'scenario', scenario = 'WORLD_HUMAN_AA_COFFEE',       weapon = '' },
            { model = 's_m_m_bouncer_01',    label = 'Pit Boss',         offsetX = 0.0,  offsetY = -3.0, offsetZ = 0.0, heading = 0.0,   behavior = 'scenario', scenario = 'WORLD_HUMAN_CLIPBOARD',       weapon = '' },
            { model = 's_m_m_highsec_01',    label = 'Security 1',       offsetX = -5.0, offsetY = -4.0, offsetZ = 0.0, heading = 45.0,  behavior = 'scenario', scenario = 'WORLD_HUMAN_GUARD_STAND',     weapon = 'WEAPON_PISTOL' },
            { model = 's_m_m_highsec_02',    label = 'Security 2',       offsetX = 5.0,  offsetY = -4.0, offsetZ = 0.0, heading = 315.0, behavior = 'scenario', scenario = 'WORLD_HUMAN_GUARD_STAND',     weapon = 'WEAPON_PISTOL' },
            { model = 'a_m_y_smartcaspat_01',label = 'Wandering Player', offsetX = 3.0,  offsetY = 4.0,  offsetZ = 0.0, heading = 0.0,   behavior = 'wander',   scenario = '',                            weapon = '' },
        },
    },
    {
        label = '🛍️ Shopping Mall Crowd',
        description = '6 peds - shoppers browsing, shopkeeper, tourist, phone walkers (no partying)',
        peds = {
            { model = 'a_f_y_business_01',   label = 'Shopper 1',    offsetX = 0.0,  offsetY = 0.0,  offsetZ = 0.0, heading = 180.0, behavior = 'scenario', scenario = 'WORLD_HUMAN_WINDOW_SHOP_BROWSE', weapon = '' },
            { model = 'a_m_y_hipster_01',    label = 'Shopper 2',    offsetX = 3.0,  offsetY = 0.0,  offsetZ = 0.0, heading = 180.0, behavior = 'scenario', scenario = 'WORLD_HUMAN_WINDOW_SHOP_BROWSE', weapon = '' },
            { model = 'mp_m_shopkeep_01',    label = 'Shopkeeper',   offsetX = 1.5,  offsetY = 2.0,  offsetZ = 0.0, heading = 0.0,   behavior = 'scenario', scenario = 'WORLD_HUMAN_STAND_IMPATIENT',    weapon = '' },
            { model = 'a_f_y_tourist_01',    label = 'Tourist',      offsetX = -3.0, offsetY = 1.0,  offsetZ = 0.0, heading = 90.0,  behavior = 'scenario', scenario = 'WORLD_HUMAN_TOURIST_MAP',        weapon = '' },
            { model = 'a_m_y_smartcaspat_01',label = 'Phone Walker', offsetX = 5.0,  offsetY = -2.0, offsetZ = 0.0, heading = 270.0, behavior = 'scenario', scenario = 'WORLD_HUMAN_STAND_MOBILE',       weapon = '' },
            { model = 'a_f_y_hipster_02',    label = 'Wanderer',     offsetX = -4.0, offsetY = -2.0, offsetZ = 0.0, heading = 0.0,   behavior = 'wander',   scenario = '',                               weapon = '' },
        },
    },
    {
        label = '💼 Office Bullpen',
        description = '6 peds - clerks with clipboards, coffee break, phone calls (no partying)',
        peds = {
            { model = 'a_m_y_business_01', label = 'Clerk 1',       offsetX = 0.0,  offsetY = 0.0,  offsetZ = 0.0, heading = 0.0,   behavior = 'scenario', scenario = 'WORLD_HUMAN_CLIPBOARD',    weapon = '' },
            { model = 'a_f_y_business_02', label = 'Clerk 2',       offsetX = 2.5,  offsetY = 0.0,  offsetZ = 0.0, heading = 180.0, behavior = 'scenario', scenario = 'WORLD_HUMAN_CLIPBOARD',    weapon = '' },
            { model = 'a_m_y_business_03', label = 'Coffee Break',  offsetX = -2.0, offsetY = 2.0,  offsetZ = 0.0, heading = 90.0,  behavior = 'scenario', scenario = 'WORLD_HUMAN_AA_COFFEE',    weapon = '' },
            { model = 'a_f_y_business_04', label = 'On a Call',     offsetX = 4.0,  offsetY = 2.0,  offsetZ = 0.0, heading = 270.0, behavior = 'scenario', scenario = 'WORLD_HUMAN_STAND_MOBILE', weapon = '' },
            { model = 'a_m_m_business_01', label = 'Smoke Break',   offsetX = -4.0, offsetY = -2.0, offsetZ = 0.0, heading = 0.0,   behavior = 'scenario', scenario = 'WORLD_HUMAN_SMOKING',      weapon = '' },
            { model = 's_m_y_waiter_01',   label = 'Mailroom',      offsetX = 5.0,  offsetY = -2.0, offsetZ = 0.0, heading = 0.0,   behavior = 'wander',   scenario = '',                         weapon = '' },
        },
    },
    {
        label = '🏢 Apartment Lobby',
        description = '5 peds - concierge, doorman, residents coming and going (no partying)',
        peds = {
            { model = 'a_m_m_bevhills_01', label = 'Concierge',     offsetX = 0.0,  offsetY = 0.0,  offsetZ = 0.0, heading = 180.0, behavior = 'scenario', scenario = 'WORLD_HUMAN_CLIPBOARD',    weapon = '' },
            { model = 's_m_m_security_01', label = 'Doorman',       offsetX = 0.0,  offsetY = -5.0, offsetZ = 0.0, heading = 180.0, behavior = 'scenario', scenario = 'WORLD_HUMAN_GUARD_STAND',  weapon = '' },
            { model = 'a_f_y_hipster_03',  label = 'Resident 1',    offsetX = -3.0, offsetY = -1.0, offsetZ = 0.0, heading = 90.0,  behavior = 'scenario', scenario = 'WORLD_HUMAN_STAND_MOBILE', weapon = '' },
            { model = 'a_m_y_business_02', label = 'Resident 2',    offsetX = 3.0,  offsetY = -1.0, offsetZ = 0.0, heading = 270.0, behavior = 'scenario', scenario = 'WORLD_HUMAN_LEANING',      weapon = '' },
            { model = 'a_f_y_yoga_01',     label = 'Passing Thru',  offsetX = -5.0, offsetY = -3.0, offsetZ = 0.0, heading = 0.0,   behavior = 'wander',   scenario = '',                         weapon = '' },
        },
    },
    {
        label = '🍽️ Restaurant / Diner',
        description = '6 peds - seated diners, waiter, chef, bartender (no partying)',
        peds = {
            { model = 's_m_y_waiter_01',   label = 'Waiter',      offsetX = 0.0,  offsetY = 0.0,  offsetZ = 0.0, heading = 0.0,   behavior = 'wander',   scenario = '',                           weapon = '' },
            { model = 's_m_y_chef_01',     label = 'Chef',        offsetX = -4.0, offsetY = 2.0,  offsetZ = 0.0, heading = 90.0,  behavior = 'scenario', scenario = 'WORLD_HUMAN_STAND_IMPATIENT', weapon = '' },
            { model = 's_f_y_bartender_01',label = 'Bartender',   offsetX = 5.0,  offsetY = 2.0,  offsetZ = 0.0, heading = 270.0, behavior = 'scenario', scenario = 'WORLD_HUMAN_DRINKING',        weapon = '' },
            { model = 'a_m_y_business_03', label = 'Diner 1',     offsetX = 2.0,  offsetY = -3.0, offsetZ = 0.0, heading = 0.0,   behavior = 'scenario', scenario = 'PROP_HUMAN_SEAT_CHAIR',       weapon = '' },
            { model = 'a_f_y_business_02', label = 'Diner 2',     offsetX = -2.0, offsetY = -3.0, offsetZ = 0.0, heading = 180.0, behavior = 'scenario', scenario = 'PROP_HUMAN_SEAT_CHAIR',       weapon = '' },
            { model = 'a_f_y_bevhills_02', label = 'Diner 3',     offsetX = 4.0,  offsetY = -4.0, offsetZ = 0.0, heading = 180.0, behavior = 'scenario', scenario = 'PROP_HUMAN_SEAT_CHAIR',       weapon = '' },
        },
    },
    {
        label = '☕ Café / Coffee Shop',
        description = '5 peds - barista and customers sipping coffee (no partying)',
        peds = {
            { model = 'mp_m_shopkeep_01',    label = 'Barista',       offsetX = 0.0,  offsetY = 0.0,  offsetZ = 0.0, heading = 180.0, behavior = 'scenario', scenario = 'WORLD_HUMAN_STAND_IMPATIENT', weapon = '' },
            { model = 'a_f_y_hipster_02',    label = 'Customer 1',    offsetX = -3.0, offsetY = -2.0, offsetZ = 0.0, heading = 0.0,   behavior = 'scenario', scenario = 'WORLD_HUMAN_AA_COFFEE',       weapon = '' },
            { model = 'a_m_y_hipster_03',    label = 'Customer 2',    offsetX = 3.0,  offsetY = -2.0, offsetZ = 0.0, heading = 0.0,   behavior = 'scenario', scenario = 'WORLD_HUMAN_DRINKING',        weapon = '' },
            { model = 'a_f_y_business_04',   label = 'Remote Worker', offsetX = 4.0,  offsetY = 2.0,  offsetZ = 0.0, heading = 270.0, behavior = 'scenario', scenario = 'WORLD_HUMAN_STAND_MOBILE',    weapon = '' },
            { model = 'a_m_y_smartcaspat_01',label = 'Leaner',        offsetX = -4.0, offsetY = 2.0,  offsetZ = 0.0, heading = 90.0,  behavior = 'scenario', scenario = 'WORLD_HUMAN_LEANING',         weapon = '' },
        },
    },
    {
        label = '🏨 Hotel Lobby',
        description = '6 peds - valet, concierge, tourists, business traveler, security (no partying)',
        peds = {
            { model = 's_m_y_valet_01',    label = 'Valet',         offsetX = 0.0,  offsetY = 0.0,  offsetZ = 0.0, heading = 0.0,   behavior = 'scenario', scenario = 'WORLD_HUMAN_CAR_PARK_ATTENDANT', weapon = '' },
            { model = 'a_m_m_bevhills_01', label = 'Concierge',     offsetX = 3.0,  offsetY = 0.0,  offsetZ = 0.0, heading = 180.0, behavior = 'scenario', scenario = 'WORLD_HUMAN_CLIPBOARD',          weapon = '' },
            { model = 'a_m_m_tourist_01',  label = 'Tourist 1',     offsetX = -3.0, offsetY = 1.0,  offsetZ = 0.0, heading = 90.0,  behavior = 'scenario', scenario = 'WORLD_HUMAN_TOURIST_MAP',        weapon = '' },
            { model = 'a_f_y_tourist_02',  label = 'Tourist 2',     offsetX = -3.0, offsetY = 3.0,  offsetZ = 0.0, heading = 270.0, behavior = 'scenario', scenario = 'WORLD_HUMAN_BINOCULARS',         weapon = '' },
            { model = 'a_m_y_business_02', label = 'Biz Traveler',  offsetX = 5.0,  offsetY = 2.0,  offsetZ = 0.0, heading = 180.0, behavior = 'scenario', scenario = 'WORLD_HUMAN_STAND_MOBILE',       weapon = '' },
            { model = 's_m_m_security_01', label = 'Security',      offsetX = 0.0,  offsetY = -5.0, offsetZ = 0.0, heading = 180.0, behavior = 'scenario', scenario = 'WORLD_HUMAN_GUARD_STAND',        weapon = '' },
        },
    },
}

--  gang houses, one per set, all built from the same layout
-- Every ped carries a pistol and is placed mortal (invincible = false), which
-- is what lets rr-gangwar run them: it arms them properly, makes every set hate
-- every other set, sends them at rivals on sight and respawns the dead. Face
-- the front door when you place one: the OG stands at the back, lookouts watch
-- the street behind you, two roamers walk the block.
--
-- `m` = { og, caller, corner, leaner, smoker, drinker, hang1, hang2, girl
--         lookoutL, lookoutR, roam1, roam2 }, any entry may repeat a model.
local function GangHouse(emoji, name, m)
    local function P(model, label, x, y, h, behavior, scenario)
        return {
            model = model, label = name .. ' ' .. label,
            offsetX = x, offsetY = y, offsetZ = 0.0, heading = h,
            behavior = behavior, scenario = scenario or '',
            weapon = 'WEAPON_PISTOL', invincible = false,
        }
    end
    return {
        label = emoji .. ' ' .. name .. ' Gang House',
        description = '13 peds - armed set holding the house: OG, shot caller, corner boy, lookouts, roamers. All pistols, all mortal - rr-gangwar makes them fight rivals on sight',
        peds = {
            P(m[1],  'OG',           0.0,  5.0,  180.0, 'scenario', 'WORLD_HUMAN_STAND_IMPATIENT'),
            P(m[2],  'Shot Caller',  1.5,  4.5,  200.0, 'scenario', 'WORLD_HUMAN_STAND_MOBILE'),
            P(m[3],  'Corner Boy',  -4.5,  3.0,  90.0,  'scenario', 'WORLD_HUMAN_DRUG_DEALER'),
            P(m[4],  'Leaner',       4.5,  3.0,  270.0, 'scenario', 'WORLD_HUMAN_LEANING'),
            P(m[5],  'Smoker',      -2.5,  1.5,  45.0,  'scenario', 'WORLD_HUMAN_SMOKING'),
            P(m[6],  'Drinker',      2.5,  1.5,  315.0, 'scenario', 'WORLD_HUMAN_DRINKING'),
            P(m[7],  'Homie 1',     -1.0,  0.5,  120.0, 'scenario', 'WORLD_HUMAN_HANG_OUT_STREET'),
            P(m[8],  'Homie 2',      1.0,  0.5,  240.0, 'scenario', 'WORLD_HUMAN_HANG_OUT_STREET'),
            P(m[9],  'Girl',         0.0,  2.5,  180.0, 'scenario', 'WORLD_HUMAN_STAND_MOBILE'),
            P(m[10], 'Lookout L',   -3.5, -4.5,  180.0, 'scenario', 'WORLD_HUMAN_GUARD_STAND'),
            P(m[11], 'Lookout R',    3.5, -4.5,  180.0, 'scenario', 'WORLD_HUMAN_GUARD_STAND'),
            P(m[12], 'Roamer 1',    -6.0, -1.0,  0.0,   'wander'),
            P(m[13], 'Roamer 2',     6.0, -1.0,  0.0,   'wander'),
        },
    }
end

Config.PresetGroups[#Config.PresetGroups + 1] = GangHouse('🟢', 'Families', {
    'g_m_y_famdnf_01', 'g_m_y_famca_01', 'mp_m_famdd_01', 'g_m_y_famfor_01', 'g_m_y_famca_01',
    'g_m_y_famfor_01', 'g_m_y_famdnf_01', 'mp_m_famdd_01', 'g_f_y_families_01',
    'g_m_y_famca_01', 'g_m_y_famfor_01', 'g_m_y_famdnf_01', 'g_f_y_families_01',
})
Config.PresetGroups[#Config.PresetGroups + 1] = GangHouse('🟣', 'Ballas', {
    'g_m_y_ballaorig_01', 'g_m_y_ballaeast_01', 'g_m_y_ballasout_01', 'g_m_y_ballaeast_01', 'g_m_y_ballaorig_01',
    'g_m_y_ballasout_01', 'g_m_y_ballaeast_01', 'g_m_y_ballaorig_01', 'g_f_y_ballas_01',
    'g_m_y_ballasout_01', 'g_m_y_ballaorig_01', 'g_m_y_ballaeast_01', 'g_f_y_ballas_01',
})
Config.PresetGroups[#Config.PresetGroups + 1] = GangHouse('🟡', 'Vagos', {
    'g_m_y_mexgoon_03', 'g_m_y_mexgoon_01', 'g_m_y_mexgoon_02', 'g_m_y_mexgoon_01', 'g_m_y_mexgoon_03',
    'g_m_y_mexgoon_02', 'g_m_y_mexgoon_01', 'g_m_y_mexgoon_03', 'g_f_y_vagos_01',
    'g_m_y_mexgoon_02', 'g_m_y_mexgoon_01', 'g_m_y_mexgoon_03', 'g_f_y_vagos_01',
})
Config.PresetGroups[#Config.PresetGroups + 1] = GangHouse('⚫', 'Lost MC', {
    'g_m_y_lost_03', 'g_m_y_lost_01', 'g_m_y_lost_02', 'g_m_y_lost_01', 'g_m_y_lost_03',
    'g_m_y_lost_02', 'g_m_y_lost_01', 'g_m_y_lost_03', 'g_f_y_lost_01',
    'g_m_y_lost_02', 'g_m_y_lost_01', 'g_m_y_lost_03', 'g_f_y_lost_01',
})
Config.PresetGroups[#Config.PresetGroups + 1] = GangHouse('🔴', 'Triads', {
    'g_m_m_chiboss_01', 'g_m_m_korboss_01', 'g_m_y_korean_01', 'g_m_m_chigoon_02', 'g_m_m_chigoon_01',
    'g_m_y_korean_02', 'g_m_m_chigoon_01', 'g_m_y_korlieut_01', 'g_m_y_korean_01',
    'g_m_m_chigoon_02', 'g_m_y_korean_02', 'g_m_m_chigoon_01', 'g_m_y_korean_01',
})
Config.PresetGroups[#Config.PresetGroups + 1] = GangHouse('🟠', 'Cartel', {
    'g_m_m_mexboss_01', 'g_m_y_salvaboss_01', 'g_m_y_salvagoon_01', 'g_m_y_salvagoon_02', 'g_m_y_salvagoon_03',
    'g_m_y_salvagoon_01', 'g_m_y_salvagoon_02', 'g_m_y_salvagoon_03', 'g_m_y_mexgang_01',
    'g_m_y_salvagoon_02', 'g_m_y_salvagoon_01', 'g_m_y_salvagoon_03', 'g_m_m_mexboss_02',
})
