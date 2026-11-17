-- One simulator visit: offer stages when a course is selected; when the course is confirmed, bring the chosen stage
-- to the simulator (or, with route = move, the simulator to the stage); dress it once the game is in the simulator;
-- put everything back afterwards. Game calls go through `game` (game.lua), so this file is tested offline with a
-- fake (tests/session_test.lua).
local M = {}

M.ARM_TIMEOUT = 90    -- seconds to wait for the simulator after a course is confirmed
M.LEAVE_GRACE = 3     -- seconds out of the simulator before the visit counts as over
M.REDRESS_AFTER = 3   -- seconds after dressing to do it once more (the stage's own set-up can undo the first)
M.STREAM_PATIENCE = 30 -- seconds in the simulator before unloaded stage levels are reported
M.SHOWN_FOR = 0       -- extra seconds the simulator's own levels must all have been showing before they are touched
M.LIGHTS_PATIENCE = 12 -- seconds to hold the stage's lights for the simulator's lighting to show and be hidden
M.DRESSING_PARTS = 18 -- what the simulator's own look is made of when it is fully in (scenery, skyline, rim collision)
M.LOADER_IDLE = 1     -- seconds the package loader must have been idle before anything searches the game's objects
M.BLIND_SETTLE = 12   -- seconds to wait instead when there is no helper to ask
M.REACTIVATE_AFTER = 5 -- seconds after showing a streamed stage's hidden parts to do it once more

-- deps: stages, catalogue, game, choices (table, edited in place), save_choices(choices), log(message)
function M.new(deps)
    local stages, catalogue, game = deps.stages, deps.catalogue, deps.game
    local choices = deps.choices or {}
    local log = deps.log or function() end
    local self = { state = "idle" }

    -- The simulator volume of the world that is loaded, and everything the unlock rules ask about.
    local function look()
        local volume, continent
        for _, candidate in ipairs(game.vr_volumes(catalogue.vr_stage.volume_label)) do
            local c = stages.continent_of(candidate.name, catalogue.vr_stage)
            if c == "EASTC" or c == "WESTC" then
                if volume then return nil, nil, "two simulator volumes loaded" end
                volume, continent = candidate, c
            end
        end
        if not volume then return nil, nil, "no simulator volume here" end
        return volume, {
            continent = continent,
            flag = game.flag,
            progress = game.progress(),
            cleared = game.cleared(),
            can_stream = game.can_stream(),
        }
    end

    local function restore(why)
        if self.plan then
            for _, item in ipairs(self.plan) do game.stream_release(item.name) end
            log("restore\t" .. why .. "\treleased " .. #self.plan .. " levels")
        elseif self.volume and self.original then
            local ok = game.set_target(self.volume, self.original.location, self.original.yaw)
            log("restore\t" .. why .. "\ttarget " .. (ok and "restored" or "NOT restored"))
        else
            log("restore\t" .. why)
        end
        if self.dressed then game.set_dressing_hidden(catalogue.vr_stage, false, self.sky_hidden) end
        self.state, self.stage, self.volume, self.original, self.plan = "idle", nil, nil, nil, nil
        self.dressed, self.sky_hidden, self.left_at, self.redress_at, self.arrived_at, self.ready = nil, nil, nil, nil, nil, nil
        self.dressed_once, self.activated_at, self.reactivated = nil, nil, nil
        self.shown_since, self.shown_checked_at, self.waiting_logged = nil, nil, nil
        self.prepared, self.prepared_at, self.prepare_tries = nil, nil, nil
        self.lights_waiting = nil
    end

    local function dress(steps)
        if self.plan then
            -- A streamed stage brings its own sky when it lists one; then the simulator's sky goes too.
            self.sky_hidden = self.stage.sky_level ~= nil
        elseif steps.unhide then
            log("unhide\t" .. tostring(game.show_hidden_levels(self.volume)))
        end
        if steps.dressing then
            log("dressing\t" .. tostring(game.set_dressing_hidden(catalogue.vr_stage, true, self.sky_hidden)))
            self.dressed = true
        end
        if not self.plan and steps.sky and self.stage.sky then
            log("sky\t" .. self.stage.sky.volume .. "\t" .. tostring(game.switch_sky(self.stage.sky)))
        end
    end

    -- The player selected a course in the menu (its title is on the info panel). Returns the course and what the
    -- picker should offer: options ({ id, name }) and the index to start on. No options means no picker.
    function self.course_selected(title, settings)
        if self.state ~= "idle" then return nil, {}, 1 end
        self.titles = self.titles or stages.title_index(catalogue, game.text)
        local course = stages.course_by_title(self.titles, title)
        self.course = course
        if not course then
            log("select\tunrecognised\t" .. tostring(title))
            return nil, {}, 1
        end
        if not settings.enabled or course.excluded then return course, {}, 1 end
        local _, context, why = look()
        if not context then
            log("select\t" .. course.key .. "\t" .. why)
            return course, {}, 1
        end
        local options, left_out = stages.options(catalogue, course, context, settings)
        log("select\t" .. course.key .. "\t" .. #options .. " options\t" .. table.concat(left_out, "; "))
        if #options < 2 then return course, {}, 1 end
        return course, options, stages.selected_index(options, course, choices)
    end

    -- The player picked a stage for a course. Remembered until changed.
    function self.choose(course, id)
        choices[course.key] = id
        if deps.save_choices then deps.save_choices(choices) end
        log("choice\t" .. course.key .. "\t" .. id)
    end

    -- The player confirmed the selected course.
    function self.course_confirmed(now, settings)
        if self.state ~= "idle" then return nil, "visit in progress" end
        local volume, context, why = look()
        if not volume then return nil, why end
        local stage
        stage, why = stages.chosen(catalogue, self.course, context, settings, choices)
        log("confirm\t" .. (self.course and self.course.key or "?") .. "\t" .. (stage and stage.id or "vanilla") .. "\t" .. tostring(why))
        if not stage then return nil, why end
        local steps = stages.steps(settings)
        local original = game.get_target(volume)
        if not original then return nil, "simulator volume unreadable" end
        if stages.route_of(stage, settings) == "stream" then
            self.serial = (self.serial or 0) + 1
            local plan, asked = stages.stream_plan(stage, original.location, settings, self.serial), 0
            for _, item in ipairs(plan) do
                if game.stream_request(item) then asked = asked + 1 end
            end
            if asked < #plan then
                for _, item in ipairs(plan) do game.stream_release(item.name) end
                return nil, "level request refused"
            end
            self.plan = plan
            log(string.format("stream\t%s\t%d levels\t%.0f\t%.0f\t%.0f", stage.id, #plan,
                plan[1].location.X, plan[1].location.Y, plan[1].location.Z))
        elseif steps.relocate then
            local location, yaw = stages.target(stage, settings)
            if not game.set_target(volume, location, yaw) then
                game.set_target(volume, original.location, original.yaw)
                return nil, "target not accepted"
            end
            self.original = original
            log(string.format("relocate\t%s\t%.0f\t%.0f\t%.0f", stage.id, location.X, location.Y, location.Z))
        end
        self.state, self.stage, self.volume = "armed", stage, volume
        self.armed_at, self.settings = now, settings
        return stage, why
    end

    -- Whether every level of a streamed stage is loaded and showing. Reported once each way.
    local function watch_stream(now)
        if not self.plan or self.ready or self.watched_at == now then return end
        self.watched_at = now -- once a second is plenty: each look reads the helper's file
        local missing = {}
        for _, item in ipairs(self.plan) do
            if not game.stream_ready(item.name) then missing[#missing + 1] = item.package end
        end
        if #missing == 0 then
            self.ready = true
            log("stream\tready\t" .. (now - self.arrived_at) .. " s after arrival")
        elseif not self.reported and now - self.arrived_at >= M.STREAM_PATIENCE then
            self.reported = true
            log("stream\tNOT loaded after " .. M.STREAM_PATIENCE .. " s\t" .. table.concat(missing, "; "))
        end
    end

    -- Call a few times a second while not idle.
    function self.tick(now)
        if self.state == "idle" then return end
        local inside = game.in_simulator()
        if self.state == "armed" then
            if inside then
                self.arrived_at, self.reported = now, nil
                self.arrived_clock = game.clock and game.clock() or nil
                self.state = "live"
            else
                if now - self.armed_at > M.ARM_TIMEOUT then restore("simulator never started") end
                return
            end
        end
        if inside then
            self.left_at = nil
            -- Nothing searches the game's objects until the load that brought the party here has finished.
            local settled = game.settled(now, self.arrived_at, M.LOADER_IDLE, M.BLIND_SETTLE)
            local function since_arrival()
                local clock = game.clock and game.clock()
                if clock and self.arrived_clock then return string.format("%.1f s", (clock - self.arrived_clock) / 1000) end
                return (now - self.arrived_at) .. " s"
            end
            watch_stream(now)
            -- The stage's own parts first: stretched, and its sun, fog and hidden meshes shown, as soon as its levels
            -- are in. That is the heavy work, and it touches nothing of the simulator's, so it need not wait for the
            -- simulator; done early, it is not all waiting to happen at the moment the simulator's look goes. Shown
            -- once more a little later in case the stage's own set-up hid something again.
            if settled and self.plan and self.ready then
                if not self.activated_at then
                    self.activated_at = now
                    if self.stage.fit then log("fit\t" .. tostring(game.fit_stage(self.stage, self.plan))) end
                    -- The stage's lights go on only while none of the simulator's lighting levels is showing: now if
                    -- none is, otherwise the moment they have been hidden (below).
                    local lights_now = self.dressed_once or not game.simulator_lighting_visible(catalogue.vr_stage)
                    local shown, waiting = game.activate_stage(self.stage, lights_now)
                    self.lights_waiting = (waiting or 0) > 0
                    log("activate\t" .. tostring(shown) .. (self.lights_waiting and ("\tlights wait: " .. tostring(waiting)) or "")
                        .. "\t" .. since_arrival() .. " after arrival")
                elseif not self.reactivated and now - self.activated_at >= M.REACTIVATE_AFTER then
                    self.reactivated = true
                    log("activate again\t" .. tostring(game.reactivate_stage(self.stage)))
                end
            end
            -- The simulator's own look goes on the first tick on which the game has all of its own levels showing,
            -- and not before: a level told to hide while the game is still bringing it in holds up the start, and an
            -- idle loader alone does not mean it is in (on a later visit its levels are cached).
            -- The simulator's scenery (floor, blocks, skyline, rim collision) goes as soon as it exists, behind the
            -- loading screen: once a second one cheap search asks whether the floor is there; when it is, everything
            -- is found and hidden. Hiding actors changes no level's state, so it cannot hold the start up.
            if settled and not self.prepared and self.prepared_at ~= now and (self.prepare_tries or 0) < 40 then
                self.prepared_at, self.prepare_tries = now, (self.prepare_tries or 0) + 1
                if game.scenery_present(catalogue.vr_stage) then
                    local found = game.prepare_dressing(catalogue.vr_stage)
                    if found >= M.DRESSING_PARTS then
                        self.prepared = true
                        local steps = stages.steps(self.settings)
                        local hidden = steps.dressing and game.set_dressing_hidden(catalogue.vr_stage, true, false, "scenery") or 0
                        if steps.dressing then self.dressed = true end
                        log("scenery\t" .. tostring(hidden) .. " of " .. tostring(found) .. "\t" .. since_arrival() .. " after arrival")
                    end
                end
            end
            if settled and not self.dressed_once then
                local shown, count = game.simulator_shown(catalogue.vr_stage, now)
                if shown then self.shown_since = self.shown_since or now else self.shown_since = nil end
                if not shown and not self.waiting_logged and now - self.arrived_at >= 20 then
                    self.waiting_logged = true
                    log("waiting\tthe simulator's own levels are not all showing\t" .. tostring(count) .. " exist")
                end
                if self.shown_since and now - self.shown_since >= M.SHOWN_FOR then
                    self.dressed_once = true
                    -- Not everything was found beforehand: look again now (slow, but right).
                    if not self.prepared then game.prepare_dressing(catalogue.vr_stage) end
                    log("settled\t" .. since_arrival() .. " after arrival")
                    dress(stages.steps(self.settings))
                    self.redress_at = now + M.REDRESS_AFTER
                    if self.lights_waiting then
                        self.lights_waiting = nil
                        log("lights\t" .. tostring(game.show_stage_lights()))
                    end
                end
            elseif self.redress_at and now >= self.redress_at then
                self.redress_at = nil
                dress(stages.steps(self.settings))
            end
            -- The simulator's lighting never all showed: do not leave the stage unlit.
            if self.lights_waiting and self.activated_at and now - self.activated_at >= M.LIGHTS_PATIENCE then
                self.lights_waiting = nil
                log("lights\t" .. tostring(game.show_stage_lights()) .. "\tthe simulator's lighting never all showed")
            end
        else
            self.left_at = self.left_at or now
            if now - self.left_at >= M.LEAVE_GRACE then restore("left the simulator") end
        end
    end

    function self.busy() return self.state ~= "idle" end
    function self.stream_ready() return self.ready == true end

    return self
end

return M
