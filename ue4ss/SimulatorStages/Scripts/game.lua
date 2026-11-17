-- Every call into the game. Each function names what it relies on and, where it matters, what was seen in the game
-- (docs/LIVE-RESULTS.md).
--
-- Rules from our other mods (FFVII-Modding skills/create-rebirth-mod/references/cookbook.md):
--   * never name a member an object lacks, even in pcall: the failed lookup leaks the Lua C stack;
--   * FindAllOf costs about 0.2 s on the game thread whatever the class (measured 2026-11-17), so every search is
--     made behind the loading screen and references are kept.
local M = {}

local DATABASE_API = "/Script/EndGame.Default__EndDataBaseAPI"
local WORLD_API = "/Script/EndGame.Default__EndWorldAPI"
local MENU_API = "/Script/EndGame.Default__EndMenuAPI"
local BATTLE_API = "/Script/EndGame.Default__EndBattleAPI" -- GetPartyLeader lives here, not on EndPartyAPI
local MESSAGE_PAUSE_MENU = 2 -- EEndMenuMessageWindowFlags.PauseMenu
local IN_SIMULATOR_FLAGS = { "stfCmn_IsInVR_EASTC", "stfCmn_IsInVR_WESTC" }
local SWITCH_SEAMLESS = 1 -- EEndStreamingSwitchType::Seamless

local function safe(f, ...)
    local ok, value = pcall(f, ...)
    if ok then return value end
    return nil
end
local function valid(object)
    return object ~= nil and safe(function() return object:IsValid() end) == true
end
local function cdo(path)
    local object = safe(StaticFindObject, path)
    if valid(object) then return object end
    return nil
end

-- Story flags: UEndDataBaseAPI.IsStoryFlag(FName), as Junon Colosseum reads them.
function M.flag(name)
    local api = cdo(DATABASE_API)
    if not api then return false end
    return safe(function() return api:IsStoryFlag(FName(name)) end) == true
end

-- The game sets one of these while a simulator course runs (0000-COMON_VR's level script names both).
function M.in_simulator()
    for _, flag in ipairs(IN_SIMULATOR_FLAGS) do
        if M.flag(flag) then return true end
    end
    return false
end

-- Each world has one AEndStreamingVolume labelled COMMON_VR that streams 0000-COMON_VR at its TargetLocation
-- (1000-EASTC_WorldPlan, 2000-WESTC_WorldPlan_MiniGame). Returns { { name = actor name, object = volume } }.
function M.vr_volumes(label)
    local found = {}
    for _, volume in ipairs(safe(FindAllOf, "EndStreamingVolume") or {}) do
        if valid(volume) and safe(function() return volume.VolumeLabel:ToString() end) == label then
            found[#found + 1] = { name = safe(function() return volume:GetFName():ToString() end) or "?", object = volume }
        end
    end
    return found
end

-- AEndStreamingVolume.TargetLocation (FVector) and TargetRotationDegree (float), both BlueprintReadWrite.
function M.get_target(volume)
    local v = volume.object
    if not valid(v) then return nil end
    local x = safe(function() return v.TargetLocation.X end)
    local y = safe(function() return v.TargetLocation.Y end)
    local z = safe(function() return v.TargetLocation.Z end)
    local yaw = safe(function() return v.TargetRotationDegree end)
    if type(x) ~= "number" or type(y) ~= "number" or type(z) ~= "number" then return nil end
    return { location = { X = x, Y = y, Z = z }, yaw = type(yaw) == "number" and yaw or 0 }
end

-- Writes the target and reads it back. True only when the volume now holds the requested values.
function M.set_target(volume, location, yaw)
    local v = volume.object
    if not valid(v) then return false end
    safe(function() v.TargetLocation = { X = location.X, Y = location.Y, Z = location.Z } end)
    safe(function() v.TargetRotationDegree = yaw or 0 end)
    local now = M.get_target(volume)
    if not now then return false end
    local function near(a, b) return math.abs(a - b) < 1 end
    return near(now.location.X, location.X) and near(now.location.Y, location.Y) and near(now.location.Z, location.Z)
end

-- The simulator volume hides far terrain while it is active (HideLevelsInstead: 45 levels in the east, 117 in the
-- west, the west's including Corel's own terrain). AEndStreamingVolume.ShowHideInsteadLevels(bShow, bHideDrawOnly)
-- shows them again.
function M.show_hidden_levels(volume)
    local v = volume.object
    if not valid(v) then return false end
    return pcall(function() v:ShowHideInsteadLevels(true, false) end)
end

-- The simulator's own look: a floor prop and rotating blocks (actors in 0000-COMON_VR_Terrain_Strip), and the
-- spotlight and floating-cube levels. Actors are hidden one by one; the two levels are hidden as streaming levels.
-- With `sky_too`, the simulator's sky level (0001-WORLD_VRSky) is hidden as well, for a stage that brings its own.
-- The flat collision in 0000-COMON_VR_Terrain_Strip is left alone.
local SIMULATOR_SKY = "0001-WORLD_VRSky"
local hidden_actors, hidden_streams, hidden_components = {}, {}, {}
local hidden_seen = {} -- what is already in those lists, by address, so a repeat does not add it twice
-- The simulator's rim clutter (low blocks, 30 to 50 cm) collides through this actor of its terrain level. Hidden
-- with the rest of the look it would be an invisible obstacle, so its collision goes off with it (measured in the
-- game 2026-11-17: with it off the floor is flat out to the pillars at about 24 m). AActor.SetActorEnableCollision.
local RIM_COLLISION = "Spl_CST"
local collision_off = {}
-- Has the game finished bringing the simulator in? True when its lighting, effect and sky levels all exist and are
-- loaded and visible. The game loads them in turn while the "Get Ready" screen is up, the effect level last, so all
-- three showing means it is done with them. Also returns how many of them exist.
-- The game makes these levels anew on every visit. They are searched for at most once a second (a search every
-- 100 ms during the load slowed it from 8 s to 34 s, 2026-11-17); once all are found, each call only asks the kept
-- levels whether they are loaded and visible, which is cheap enough for every tick. Call only with the loader idle.
local simulator_levels, simulator_searched_at = {}, nil -- { stream, which } for each of the simulator's own levels
local function find_simulator_levels(vr_stage)
    local seen = {}
    simulator_levels = {}
    for _, stream in ipairs(safe(FindAllOf, "LevelStreamingDynamic") or {}) do
        if valid(stream) then
            local package = safe(function() return stream:GetWorldAssetPackageFName():ToString() end) or ""
            local which = package:find(SIMULATOR_SKY, 1, true) and SIMULATOR_SKY or nil
            for _, level in ipairs(vr_stage.dressing_levels) do
                if package:find(level, 1, true) then which = level end
            end
            if which and not seen[which] then
                seen[which] = true
                simulator_levels[#simulator_levels + 1] = { stream = stream, which = which }
            end
        end
    end
    return #simulator_levels
end
function M.simulator_shown(vr_stage, now)
    local expected, have = #vr_stage.dressing_levels + 1, 0
    for _, entry in ipairs(simulator_levels) do
        if valid(entry.stream) then have = have + 1 end
    end
    if have < expected then
        if simulator_searched_at == now then return false, have end
        simulator_searched_at = now
        have = find_simulator_levels(vr_stage)
        if have < expected then return false, have end
    end
    for _, entry in ipairs(simulator_levels) do
        if safe(function() return entry.stream:IsLevelLoaded() end) ~= true
            or safe(function() return entry.stream:IsLevelVisible() end) ~= true then
            return false, have
        end
    end
    return true, have
end

-- What makes up the simulator's own look, found ahead of the moment it goes and kept, so that moment only flips
-- kept objects. Each FindAllOf here costs about 0.2 s (it walks the whole object table, measured 2026-11-17); eight
-- of them at the swap froze the screen on the simulator's stage for two seconds. Returns how many things were found
-- (18 when the simulator is fully in: 16 scenery actors, its skyline component and its rim collision).
local dressing_ready = nil
-- Is the simulator's floor there yet? One search (about 0.2 s), to decide when the full look-up is worth making.
function M.scenery_present(vr_stage)
    for _, actor in ipairs(safe(FindAllOf, vr_stage.dressing_classes[1]) or {}) do
        if valid(actor) then return true end
    end
    return false
end
function M.prepare_dressing(vr_stage)
    local found = { actors = {}, components = {}, collision = {} }
    for _, actor in ipairs(safe(FindAllOf, "CollisionAssetActor") or {}) do
        if valid(actor) then
            local name = safe(function() return actor:GetFullName() end) or ""
            if name:find(vr_stage.collision_level, 1, true) and name:find(RIM_COLLISION, 1, true) then
                found.collision[#found.collision + 1] = actor
            end
        end
    end
    -- The block skyline round the simulator is drawn by its terrain level's massive-environment component, which
    -- hiding the actors does not touch (seen in the game 2026-11-17).
    for _, actor in ipairs(safe(FindAllOf, "MassiveEnvironmentActor") or {}) do
        if valid(actor) and (safe(function() return actor:GetFullName() end) or ""):find(vr_stage.collision_level, 1, true) then
            local component = safe(function() return actor.MassiveEnvironmentComponent end)
            if valid(component) then found.components[#found.components + 1] = component end
        end
    end
    for _, class in ipairs(vr_stage.dressing_classes) do
        for _, actor in ipairs(safe(FindAllOf, class) or {}) do
            if valid(actor) then found.actors[#found.actors + 1] = actor end
        end
    end
    dressing_ready = found
    return #found.actors + #found.components + #found.collision
end

-- `what`: "scenery" hides only the actors, skyline and rim collision (safe at any time: no level's state changes);
-- nil hides those and the simulator's lighting, effect and sky levels.
function M.set_dressing_hidden(vr_stage, hidden, sky_too, what)
    local count = 0
    if not hidden then
        -- Show exactly what was hidden, from the kept references: no search while the game loads its way out.
        for _, actor in ipairs(hidden_actors) do
            if valid(actor) and pcall(function() actor:SetActorHiddenInGame(false) end) then count = count + 1 end
        end
        for _, stream in ipairs(hidden_streams) do
            if valid(stream) and pcall(function() stream:SetShouldBeVisible(true) end) then count = count + 1 end
        end
        for _, component in ipairs(hidden_components) do
            if valid(component) and pcall(function()
                component:SetHiddenInGame(false, true)
                component:SetVisibility(true, true)
            end) then count = count + 1 end
        end
        for _, actor in ipairs(collision_off) do
            if valid(actor) and pcall(function() actor:SetActorEnableCollision(true) end) then count = count + 1 end
        end
        hidden_actors, hidden_streams, hidden_components, collision_off = {}, {}, {}, {}
        hidden_seen, dressing_ready = {}, nil
        return count
    end
    -- Hide from what was found beforehand; search now only if nothing was (that is the slow path).
    if not dressing_ready then M.prepare_dressing(vr_stage) end
    if what ~= "scenery" and #simulator_levels == 0 then find_simulator_levels(vr_stage) end
    local function keep(list, object)
        local key = tostring(safe(function() return object:GetAddress() end) or object)
        if not hidden_seen[key] then
            hidden_seen[key] = true
            list[#list + 1] = object
        end
    end
    for _, actor in ipairs(dressing_ready.collision) do
        if valid(actor) and pcall(function() actor:SetActorEnableCollision(false) end) then
            keep(collision_off, actor)
            count = count + 1
        end
    end
    for _, component in ipairs(dressing_ready.components) do
        if valid(component) and pcall(function()
            component:SetHiddenInGame(true, true)
            component:SetVisibility(false, true)
        end) then
            keep(hidden_components, component)
            count = count + 1
        end
    end
    for _, actor in ipairs(dressing_ready.actors) do
        if valid(actor) and pcall(function() actor:SetActorHiddenInGame(true) end) then
            keep(hidden_actors, actor)
            count = count + 1
        end
    end
    if what == "scenery" then return count end
    for _, entry in ipairs(simulator_levels) do
        local stream = entry.stream
        -- Only a level the game has already shown: one told to hide while the game is still bringing it in
        -- holds up the start of the fight (seen in the game 2026-11-17).
        if valid(stream) and (sky_too or entry.which ~= SIMULATOR_SKY)
            and safe(function() return stream:IsLevelVisible() end) == true
            and pcall(function() stream:SetShouldBeVisible(false) end) then
            keep(hidden_streams, stream)
            count = count + 1
        end
    end
    return count
end

-- UEndWorldAPI.SwitchStreamingVolume(VolumeLabel, SwitchLabel, SwitchType). An empty label means the volume's own
-- default (its NoneSwitchLabel), which is the region's daytime sky.
function M.switch_sky(sky)
    local api = cdo(WORLD_API)
    if not api then return false end
    local label = (sky.label and sky.label ~= "") and sky.label or "None"
    return pcall(function() api:SwitchStreamingVolume(FName(sky.volume), FName(label), SWITCH_SEAMLESS) end)
end

-- Chapter progress (12000 = Chapter 12) and whether the game has been finished, as Junon Colosseum reads them.
function M.progress()
    local api = cdo(DATABASE_API)
    local value = api and safe(function() return api:GetChapterProgress() end)
    return type(value) == "number" and value or nil
end
function M.cleared() return M.flag("stfComn_Release_ChapterSelect") end

-- Streamed stages. UE4SS 3.0.1's Lua cannot call LevelStreamingDynamic.LoadLevelInstance (its bool out-parameter
-- breaks the argument stack), so the native helper (native/, dlls/main.dll) makes that call on the game thread.
-- The two sides talk through files in the mod's folder, as Junon Colosseum's do:
--   stages-helper.txt   written by the helper twice a second: tick, ready (its checks on the game's code passed)
--   stages-request.txt  written here: load <tab> name <tab> package <tab> x <tab> y <tab> z <tab> yaw, one per line
--   stages-ack.txt      written by the helper: name <tab> loaded | refused <tab> reason
-- The helper loads each level as a new instance called `name` at that position. Everything after that is plain Lua
-- on the streaming object.
local MOD_DIR = (debug.getinfo(1, "S").source:match("^@(.*[\\/])[Ss]cripts[\\/]")) or ""
local helper = { tick = nil, changed_at = nil, ready = false, loading = true, idle_since = nil }

-- The helper's clock in milliseconds (it moves every half second), for timing notes in the log; nil without a helper.
function M.clock()
    return tonumber(helper.tick)
end

-- Call a few times a second (plain file reading, any thread). The helper counts as present while its tick moves.
function M.helper_poll(now)
    local file = io.open(MOD_DIR .. "stages-helper.txt", "rb")
    if not file then
        helper.tick, helper.changed_at, helper.ready, helper.loading, helper.idle_since = nil, nil, false, true, nil
        return
    end
    local text = file:read("a") or ""
    file:close()
    local tick = text:match("tick\t(%d+)")
    if tick and tick ~= helper.tick then
        if helper.tick then helper.changed_at = now end
        helper.tick = tick
    end
    helper.ready = text:match("ready\t1") ~= nil
    helper.loading = text:match("loading\t0") == nil
    if helper.loading then helper.idle_since = nil else helper.idle_since = helper.idle_since or now end
end

-- Has the game finished loading? Searching the game's objects in the tail of a load crashed Junon Colosseum twice,
-- so nothing here looks for objects until this says so. With the helper: the package loader has been idle for
-- `idle_seconds`. Without it there is no way to ask, so a flat `blind_seconds` since `since` (Junon's old floor).
function M.settled(now, since, idle_seconds, blind_seconds)
    if M.can_stream(now) then
        return helper.idle_since ~= nil and now - helper.idle_since >= idle_seconds
    end
    return now - since >= blind_seconds
end

function M.can_stream(now)
    now = now or os.time()
    return helper.ready and helper.changed_at ~= nil and now - helper.changed_at <= 3
end

-- Appends one line to the request file (written whole, then renamed, so the helper never reads half a line).
local function request(line)
    local path = MOD_DIR .. "stages-request.txt"
    local existing = ""
    local file = io.open(path, "rb")
    if file then
        existing = file:read("a") or ""
        file:close()
    end
    local out = io.open(path .. ".tmp", "wb")
    if not out then return false end
    out:write(existing .. line .. "\n")
    out:close()
    os.remove(path)
    return os.rename(path .. ".tmp", path) == true
end

function M.stream_request(item)
    if not M.can_stream() then return false end
    return request(string.format("load\t%s\t%s\t%.3f\t%.3f\t%.3f\t%.3f", item.name, item.package,
        item.location.X, item.location.Y, item.location.Z, item.yaw or 0))
end

-- What the helper said about an instance: "loaded", "unloaded", "refused" or nil (nothing yet). The last word wins.
function M.stream_state(name)
    local file = io.open(MOD_DIR .. "stages-ack.txt", "rb")
    if not file then return nil end
    local state
    for line in file:lines() do
        local who, what = line:match("^([%w_]+)\t(%a+)")
        if who == name then state = what end
    end
    file:close()
    return state
end

function M.stream_ready(name) return M.stream_state(name) == "loaded" end

-- The helper kept the stream it loaded, and unloads it.
function M.stream_release(name)
    return request("unload\t" .. name)
end

-- A streamed stage arrives with parts switched off. Its sky level's sun and fog are hidden until the game's own sky
-- system selects that sky, and some stages' meshes are hidden until their boss fight shows them (the rock in space:
-- all 41; seen in the game 2026-11-17). This shows them: the sun and fog always, and the classes the stage lists in
-- `show_classes`. Only actors in this stage's own instances ("SimStage_<id>_") are touched. Returns how many.
local shown_actors = {}
-- The stage's lights: what decides how the scene is lit. Switched on while the simulator's own lighting levels are
-- showing, they leave the scene dull once those are hidden (the Lifestream, 2026-11-17), so they wait (see below).
local LIGHT_CLASSES = { DirectionalLight = true, ExponentialHeightFog = true, PrecomputedLightEnvironmentActor = true,
    SphereReflectionCapture = true, VolumetricFogInjectionVolumeActor = true }
local waiting_lights = {}

-- Is any of the simulator's own lighting, effect or sky levels visible right now? One search.
function M.simulator_lighting_visible(vr_stage)
    find_simulator_levels(vr_stage)
    for _, entry in ipairs(simulator_levels) do
        if valid(entry.stream) and safe(function() return entry.stream:IsLevelVisible() end) == true then return true end
    end
    return false
end

-- `lights_now` false: the stage's lights are found but left off, for `show_stage_lights` to switch on later.
function M.activate_stage(stage, lights_now)
    local marker = "SimStage_" .. stage.id .. "_"
    -- The sun and fog come from the sky level; the ambient light, reflection capture and fog volume from the stage's
    -- light level. Without the ambient light characters are black silhouettes (the Lifestream, 2026-11-17).
    local classes = { "DirectionalLight", "ExponentialHeightFog", "PrecomputedLightEnvironmentActor",
        "SphereReflectionCapture", "VolumetricFogInjectionVolumeActor" }
    for _, class in ipairs(stage.show_classes or {}) do classes[#classes + 1] = class end
    -- Never shown: collision-only meshes ("CL_...") and what the stage lists in `keep_hidden` (cutscene props).
    local keep = { "PersistentLevel.CL_" }
    for _, part in ipairs(stage.keep_hidden or {}) do keep[#keep + 1] = "PersistentLevel." .. part end
    local function kept(name)
        for _, part in ipairs(keep) do
            if name:find(part, 1, true) then return true end
        end
        return false
    end
    local shown = 0
    shown_actors, waiting_lights = {}, {}
    for _, class in ipairs(classes) do
        local later = lights_now == false and LIGHT_CLASSES[class] == true
        for _, actor in ipairs(safe(FindAllOf, class) or {}) do
            if valid(actor) and safe(function() return actor.bHidden end) == true then
                local name = safe(function() return actor:GetFullName() end) or ""
                if name:find(marker, 1, true) and not kept(name) then
                    if later then
                        waiting_lights[#waiting_lights + 1] = actor
                    elseif pcall(function() actor:SetActorHiddenInGame(false) end) then
                        shown_actors[#shown_actors + 1] = actor
                        shown = shown + 1
                    end
                end
            end
        end
    end
    return shown, #waiting_lights
end

-- Switches on the lights `activate_stage` left off. No search.
function M.show_stage_lights()
    local shown = 0
    for _, actor in ipairs(waiting_lights) do
        if valid(actor) and pcall(function() actor:SetActorHiddenInGame(false) end) then
            shown_actors[#shown_actors + 1] = actor
            shown = shown + 1
        end
    end
    waiting_lights = {}
    return shown
end

-- Shows again whatever `activate_stage` showed and the stage's own set-up has hidden since. No search: this runs a
-- few seconds into the fight, where eight searches would freeze the screen for a second and a half.
function M.reactivate_stage()
    local shown = 0
    for _, actor in ipairs(shown_actors) do
        if valid(actor) and safe(function() return actor.bHidden end) == true
            and pcall(function() actor:SetActorHiddenInGame(false) end) then
            shown = shown + 1
        end
    end
    return shown
end

-- A stage smaller than the simulator's arena (a circle of 24.4 m radius, measured 2026-11-17) leaves invisible floor
-- round it, and one much larger puts the wall in the middle of it. `stage.fit.scale` ({ x, y }, or one number for
-- both) stretches it sideways about the arena's centre: each actor of `scale_classes` moves to centre + scale * (its
-- offset from the centre) and is scaled to match (along its own axes, so a turned actor gets the right mix of the
-- two); `move_classes` only move. Heights are left alone, so bumps do not grow. An actor whose name holds one of
-- `fit.keep`'s names is not stretched: it keeps its true size and place, lowered by that entry's `lower_cm` if set
-- (the Edge of Creation's far-land mesh carries a low-detail copy of the platform that would poke through the real one). Static actors are made movable first (USceneComponent.SetMobility),
-- or the engine will not move them. Only this visit's copies (`plan` names) are touched. Returns how many.
local MOVABLE = 2
function M.fit_stage(stage, plan)
    local fit, centre = stage.fit, plan and plan.centre
    if not (fit and centre and fit.scale) then return 0 end
    local sx, sy
    if type(fit.scale) == "table" then sx, sy = fit.scale[1], fit.scale[2] else sx, sy = fit.scale, fit.scale end
    if type(sx) ~= "number" or type(sy) ~= "number" or (sx == 1 and sy == 1) then return 0 end
    local function ours(name)
        for _, item in ipairs(plan) do
            if name:find(item.name .. ".", 1, true) then return true end
        end
        return false
    end
    local function kept(name)
        for _, entry in ipairs(fit.keep or {}) do
            if name:find(entry.name, 1, true) then return entry end
        end
        return nil
    end
    local count = 0
    local function each(classes, scale_too)
        for _, class in ipairs(classes or {}) do
            for _, actor in ipairs(safe(FindAllOf, class) or {}) do
                local name = valid(actor) and (safe(function() return actor:GetFullName() end) or "") or ""
                local keep = kept(name)
                if name ~= "" and ours(name) and pcall(function()
                    local component = actor.RootComponent
                    if component and component:IsValid() then component:SetMobility(MOVABLE) end
                    local p = actor:K2_GetActorLocation()
                    if keep then
                        if (keep.lower_cm or 0) ~= 0 then
                            actor:K2_SetActorLocation({ X = p.X, Y = p.Y, Z = p.Z - keep.lower_cm }, false, {}, true)
                        end
                        return
                    end
                    actor:K2_SetActorLocation({
                        X = centre.X + sx * (p.X - centre.X),
                        Y = centre.Y + sy * (p.Y - centre.Y),
                        Z = p.Z,
                    }, false, {}, true)
                    if scale_too then
                        local k = actor:GetActorScale3D()
                        local yaw = math.rad(actor:K2_GetActorRotation().Yaw)
                        local c, s = math.cos(yaw), math.sin(yaw)
                        actor:SetActorScale3D({
                            X = k.X * math.sqrt((sx * c) ^ 2 + (sy * s) ^ 2),
                            Y = k.Y * math.sqrt((sx * s) ^ 2 + (sy * c) ^ 2),
                            Z = k.Z,
                        })
                    end
                end) then
                    count = count + 1
                end
            end
        end
    end
    each(fit.scale_classes, true)
    each(fit.move_classes, false)
    return count
end

-- A text by its id in the player's language: UEndMenuAPI.GetString(TextId), as Junon Colosseum's text dump calls it.
function M.text(id)
    local api = cdo(MENU_API)
    if not api then return nil end
    local value = safe(function() return api:GetString(id) end)
    if value ~= nil and type(value) ~= "string" then value = safe(function() return value:ToString() end) end
    return type(value) == "string" and value or nil
end

-- The selected course's title: UEndColosseumMenu.InfoWindow.Txt_CourseTitle, falling back to Txt_TitleCourse, as
-- Training Dummy reads it. `context` is the hook's first argument.
function M.course_title(context)
    local menu = safe(function() return context:get() end)
    if not valid(menu) then return nil end
    local title = safe(function() return menu.InfoWindow.Txt_CourseTitle:GetText():ToString() end)
    if type(title) ~= "string" or title == "" then
        title = safe(function() return menu.Txt_TitleCourse:GetText():ToString() end)
    end
    return type(title) == "string" and title or nil
end

-- The game's own choice window: UEndMenuAPI.ShowMessageWindow(context, text, options, flags). Junon Colosseum uses
-- it in the field and in battle. On top of the simulator's menu it is untested.
function M.open_picker(prompt, labels)
    local menu, battle = cdo(MENU_API), cdo(BATTLE_API)
    if not menu or not battle then return nil end
    local leader = safe(function() return battle:GetPartyLeader() end)
    if not valid(leader) then return nil end
    local window = safe(function() return menu:ShowMessageWindow(leader, prompt, labels, MESSAGE_PAUSE_MENU) end)
    return valid(window) and window or nil
end

-- "open" while the window is up; otherwise "closed" and the zero-based index picked (nil when unreadable).
function M.read_picker(window)
    local menu = cdo(MENU_API)
    if not menu or not valid(window) then return "closed", nil end
    local closed = safe(function() return menu:IsMessageWindowClosed(window) end)
    if closed == false then return "open", nil end
    local index = safe(function() return menu:GetMessageWindowSelectedIndex(window) end)
    return "closed", type(index) == "number" and index or nil
end

return M
