-- Yet Not Another All-In-One Mod Menu
-- Version: 1.0
-- @iitztoasty


-- ==========================================
-- STATE & CONFIGURATION
-- ==========================================
local state = {
    -- Self Options
    godmode = { value = false },
    never_wanted = { value = false },
    super_jump = { value = false },
    invisible = { value = false },
    walkable_animations = { value = false },

    -- Vehicle Options
    veh_godmode = { value = false },
    veh_horn_boost = { value = false },

    -- Weapon Options
    explosive_ammo = { value = false },
    infinite_ammo = { value = false },

    -- World & Visuals
    player_esp = { value = false },
    info_hud = { value = true },

    -- Vehicle Spawner State
    spawner = {
        preview_handle = 0,
        preview_hash = 0,
        selected_name = ""
    }
}

local function save_config()
    for key, ref in pairs(state) do
        script.set_config(key, ref.value)
    end
    notify.success("AIO settings saved to config.")
end

local function load_config()
    for key, ref in pairs(state) do
        local val = script.get_config(key, nil)
        if val ~= nil then
            ref.value = val
        end
    end
end

-- Load configuration on script initialization
load_config()

-- ==========================================
-- EVENT HANDLERS
-- ==========================================
event.register_handler(menu_event.PlayerJoin, function(data)
    notify.joined(string.format("%s joined the session.", data.name))
    log.info(string.format("Join: %s | RID: %d", data.name, data.rid))
end)

event.register_handler(menu_event.PlayerLeave, function(data)
    notify.left(string.format("%s left the session.", data.name))
end)

event.register_handler(menu_event.Unload, function()
    -- Ensure clean up if necessary before script terminates
    if state.spawner.preview_handle ~= 0 and entities.exist(state.spawner.preview_handle) then
        if entities.request_control(state.spawner.preview_handle) then
            entities.delete(state.spawner.preview_handle)
        end
    end
    save_config()
    drawing.clear()
end)

-- ==========================================
-- MAIN LOOP (TICK)
-- ==========================================
function tick()
    local ped = self.get_ped()
    local veh = self.get_veh()
    local pid = PLAYER.PLAYER_ID()

    -- 1. Self Modifiers
    if ped ~= 0 then
        ENTITY.SET_ENTITY_INVINCIBLE(ped, state.godmode.value)
        ENTITY.SET_ENTITY_VISIBLE(ped, not state.invisible.value, false)

        if state.super_jump.value then
            MISC.SET_SUPER_JUMP_THIS_FRAME(pid)
        end

        if state.never_wanted.value then
            if PLAYER.GET_PLAYER_WANTED_LEVEL(pid) > 0 then
                PLAYER.CLEAR_PLAYER_WANTED_LEVEL(pid)
            end
        end

        if state.infinite_ammo.value then
            WEAPON.SET_PED_INFINITE_AMMO_CLIP(ped, true)
        end

        if state.explosive_ammo.value then
            MISC.SET_EXPLOSIVE_AMMO_THIS_FRAME(pid)
        end
    end

    -- 2. Vehicle Modifiers
    if veh ~= 0 then
        ENTITY.SET_ENTITY_INVINCIBLE(veh, state.veh_godmode.value)

        if state.veh_horn_boost.value then
            if PLAYER.IS_PLAYER_PRESSING_HORN(pid) then
                local forward_vector = ENTITY.GET_ENTITY_FORWARD_VECTOR(veh)
                -- Apply a forward force (Native properties are accessed via .x, .y, .z)
                ENTITY.APPLY_FORCE_TO_ENTITY(veh, 1, forward_vector.x * 20.0, forward_vector.y * 20.0,
                    forward_vector.z * 20.0, 0.0, 0.0, 0.0, 0, true, true, true, false, true)
            end
        end
    end

    -- 3. Visuals & ESP
    if state.info_hud.value then
        local pos = self.get_pos()
        local info_text = string.format("Ethereal AIO | X: %.1f Y: %.1f Z: %.1f | Health: %d/%d", pos.x, pos.y, pos.z,
            self.get_health(), self.get_max_health())
        drawing.text(10.0, 10.0, info_text, { r = 100, g = 255, b = 100, a = 255 }, 0.5)
    end

    if state.player_esp.value then
        local y_offset = 30.0
        drawing.text(10.0, y_offset, "Player ESP:", "white", 0.4)
        y_offset = y_offset + 15.0

        local my_pos = self.get_pos()
        for i = 0, 31 do
            local p = players.get(i)
            if p and p:valid() and not p:is_local() then
                local dist = p:distance(my_pos)
                local ped = p:get_ped()
                local is_dead = ped == 0 or entities.get_health(ped) <= 0
                local status = is_dead and "[DEAD]" or string.format("[%.1fm]", dist)
                local color = is_dead and "red" or "cyan"

                local esp_str = string.format("%d: %s %s", p:id(), p:get_name(), status)
                drawing.text(15.0, y_offset, esp_str, color, 0.4)
                y_offset = y_offset + 15.0
            end
        end
    end

    -- 4. Preview Rotation
    if state.spawner.preview_handle ~= 0 and entities.exist(state.spawner.preview_handle) then
        local p_veh = state.spawner.preview_handle
        local h = ENTITY.GET_ENTITY_HEADING(p_veh)
        ENTITY.SET_ENTITY_HEADING(p_veh, h + 0.5)
    end
end

-- ==========================================
-- MENU INTERFACE
-- ==========================================

local function handle_vehicle_spawn(name, hash_name)
    script.run_in_fiber(function()
        local hash = joaat(hash_name)

        -- If they clicked the same car we are already previewing, spawn it!
        if state.spawner.selected_name == name and state.spawner.preview_handle ~= 0 then
            STREAMING.REQUEST_MODEL(hash)
            local start_time = util.time_ms()
            while not STREAMING.HAS_MODEL_LOADED(hash) do
                if util.time_ms() - start_time > 5000 then
                    notify.error("Failed to load model: " .. hash_name)
                    state.spawner.preview_handle = 0
                    state.spawner.selected_name = ""
                    return
                end
                script.yield(10)
            end

            local pos = self.get_pos()
            local heading = self.get_heading()
            local veh = VEHICLE.CREATE_VEHICLE(hash, pos.x, pos.y, pos.z, heading, true, false)

            PED.SET_PED_INTO_VEHICLE(self.get_ped(), veh, -1)
            STREAMING.SET_MODEL_AS_NO_LONGER_NEEDED(hash)

            -- Delete the preview vehicle
            if entities.exist(state.spawner.preview_handle) and entities.request_control(state.spawner.preview_handle) then
                entities.delete(state.spawner.preview_handle)
            end
            state.spawner.preview_handle = 0
            state.spawner.preview_hash = 0
            state.spawner.selected_name = ""

            notify.success(name .. " Spawned!")
        else
            -- Check if on foot
            if self.get_veh() ~= 0 then
                notify.warning("You must be on foot to preview vehicles.")
                return
            end

            -- Preview mode
            notify.info("Previewing " .. name .. ". Click again to spawn.")

            -- Delete old preview
            if state.spawner.preview_handle ~= 0 and entities.exist(state.spawner.preview_handle) then
                if entities.request_control(state.spawner.preview_handle) then
                    entities.delete(state.spawner.preview_handle)
                end
            end

            STREAMING.REQUEST_MODEL(hash)
            local start_time = util.time_ms()
            while not STREAMING.HAS_MODEL_LOADED(hash) do
                if util.time_ms() - start_time > 5000 then
                    notify.error("Failed to load model: " .. hash_name)
                    return
                end
                script.yield(10)
            end

            -- Spawn in front of player
            local ped = self.get_ped()
            local forward_pos = ENTITY.GET_OFFSET_FROM_ENTITY_IN_WORLD_COORDS(ped, 0.0, 5.0, 0.0)
            local heading = self.get_heading()

            -- CREATE_VEHICLE(modelHash, x, y, z, heading, isNetwork, bScriptHostVeh)
            local preview_veh = VEHICLE.CREATE_VEHICLE(hash, forward_pos.x, forward_pos.y, forward_pos.z, heading, false,
                false)

            ENTITY.SET_ENTITY_ALPHA(preview_veh, 127, false)
            ENTITY.SET_ENTITY_COLLISION(preview_veh, false, false)
            ENTITY.FREEZE_ENTITY_POSITION(preview_veh, true)

            STREAMING.SET_MODEL_AS_NO_LONGER_NEEDED(hash)

            state.spawner.preview_handle = preview_veh
            state.spawner.preview_hash = hash
            state.spawner.selected_name = name
        end
    end)
end

gui.register_menu("YNAAIOMM", function()
    -- Submenu: Self Options
    local self_menu = gui.add_submenu("Self Options", "Modifications for your local player")
    gui.set_submenu_context(self_menu)
    gui.add_bool_option("Godmode", "Prevents all damage", state.godmode)
    gui.add_bool_option("Invisibility", "Make your player model invisible", state.invisible)
    gui.add_bool_option("Never Wanted", "Automatically clears police wanted level", state.never_wanted)
    gui.add_bool_option("Super Jump", "Jump incredibly high", state.super_jump)
    gui.add_break("Movement & Physics")
    gui.add_bool_option("Fast Run/Sprint", "Run extremely fast", state.fast_run)
    gui.add_bool_option("Fast Swim", "Swim extremely fast", state.fast_swim)
    gui.add_bool_option("No Ragdoll", "Cannot be knocked over", state.no_ragdoll)
    gui.add_bool_option("Seatbelt", "Cannot be launched from vehicles", state.seatbelt)
    gui.add_bool_option("Ignored by NPCs", "Cops and peds ignore you", state.ignored_by_npcs)
    gui.add_option("Clone Ped", "Spawn a clone of yourself", function()
        local ped = self.get_ped()
        local pos = self.get_pos()
        PED.CLONE_PED(ped, self.get_heading(), false, false)
        notify.success("Clone spawned.")
    end)

    gui.add_break("Crazy Powers")
    if state.jedi_forcefield == nil then state.jedi_forcefield = { value = false } end
    if state.fire_breath == nil then state.fire_breath = { value = false } end
    if state.walk_on_water == nil then state.walk_on_water = { value = false } end
    gui.add_bool_option("Jedi Forcefield", "Repels all nearby peds and vehicles", state.jedi_forcefield)
    gui.add_bool_option("Fire Breath", "Attack while unarmed to breathe fire", state.fire_breath)
    gui.add_bool_option("Walk on Water", "Spawn an invisible platform on water", state.walk_on_water)

    gui.add_break("Appearance")
    local model_menu = gui.add_submenu("Model Changer", "Change player model")
    gui.set_submenu_context(model_menu)
    local function handle_model_spawn(model_name)
        script.run_in_fiber(function()
            local hash = joaat(model_name)
            STREAMING.REQUEST_MODEL(hash)
            local st = util.time_ms()
            while not STREAMING.HAS_MODEL_LOADED(hash) do
                if util.time_ms() - st > 5000 then
                    notify.error("Failed to load model: " .. model_name)
                    return
                end
                script.yield(10)
            end
            PLAYER.SET_PLAYER_MODEL(self.get_id(), hash)
            STREAMING.SET_MODEL_AS_NO_LONGER_NEEDED(hash)
            notify.success("Model applied: " .. model_name)
        end)
    end

    local freemode_menu = gui.add_submenu("Freemode Models", "Standard online models")
    gui.set_submenu_context(freemode_menu)
    gui.add_option("Male Freemode", "Default male", function() handle_model_spawn("mp_m_freemode_01") end)
    gui.add_option("Female Freemode", "Default female", function() handle_model_spawn("mp_f_freemode_01") end)
    gui.set_submenu_context(model_menu)

    local animal_menu = gui.add_submenu("Animals", "Play as an animal")
    gui.set_submenu_context(animal_menu)
    gui.add_option("Chimp", "Ape", function() handle_model_spawn("a_c_chimp") end)
    gui.add_option("Chop (Dog)", "Franklin's dog", function() handle_model_spawn("a_c_chop") end)
    gui.add_option("Cat", "Meow", function() handle_model_spawn("a_c_cat_01") end)
    gui.add_option("Cow", "Moo", function() handle_model_spawn("a_c_cow") end)
    gui.add_option("Coyote", "Wild dog", function() handle_model_spawn("a_c_coyote") end)
    gui.set_submenu_context(model_menu)

    local story_menu = gui.add_submenu("Story Characters", "Protagonists")
    gui.set_submenu_context(story_menu)
    gui.add_option("Michael", "De Santa", function() handle_model_spawn("player_zero") end)
    gui.add_option("Franklin", "Clinton", function() handle_model_spawn("player_one") end)
    gui.add_option("Trevor", "Philips", function() handle_model_spawn("player_two") end)
    gui.set_submenu_context(model_menu)

    local roleplay_menu = gui.add_submenu("Roleplay / Misc", "Fun models")
    gui.set_submenu_context(roleplay_menu)
    gui.add_option("Cop", "LSPD Officer", function() handle_model_spawn("s_m_y_cop_01") end)
    gui.add_option("SWAT", "NOOSE", function() handle_model_spawn("s_m_y_swat_01") end)
    gui.add_option("Alien", "UFO Pilot", function() handle_model_spawn("u_m_y_alien_01") end)
    gui.add_option("Space Monkey", "Go go space monkey", function() handle_model_spawn("u_m_y_rsranger_01") end)
    gui.set_submenu_context(self_menu)

    local outfit_menu = gui.add_submenu("Outfit Changer", "Customize your clothing")
    gui.set_submenu_context(outfit_menu)
    local presets_menu = gui.add_submenu("Presets", "Quick outfits")
    gui.set_submenu_context(presets_menu)
    gui.add_option("Randomize Outfit", "Mix all components", function()
        local ped = self.get_ped()
        for i = 0, 11 do
            local max = PED.GET_NUMBER_OF_PED_DRAWABLE_VARIATIONS(ped, i) - 1
            if max > 0 then
                local r = math.random(0, max)
                PED.SET_PED_COMPONENT_VARIATION(ped, i, r, 0, 0)
                state.outfit["comp_" .. i].value = r
                state.outfit["prev_comp_" .. i] = r
            end
        end
        notify.success("Outfit randomized")
    end)
    gui.add_option("Invisible Body", "Hides torso and arms", function()
        local ped = self.get_ped()
        PED.SET_PED_COMPONENT_VARIATION(ped, 3, 15, 0, 0)
        PED.SET_PED_COMPONENT_VARIATION(ped, 8, 15, 0, 0)
        PED.SET_PED_COMPONENT_VARIATION(ped, 11, 15, 0, 0)
        state.outfit.comp_3.value = 15; state.outfit.prev_comp_3 = 15
        state.outfit.comp_8.value = 15; state.outfit.prev_comp_8 = 15
        state.outfit.comp_11.value = 15; state.outfit.prev_comp_11 = 15
        notify.success("Applied Invisible Body")
    end)
    gui.add_option("Naked / Base", "Default underwear", function()
        local ped = self.get_ped()
        for i = 0, 11 do
            PED.SET_PED_COMPONENT_VARIATION(ped, i, 0, 0, 0)
            state.outfit["comp_" .. i].value = 0
            state.outfit["prev_comp_" .. i] = 0
        end
        notify.success("Applied Naked Outfit")
    end)
    gui.set_submenu_context(outfit_menu)

    gui.add_break("Components (0-600)")
    gui.add_number_option("Face / Head", "Head shape", state.outfit.comp_0, 0, 600, 1)
    gui.add_number_option("Masks", "Face covers", state.outfit.comp_1, 0, 600, 1)
    gui.add_number_option("Hair", "Hairstyle", state.outfit.comp_2, 0, 600, 1)
    gui.add_number_option("Torso / Arms", "Upper body base", state.outfit.comp_3, 0, 600, 1)
    gui.add_number_option("Legs / Pants", "Trousers", state.outfit.comp_4, 0, 600, 1)
    gui.add_number_option("Bags / Parachutes", "Backpacks", state.outfit.comp_5, 0, 600, 1)
    gui.add_number_option("Shoes", "Footwear", state.outfit.comp_6, 0, 600, 1)
    gui.add_number_option("Accessories / Neck", "Scarves and chains", state.outfit.comp_7, 0, 600, 1)
    gui.add_number_option("Undershirts", "Under jacket top", state.outfit.comp_8, 0, 600, 1)
    gui.add_number_option("Body Armor", "Kevlar vests", state.outfit.comp_9, 0, 600, 1)
    gui.add_number_option("Decals / Logos", "Shirt prints", state.outfit.comp_10, 0, 600, 1)
    gui.add_number_option("Tops / Jackets", "Outer torso", state.outfit.comp_11, 0, 600, 1)
    gui.set_submenu_context(self_menu)
    gui.add_break("Quick Actions")
    gui.add_option("Heal & Max Armor", "Restores health and gives maximum armor", function()
        self.set_health(self.get_max_health())
        self.set_armor(50)
        PED.CLEAR_PED_BLOOD_DAMAGE(self.get_ped())
        notify.success("Player restored.")
    end)
    gui.add_option("Suicide", "Take the easy way out", function()
        self.set_health(0)
        notify.info("Wasted.")
    end)

    gui.add_break("Animations")
    local animate_menu = gui.add_submenu("Animate", "Player animations and scenarios")
    gui.set_submenu_context(animate_menu)

    local anims_menu = gui.add_submenu("Animations", "Play specific animations")
    gui.set_submenu_context(anims_menu)
    gui.add_bool_option("Walkable Animations", "Allow walking while animating", state.walkable_animations)
    gui.add_option("Stop Animation", "Clear current tasks", function()
        TASK.CLEAR_PED_TASKS(self.get_ped())
    end)
    gui.add_option("Pole Dance", "Dancing on a pole", function()
        script.run_in_fiber(function()
            local dict = "mini@strip_club@pole_dance@pole_a_2_stage"
            local anim = "pole_a_2_stage"
            STREAMING.REQUEST_ANIM_DICT(dict)
            local start_time = util.time_ms()
            while not STREAMING.HAS_ANIM_DICT_LOADED(dict) do
                if util.time_ms() - start_time > 5000 then
                    notify.error("Failed to load animation: " .. dict)
                    return
                end
                script.yield(10)
            end
            local flag = state.walkable_animations.value and 49 or 1
            TASK.TASK_PLAY_ANIM(self.get_ped(), dict, anim, 8.0, -8.0, -1, flag, 0.0, false, false, false)
        end)
    end)
    gui.add_option("Push Ups", "Workout animation", function()
        script.run_in_fiber(function()
            local dict = "amb@world_human_push_ups@male@base"
            local anim = "base"
            STREAMING.REQUEST_ANIM_DICT(dict)
            local start_time = util.time_ms()
            while not STREAMING.HAS_ANIM_DICT_LOADED(dict) do
                if util.time_ms() - start_time > 5000 then
                    notify.error("Failed to load animation: " .. dict)
                    return
                end
                script.yield(10)
            end
            local flag = state.walkable_animations.value and 49 or 1
            TASK.TASK_PLAY_ANIM(self.get_ped(), dict, anim, 8.0, -8.0, -1, flag, 0.0, false, false, false)
        end)
    end)
    gui.add_option("Drink Beer", "Drinking animation", function()
        script.run_in_fiber(function()
            local dict = "amb@world_human_drinking@beer@male@idle_a"
            local anim = "idle_a"
            STREAMING.REQUEST_ANIM_DICT(dict)
            local start_time = util.time_ms()
            while not STREAMING.HAS_ANIM_DICT_LOADED(dict) do
                if util.time_ms() - start_time > 5000 then
                    notify.error("Failed to load animation: " .. dict)
                    return
                end
                script.yield(10)
            end
            local flag = state.walkable_animations.value and 49 or 1
            TASK.TASK_PLAY_ANIM(self.get_ped(), dict, anim, 8.0, -8.0, -1, flag, 0.0, false, false, false)
        end)
    end)
    gui.add_option("Cheering", "Cheer animation", function()
        script.run_in_fiber(function()
            local dict = "amb@world_human_cheering@male_a"
            local anim = "base"
            STREAMING.REQUEST_ANIM_DICT(dict)
            local start_time = util.time_ms()
            while not STREAMING.HAS_ANIM_DICT_LOADED(dict) do
                if util.time_ms() - start_time > 5000 then
                    notify.error("Failed to load animation: " .. dict)
                    return
                end
                script.yield(10)
            end
            local flag = state.walkable_animations.value and 49 or 1
            TASK.TASK_PLAY_ANIM(self.get_ped(), dict, anim, 8.0, -8.0, -1, flag, 0.0, false, false, false)
        end)
    end)
    gui.add_option("Cowering", "Cower animation", function()
        script.run_in_fiber(function()
            local dict = "amb@code_human_cower@female@base"
            local anim = "base"
            STREAMING.REQUEST_ANIM_DICT(dict)
            local start_time = util.time_ms()
            while not STREAMING.HAS_ANIM_DICT_LOADED(dict) do
                if util.time_ms() - start_time > 5000 then
                    notify.error("Failed to load animation: " .. dict)
                    return
                end
                script.yield(10)
            end
            local flag = state.walkable_animations.value and 49 or 1
            TASK.TASK_PLAY_ANIM(self.get_ped(), dict, anim, 8.0, -8.0, -1, flag, 0.0, false, false, false)
        end)
    end)

    gui.set_submenu_context(animate_menu)
    local scenarios_menu = gui.add_submenu("Scenarios", "Play world scenarios")
    gui.set_submenu_context(scenarios_menu)
    gui.add_option("Stop Scenario", "Clear current tasks", function()
        TASK.CLEAR_PED_TASKS(self.get_ped())
    end)
    gui.add_option("Drink Coffee", "Drink a cup of coffee", function()
        TASK.TASK_START_SCENARIO_IN_PLACE(self.get_ped(), "WORLD_HUMAN_AA_COFFEE", 0, true)
    end)
    gui.add_option("Muscle Flex", "Flex your muscles", function()
        TASK.TASK_START_SCENARIO_IN_PLACE(self.get_ped(), "WORLD_HUMAN_MUSCLE_FLEX", 0, true)
    end)
    gui.add_option("Paparazzi", "Take pictures", function()
        TASK.TASK_START_SCENARIO_IN_PLACE(self.get_ped(), "WORLD_HUMAN_PAPARAZZI", 0, true)
    end)
    gui.add_option("Guard Stand", "Stand like a guard", function()
        TASK.TASK_START_SCENARIO_IN_PLACE(self.get_ped(), "WORLD_HUMAN_GUARD_STAND", 0, true)
    end)
    gui.add_option("Jogging", "Go for a jog", function()
        TASK.TASK_START_SCENARIO_IN_PLACE(self.get_ped(), "WORLD_HUMAN_JOG", 0, true)
    end)
    gui.add_option("Fishing", "Stand and fish", function()
        TASK.TASK_START_SCENARIO_IN_PLACE(self.get_ped(), "WORLD_HUMAN_STAND_FISHING", 0, true)
    end)
    gui.add_option("Binoculars", "Look through binoculars", function()
        TASK.TASK_START_SCENARIO_IN_PLACE(self.get_ped(), "WORLD_HUMAN_BINOCULARS", 0, true)
    end)

    gui.reset_submenu_context()

    -- Submenu: Vehicle Options
    local veh_menu = gui.add_submenu("Vehicle Options", "Modifications for vehicles")
    gui.set_submenu_context(veh_menu)
    gui.add_bool_option("Vehicle Godmode", "Prevents visual and mechanical damage", state.veh_godmode)
    gui.add_bool_option("Horn Boost", "Apply forward thrust when honking", state.veh_horn_boost)

    gui.add_break("Quick Actions")
    gui.add_option("Repair & Clean", "Fixes current vehicle completely", function()
        local veh = self.get_veh()
        if veh ~= 0 then
            VEHICLE.SET_VEHICLE_FIXED(veh)
            VEHICLE.SET_VEHICLE_DIRT_LEVEL(veh, 0.0)
            notify.success("Vehicle repaired and cleaned.")
        else
            notify.warning("You must be in a vehicle.")
        end
    end)
    gui.add_option("Spawn T20", "Spawns a Progen T20 directly into your control", function()
        handle_vehicle_spawn("T20", "t20")
    end)

    gui.add_break("Vehicle Mods")
    gui.add_bool_option("Vehicle Godmode", "Invincible car", state.vehicle_godmode)
    gui.add_bool_option("Invisible Vehicle", "Invisible car", state.invisible_vehicle)
    gui.add_bool_option("Engine Always On", "Keep engine running when exiting", state.engine_always_on)
    gui.add_bool_option("Horn Boost", "Hold horn to boost forward", state.horn_boost)
    gui.add_option("Max Upgrades", "Apply full upgrades instantly", function()
        local veh = self.get_veh()
        if veh ~= 0 then
            VEHICLE.SET_VEHICLE_MOD_KIT(veh, 0)
            for i = 0, 49 do
                local max = VEHICLE.GET_NUM_VEHICLE_MODS(veh, i) - 1
                VEHICLE.SET_VEHICLE_MOD(veh, i, max, false)
            end
            notify.success("Vehicle fully upgraded!")
        else
            notify.warning("You must be in a vehicle.")
        end
    end)
    gui.add_option("Custom License Plate (ETHEREAL)", "Change plate text", function()
        local veh = self.get_veh()
        if veh ~= 0 then
            VEHICLE.SET_VEHICLE_NUMBER_PLATE_TEXT(veh, "ETHEREAL")
            notify.success("Plate updated.")
        end
    end)
    gui.add_option("Flip Vehicle", "Unflip your vehicle", function()
        local veh = self.get_veh()
        if veh ~= 0 then
            local rot = ENTITY.GET_ENTITY_ROTATION(veh, 2)
            ENTITY.SET_ENTITY_ROTATION(veh, 0.0, rot.y, rot.z, 2, true)
            notify.success("Vehicle flipped.")
        end
    end)
    gui.add_break("Vehicle Spawner")
    local spawner_menu = gui.add_submenu("Vehicle Spawner", "Spawn vehicles with 3D previews")
    gui.set_submenu_context(spawner_menu)
    local super_menu = gui.add_submenu("Super", "Super vehicles")
    gui.set_submenu_context(super_menu)
    local super_launchmodels_menu = gui.add_submenu("Launch Models", "Launch Models update")
    gui.set_submenu_context(super_launchmodels_menu)
    gui.add_option("adder", "Spawn adder", function() handle_vehicle_spawn("adder", "adder") end)
    gui.add_option("bullet", "Spawn bullet", function() handle_vehicle_spawn("bullet", "bullet") end)
    gui.add_option("cheetah", "Spawn cheetah", function() handle_vehicle_spawn("cheetah", "cheetah") end)
    gui.add_option("entityxf", "Spawn entityxf", function() handle_vehicle_spawn("entityxf", "entityxf") end)
    gui.add_option("infernus", "Spawn infernus", function() handle_vehicle_spawn("infernus", "infernus") end)
    gui.add_option("vacca", "Spawn vacca", function() handle_vehicle_spawn("vacca", "vacca") end)
    gui.add_option("voltic", "Spawn voltic", function() handle_vehicle_spawn("voltic", "voltic") end)
    gui.set_submenu_context(super_menu)
    local super_doomsdayheist_menu = gui.add_submenu("Doomsday Heist", "Doomsday Heist update")
    gui.set_submenu_context(super_doomsdayheist_menu)
    gui.add_option("autarch", "Spawn autarch", function() handle_vehicle_spawn("autarch", "autarch") end)
    gui.add_option("sc1", "Spawn sc1", function() handle_vehicle_spawn("sc1", "sc1") end)
    gui.set_submenu_context(super_menu)
    local super_january2016_menu = gui.add_submenu("January2016", "January2016 update")
    gui.set_submenu_context(super_january2016_menu)
    gui.add_option("banshee2", "Spawn banshee2", function() handle_vehicle_spawn("banshee2", "banshee2") end)
    gui.add_option("sultanrs", "Spawn sultanrs", function() handle_vehicle_spawn("sultanrs", "sultanrs") end)
    gui.set_submenu_context(super_menu)
    local super_security_menu = gui.add_submenu("Security", "Security update")
    gui.set_submenu_context(super_security_menu)
    gui.add_option("champion", "Spawn champion", function() handle_vehicle_spawn("champion", "champion") end)
    gui.add_option("ignus", "Spawn ignus", function() handle_vehicle_spawn("ignus", "ignus") end)
    gui.add_option("zeno", "Spawn zeno", function() handle_vehicle_spawn("zeno", "zeno") end)
    gui.set_submenu_context(super_menu)
    local super_smugglersrun_menu = gui.add_submenu("Smugglers Run", "Smugglers Run update")
    gui.set_submenu_context(super_smugglersrun_menu)
    gui.add_option("cyclone", "Spawn cyclone", function() handle_vehicle_spawn("cyclone", "cyclone") end)
    gui.add_option("vigilante", "Spawn vigilante", function() handle_vehicle_spawn("vigilante", "vigilante") end)
    gui.add_option("visione", "Spawn visione", function() handle_vehicle_spawn("visione", "visione") end)
    gui.set_submenu_context(super_menu)
    local super_g9ec_menu = gui.add_submenu("G9ec", "G9ec update")
    gui.set_submenu_context(super_g9ec_menu)
    gui.add_option("cyclone2", "Spawn cyclone2", function() handle_vehicle_spawn("cyclone2", "cyclone2") end)
    gui.add_option("ignus2", "Spawn ignus2", function() handle_vehicle_spawn("ignus2", "ignus2") end)
    gui.set_submenu_context(super_menu)
    local super_christmas2018_menu = gui.add_submenu("Christmas2018", "Christmas2018 update")
    gui.set_submenu_context(super_christmas2018_menu)
    gui.add_option("deveste", "Spawn deveste", function() handle_vehicle_spawn("deveste", "deveste") end)
    gui.set_submenu_context(super_menu)
    local super_vinewood_menu = gui.add_submenu("Vinewood", "Vinewood update")
    gui.set_submenu_context(super_vinewood_menu)
    gui.add_option("emerus", "Spawn emerus", function() handle_vehicle_spawn("emerus", "emerus") end)
    gui.add_option("krieger", "Spawn krieger", function() handle_vehicle_spawn("krieger", "krieger") end)
    gui.add_option("s80", "Spawn s80", function() handle_vehicle_spawn("s80", "s80") end)
    gui.add_option("thrax", "Spawn thrax", function() handle_vehicle_spawn("thrax", "thrax") end)
    gui.add_option("zorrusso", "Spawn zorrusso", function() handle_vehicle_spawn("zorrusso", "zorrusso") end)
    gui.set_submenu_context(super_menu)
    local super_assault_menu = gui.add_submenu("Assault", "Assault update")
    gui.set_submenu_context(super_assault_menu)
    gui.add_option("entity2", "Spawn entity2", function() handle_vehicle_spawn("entity2", "entity2") end)
    gui.add_option("taipan", "Spawn taipan", function() handle_vehicle_spawn("taipan", "taipan") end)
    gui.add_option("tezeract", "Spawn tezeract", function() handle_vehicle_spawn("tezeract", "tezeract") end)
    gui.add_option("tyrant", "Spawn tyrant", function() handle_vehicle_spawn("tyrant", "tyrant") end)
    gui.set_submenu_context(super_menu)
    local super_christmas3_menu = gui.add_submenu("Christmas3", "Christmas3 update")
    gui.set_submenu_context(super_christmas3_menu)
    gui.add_option("entity3", "Spawn entity3", function() handle_vehicle_spawn("entity3", "entity3") end)
    gui.add_option("virtue", "Spawn virtue", function() handle_vehicle_spawn("virtue", "virtue") end)
    gui.set_submenu_context(super_menu)
    local super_executives_menu = gui.add_submenu("Executives", "Executives update")
    gui.set_submenu_context(super_executives_menu)
    gui.add_option("fmj", "Spawn fmj", function() handle_vehicle_spawn("fmj", "fmj") end)
    gui.add_option("pfister811", "Spawn pfister811", function() handle_vehicle_spawn("pfister811", "pfister811") end)
    gui.add_option("prototipo", "Spawn prototipo", function() handle_vehicle_spawn("prototipo", "prototipo") end)
    gui.add_option("reaper", "Spawn reaper", function() handle_vehicle_spawn("reaper", "reaper") end)
    gui.set_submenu_context(super_menu)
    local super_202502_menu = gui.add_submenu("2025 02", "2025 02 update")
    gui.set_submenu_context(super_202502_menu)
    gui.add_option("fmj2", "Spawn fmj2", function() handle_vehicle_spawn("fmj2", "fmj2") end)
    gui.add_option("luiva", "Spawn luiva", function() handle_vehicle_spawn("luiva", "luiva") end)
    gui.add_option("xtreme", "Spawn xtreme", function() handle_vehicle_spawn("xtreme", "xtreme") end)
    gui.set_submenu_context(super_menu)
    local super_casinoheist_menu = gui.add_submenu("Casino Heist", "Casino Heist update")
    gui.set_submenu_context(super_casinoheist_menu)
    gui.add_option("furia", "Spawn furia", function() handle_vehicle_spawn("furia", "furia") end)
    gui.set_submenu_context(super_menu)
    local super_specialraces_menu = gui.add_submenu("Specialraces", "Specialraces update")
    gui.set_submenu_context(super_specialraces_menu)
    gui.add_option("gp1", "Spawn gp1", function() handle_vehicle_spawn("gp1", "gp1") end)
    gui.set_submenu_context(super_menu)
    local super_importexport_menu = gui.add_submenu("Import/Export", "Import/Export update")
    gui.set_submenu_context(super_importexport_menu)
    gui.add_option("italigtb", "Spawn italigtb", function() handle_vehicle_spawn("italigtb", "italigtb") end)
    gui.add_option("italigtb2", "Spawn italigtb2", function() handle_vehicle_spawn("italigtb2", "italigtb2") end)
    gui.add_option("nero", "Spawn nero", function() handle_vehicle_spawn("nero", "nero") end)
    gui.add_option("nero2", "Spawn nero2", function() handle_vehicle_spawn("nero2", "nero2") end)
    gui.add_option("penetrator", "Spawn penetrator", function() handle_vehicle_spawn("penetrator", "penetrator") end)
    gui.add_option("tempesta", "Spawn tempesta", function() handle_vehicle_spawn("tempesta", "tempesta") end)
    gui.add_option("voltic2", "Spawn voltic2", function() handle_vehicle_spawn("voltic2", "voltic2") end)
    gui.set_submenu_context(super_menu)
    local super_stunt_menu = gui.add_submenu("Stunt", "Stunt update")
    gui.set_submenu_context(super_stunt_menu)
    gui.add_option("le7b", "Spawn le7b", function() handle_vehicle_spawn("le7b", "le7b") end)
    gui.add_option("sheava", "Spawn sheava", function() handle_vehicle_spawn("sheava", "sheava") end)
    gui.add_option("tyrus", "Spawn tyrus", function() handle_vehicle_spawn("tyrus", "tyrus") end)
    gui.set_submenu_context(super_menu)
    local super_sum2_menu = gui.add_submenu("Sum2", "Sum2 update")
    gui.set_submenu_context(super_sum2_menu)
    gui.add_option("lm87", "Spawn lm87", function() handle_vehicle_spawn("lm87", "lm87") end)
    gui.add_option("torero2", "Spawn torero2", function() handle_vehicle_spawn("torero2", "torero2") end)
    gui.set_submenu_context(super_menu)
    local super_luxe_menu = gui.add_submenu("Luxe", "Luxe update")
    gui.set_submenu_context(super_luxe_menu)
    gui.add_option("osiris", "Spawn osiris", function() handle_vehicle_spawn("osiris", "osiris") end)
    gui.set_submenu_context(super_menu)
    local super_bottomdollarbounties_menu = gui.add_submenu("Bottom Dollar Bounties", "Bottom Dollar Bounties update")
    gui.set_submenu_context(super_bottomdollarbounties_menu)
    gui.add_option("pipistrello", "Spawn pipistrello", function() handle_vehicle_spawn("pipistrello", "pipistrello") end)
    gui.set_submenu_context(super_menu)
    local super_battle_menu = gui.add_submenu("Battle", "Battle update")
    gui.set_submenu_context(super_battle_menu)
    gui.add_option("scramjet", "Spawn scramjet", function() handle_vehicle_spawn("scramjet", "scramjet") end)
    gui.set_submenu_context(super_menu)
    local super_202501_menu = gui.add_submenu("2025 01", "2025 01 update")
    gui.set_submenu_context(super_202501_menu)
    gui.add_option("suzume", "Spawn suzume", function() handle_vehicle_spawn("suzume", "suzume") end)
    gui.set_submenu_context(super_menu)
    local super_luxe2_menu = gui.add_submenu("Luxe2", "Luxe2 update")
    gui.set_submenu_context(super_luxe2_menu)
    gui.add_option("t20", "Spawn t20", function() handle_vehicle_spawn("t20", "t20") end)
    gui.set_submenu_context(super_menu)
    local super_sum_menu = gui.add_submenu("Sum", "Sum update")
    gui.set_submenu_context(super_sum_menu)
    gui.add_option("tigon", "Spawn tigon", function() handle_vehicle_spawn("tigon", "tigon") end)
    gui.set_submenu_context(super_menu)
    local super_thechopshop_menu = gui.add_submenu("The Chop Shop", "The Chop Shop update")
    gui.set_submenu_context(super_thechopshop_menu)
    gui.add_option("turismo3", "Spawn turismo3", function() handle_vehicle_spawn("turismo3", "turismo3") end)
    gui.set_submenu_context(super_menu)
    local super_business_menu = gui.add_submenu("Business", "Business update")
    gui.set_submenu_context(super_business_menu)
    gui.add_option("turismor", "Spawn turismor", function() handle_vehicle_spawn("turismor", "turismor") end)
    gui.set_submenu_context(super_menu)
    local super_gunrunning_menu = gui.add_submenu("Gunrunning", "Gunrunning update")
    gui.set_submenu_context(super_gunrunning_menu)
    gui.add_option("vagner", "Spawn vagner", function() handle_vehicle_spawn("vagner", "vagner") end)
    gui.add_option("xa21", "Spawn xa21", function() handle_vehicle_spawn("xa21", "xa21") end)
    gui.set_submenu_context(super_menu)
    local super_business2_menu = gui.add_submenu("Business2", "Business2 update")
    gui.set_submenu_context(super_business2_menu)
    gui.add_option("zentorno", "Spawn zentorno", function() handle_vehicle_spawn("zentorno", "zentorno") end)

    gui.set_submenu_context(spawner_menu)
    local service_menu = gui.add_submenu("Service", "Service vehicles")
    gui.set_submenu_context(service_menu)
    local service_launchmodels_menu = gui.add_submenu("Launch Models", "Launch Models update")
    gui.set_submenu_context(service_launchmodels_menu)
    gui.add_option("Airbus", "Spawn Airbus", function() handle_vehicle_spawn("Airbus", "airbus") end)
    gui.add_option("BUS", "Spawn BUS", function() handle_vehicle_spawn("BUS", "bus") end)
    gui.add_option("coach", "Spawn coach", function() handle_vehicle_spawn("coach", "coach") end)
    gui.add_option("Rentalbus", "Spawn Rentalbus", function() handle_vehicle_spawn("Rentalbus", "rentalbus") end)
    gui.add_option("taxi", "Spawn taxi", function() handle_vehicle_spawn("taxi", "taxi") end)
    gui.add_option("TOURBUS", "Spawn TOURBUS", function() handle_vehicle_spawn("TOURBUS", "tourbus") end)
    gui.add_option("Trash", "Spawn Trash", function() handle_vehicle_spawn("Trash", "trash") end)
    gui.set_submenu_context(service_menu)
    local service_executives_menu = gui.add_submenu("Executives", "Executives update")
    gui.set_submenu_context(service_executives_menu)
    gui.add_option("brickade", "Spawn brickade", function() handle_vehicle_spawn("brickade", "brickade") end)
    gui.set_submenu_context(service_menu)
    local service_christmas3_menu = gui.add_submenu("Christmas3", "Christmas3 update")
    gui.set_submenu_context(service_christmas3_menu)
    gui.add_option("brickade2", "Spawn brickade2", function() handle_vehicle_spawn("brickade2", "brickade2") end)
    gui.set_submenu_context(service_menu)
    local service_battle_menu = gui.add_submenu("Battle", "Battle update")
    gui.set_submenu_context(service_battle_menu)
    gui.add_option("pbus2", "Spawn pbus2", function() handle_vehicle_spawn("pbus2", "pbus2") end)
    gui.set_submenu_context(service_menu)
    local service_stunt_menu = gui.add_submenu("Stunt", "Stunt update")
    gui.set_submenu_context(service_stunt_menu)
    gui.add_option("rallytruck", "Spawn rallytruck", function() handle_vehicle_spawn("rallytruck", "rallytruck") end)
    gui.set_submenu_context(service_menu)
    local service_heist_menu = gui.add_submenu("Heist", "Heist update")
    gui.set_submenu_context(service_heist_menu)
    gui.add_option("trash2", "Spawn trash2", function() handle_vehicle_spawn("trash2", "trash2") end)
    gui.set_submenu_context(service_menu)
    local service_202502_menu = gui.add_submenu("2025 02", "2025 02 update")
    gui.set_submenu_context(service_202502_menu)
    gui.add_option("vivanite2", "Spawn vivanite2", function() handle_vehicle_spawn("vivanite2", "vivanite2") end)
    gui.set_submenu_context(service_menu)
    local service_importexport_menu = gui.add_submenu("Import/Export", "Import/Export update")
    gui.set_submenu_context(service_importexport_menu)
    gui.add_option("wastelander", "Spawn wastelander", function() handle_vehicle_spawn("wastelander", "wastelander") end)

    gui.set_submenu_context(spawner_menu)
    local utility_menu = gui.add_submenu("Utility", "Utility vehicles")
    gui.set_submenu_context(utility_menu)
    local utility_launchmodels_menu = gui.add_submenu("Launch Models", "Launch Models update")
    gui.set_submenu_context(utility_launchmodels_menu)
    gui.add_option("Airtug", "Spawn Airtug", function() handle_vehicle_spawn("Airtug", "airtug") end)
    gui.add_option("armytanker", "Spawn armytanker", function() handle_vehicle_spawn("armytanker", "armytanker") end)
    gui.add_option("armytrailer", "Spawn armytrailer", function() handle_vehicle_spawn("armytrailer", "armytrailer") end)
    gui.add_option("armytrailer2", "Spawn armytrailer2",
        function() handle_vehicle_spawn("armytrailer2", "armytrailer2") end)
    gui.add_option("baletrailer", "Spawn baletrailer", function() handle_vehicle_spawn("baletrailer", "baletrailer") end)
    gui.add_option("boattrailer", "Spawn boattrailer", function() handle_vehicle_spawn("boattrailer", "boattrailer") end)
    gui.add_option("caddy", "Spawn caddy", function() handle_vehicle_spawn("caddy", "caddy") end)
    gui.add_option("Caddy2", "Spawn Caddy2", function() handle_vehicle_spawn("Caddy2", "caddy2") end)
    gui.add_option("docktrailer", "Spawn docktrailer", function() handle_vehicle_spawn("docktrailer", "docktrailer") end)
    gui.add_option("docktug", "Spawn docktug", function() handle_vehicle_spawn("docktug", "docktug") end)
    gui.add_option("FORKLIFT", "Spawn FORKLIFT", function() handle_vehicle_spawn("FORKLIFT", "forklift") end)
    gui.add_option("freighttrailer", "Spawn freighttrailer",
        function() handle_vehicle_spawn("freighttrailer", "freighttrailer") end)
    gui.add_option("graintrailer", "Spawn graintrailer",
        function() handle_vehicle_spawn("graintrailer", "graintrailer") end)
    gui.add_option("Mower", "Spawn Mower", function() handle_vehicle_spawn("Mower", "mower") end)
    gui.add_option("proptrailer", "Spawn proptrailer", function() handle_vehicle_spawn("proptrailer", "proptrailer") end)
    gui.add_option("raketrailer", "Spawn raketrailer", function() handle_vehicle_spawn("raketrailer", "raketrailer") end)
    gui.add_option("Ripley", "Spawn Ripley", function() handle_vehicle_spawn("Ripley", "ripley") end)
    gui.add_option("Sadler", "Spawn Sadler", function() handle_vehicle_spawn("Sadler", "sadler") end)
    gui.add_option("sadler2", "Spawn sadler2", function() handle_vehicle_spawn("sadler2", "sadler2") end)
    gui.add_option("scrap", "Spawn scrap", function() handle_vehicle_spawn("scrap", "scrap") end)
    gui.add_option("tanker", "Spawn tanker", function() handle_vehicle_spawn("tanker", "tanker") end)
    gui.add_option("TOWTRUCK", "Spawn TOWTRUCK", function() handle_vehicle_spawn("TOWTRUCK", "towtruck") end)
    gui.add_option("Towtruck2", "Spawn Towtruck2", function() handle_vehicle_spawn("Towtruck2", "towtruck2") end)
    gui.add_option("tr2", "Spawn tr2", function() handle_vehicle_spawn("tr2", "tr2") end)
    gui.add_option("tr3", "Spawn tr3", function() handle_vehicle_spawn("tr3", "tr3") end)
    gui.add_option("tr4", "Spawn tr4", function() handle_vehicle_spawn("tr4", "tr4") end)
    gui.add_option("TRACTOR", "Spawn TRACTOR", function() handle_vehicle_spawn("TRACTOR", "tractor") end)
    gui.add_option("tractor2", "Spawn tractor2", function() handle_vehicle_spawn("tractor2", "tractor2") end)
    gui.add_option("tractor3", "Spawn tractor3", function() handle_vehicle_spawn("tractor3", "tractor3") end)
    gui.add_option("trailerlogs", "Spawn trailerlogs", function() handle_vehicle_spawn("trailerlogs", "trailerlogs") end)
    gui.add_option("trailers", "Spawn trailers", function() handle_vehicle_spawn("trailers", "trailers") end)
    gui.add_option("trailers2", "Spawn trailers2", function() handle_vehicle_spawn("trailers2", "trailers2") end)
    gui.add_option("trailers3", "Spawn trailers3", function() handle_vehicle_spawn("trailers3", "trailers3") end)
    gui.add_option("trailersmall", "Spawn trailersmall",
        function() handle_vehicle_spawn("trailersmall", "trailersmall") end)
    gui.add_option("trflat", "Spawn trflat", function() handle_vehicle_spawn("trflat", "trflat") end)
    gui.add_option("tvtrailer", "Spawn tvtrailer", function() handle_vehicle_spawn("tvtrailer", "tvtrailer") end)
    gui.add_option("utillitruck", "Spawn utillitruck", function() handle_vehicle_spawn("utillitruck", "utillitruck") end)
    gui.add_option("utillitruck2", "Spawn utillitruck2",
        function() handle_vehicle_spawn("utillitruck2", "utillitruck2") end)
    gui.add_option("Utillitruck3", "Spawn Utillitruck3",
        function() handle_vehicle_spawn("Utillitruck3", "utillitruck3") end)
    gui.set_submenu_context(utility_menu)
    local utility_thechopshop_menu = gui.add_submenu("The Chop Shop", "The Chop Shop update")
    gui.set_submenu_context(utility_thechopshop_menu)
    gui.add_option("boattrailer2", "Spawn boattrailer2",
        function() handle_vehicle_spawn("boattrailer2", "boattrailer2") end)
    gui.add_option("boattrailer3", "Spawn boattrailer3",
        function() handle_vehicle_spawn("boattrailer3", "boattrailer3") end)
    gui.add_option("towtruck3", "Spawn towtruck3", function() handle_vehicle_spawn("towtruck3", "towtruck3") end)
    gui.add_option("towtruck4", "Spawn towtruck4", function() handle_vehicle_spawn("towtruck4", "towtruck4") end)
    gui.add_option("trailers5", "Spawn trailers5", function() handle_vehicle_spawn("trailers5", "trailers5") end)
    gui.add_option("tvtrailer2", "Spawn tvtrailer2", function() handle_vehicle_spawn("tvtrailer2", "tvtrailer2") end)
    gui.set_submenu_context(utility_menu)
    local utility_gunrunning_menu = gui.add_submenu("Gunrunning", "Gunrunning update")
    gui.set_submenu_context(utility_gunrunning_menu)
    gui.add_option("caddy3", "Spawn caddy3", function() handle_vehicle_spawn("caddy3", "caddy3") end)
    gui.add_option("trailerlarge", "Spawn trailerlarge",
        function() handle_vehicle_spawn("trailerlarge", "trailerlarge") end)
    gui.add_option("trailers4", "Spawn trailers4", function() handle_vehicle_spawn("trailers4", "trailers4") end)
    gui.set_submenu_context(utility_menu)
    local utility_202502_menu = gui.add_submenu("2025 02", "2025 02 update")
    gui.set_submenu_context(utility_202502_menu)
    gui.add_option("driftkeitora", "Spawn driftkeitora",
        function() handle_vehicle_spawn("driftkeitora", "driftkeitora") end)
    gui.add_option("keitora", "Spawn keitora", function() handle_vehicle_spawn("keitora", "keitora") end)
    gui.set_submenu_context(utility_menu)
    local utility_cayoperico_menu = gui.add_submenu("Cayo Perico", "Cayo Perico update")
    gui.set_submenu_context(utility_cayoperico_menu)
    gui.add_option("slamtruck", "Spawn slamtruck", function() handle_vehicle_spawn("slamtruck", "slamtruck") end)
    gui.set_submenu_context(utility_menu)
    local utility_heist_menu = gui.add_submenu("Heist", "Heist update")
    gui.set_submenu_context(utility_heist_menu)
    gui.add_option("tanker2", "Spawn tanker2", function() handle_vehicle_spawn("tanker2", "tanker2") end)

    gui.set_submenu_context(spawner_menu)
    local emergency_menu = gui.add_submenu("Emergency", "Emergency vehicles")
    gui.set_submenu_context(emergency_menu)
    local emergency_launchmodels_menu = gui.add_submenu("Launch Models", "Launch Models update")
    gui.set_submenu_context(emergency_launchmodels_menu)
    gui.add_option("AMBULANCE", "Spawn AMBULANCE", function() handle_vehicle_spawn("AMBULANCE", "ambulance") end)
    gui.add_option("FBI", "Spawn FBI", function() handle_vehicle_spawn("FBI", "fbi") end)
    gui.add_option("FBI2", "Spawn FBI2", function() handle_vehicle_spawn("FBI2", "fbi2") end)
    gui.add_option("firetruk", "Spawn firetruk", function() handle_vehicle_spawn("firetruk", "firetruk") end)
    gui.add_option("lguard", "Spawn lguard", function() handle_vehicle_spawn("lguard", "lguard") end)
    gui.add_option("pbus", "Spawn pbus", function() handle_vehicle_spawn("pbus", "pbus") end)
    gui.add_option("police", "Spawn police", function() handle_vehicle_spawn("police", "police") end)
    gui.add_option("police2", "Spawn police2", function() handle_vehicle_spawn("police2", "police2") end)
    gui.add_option("police3", "Spawn police3", function() handle_vehicle_spawn("police3", "police3") end)
    gui.add_option("police4", "Spawn police4", function() handle_vehicle_spawn("police4", "police4") end)
    gui.add_option("policeb", "Spawn policeb", function() handle_vehicle_spawn("policeb", "policeb") end)
    gui.add_option("policeold1", "Spawn policeold1", function() handle_vehicle_spawn("policeold1", "policeold1") end)
    gui.add_option("policeold2", "Spawn policeold2", function() handle_vehicle_spawn("policeold2", "policeold2") end)
    gui.add_option("policet", "Spawn policet", function() handle_vehicle_spawn("policet", "policet") end)
    gui.add_option("pRanger", "Spawn pRanger", function() handle_vehicle_spawn("pRanger", "pranger") end)
    gui.add_option("RIOT", "Spawn RIOT", function() handle_vehicle_spawn("RIOT", "riot") end)
    gui.add_option("SHERIFF", "Spawn SHERIFF", function() handle_vehicle_spawn("SHERIFF", "sheriff") end)
    gui.add_option("sheriff2", "Spawn sheriff2", function() handle_vehicle_spawn("sheriff2", "sheriff2") end)
    gui.set_submenu_context(emergency_menu)
    local emergency_202502_menu = gui.add_submenu("2025 02", "2025 02 update")
    gui.set_submenu_context(emergency_202502_menu)
    gui.add_option("polbuffalo", "Spawn polbuffalo", function() handle_vehicle_spawn("polbuffalo", "polbuffalo") end)
    gui.add_option("polbuffalo6", "Spawn polbuffalo6", function() handle_vehicle_spawn("polbuffalo6", "polbuffalo6") end)
    gui.set_submenu_context(emergency_menu)
    local emergency_agentsofsabotage_menu = gui.add_submenu("Agents of Sabotage", "Agents of Sabotage update")
    gui.set_submenu_context(emergency_agentsofsabotage_menu)
    gui.add_option("polcaracara", "Spawn polcaracara", function() handle_vehicle_spawn("polcaracara", "polcaracara") end)
    gui.add_option("polcoquette4", "Spawn polcoquette4",
        function() handle_vehicle_spawn("polcoquette4", "polcoquette4") end)
    gui.add_option("polfaction2", "Spawn polfaction2", function() handle_vehicle_spawn("polfaction2", "polfaction2") end)
    gui.add_option("polterminus", "Spawn polterminus", function() handle_vehicle_spawn("polterminus", "polterminus") end)
    gui.set_submenu_context(emergency_menu)
    local emergency_bottomdollarbounties_menu = gui.add_submenu("Bottom Dollar Bounties", "Bottom Dollar Bounties update")
    gui.set_submenu_context(emergency_bottomdollarbounties_menu)
    gui.add_option("poldominator10", "Spawn poldominator10",
        function() handle_vehicle_spawn("poldominator10", "poldominator10") end)
    gui.add_option("poldorado", "Spawn poldorado", function() handle_vehicle_spawn("poldorado", "poldorado") end)
    gui.add_option("polgreenwood", "Spawn polgreenwood",
        function() handle_vehicle_spawn("polgreenwood", "polgreenwood") end)
    gui.add_option("policet3", "Spawn policet3", function() handle_vehicle_spawn("policet3", "policet3") end)
    gui.add_option("polimpaler5", "Spawn polimpaler5", function() handle_vehicle_spawn("polimpaler5", "polimpaler5") end)
    gui.add_option("polimpaler6", "Spawn polimpaler6", function() handle_vehicle_spawn("polimpaler6", "polimpaler6") end)
    gui.set_submenu_context(emergency_menu)
    local emergency_thechopshop_menu = gui.add_submenu("The Chop Shop", "The Chop Shop update")
    gui.set_submenu_context(emergency_thechopshop_menu)
    gui.add_option("polgauntlet", "Spawn polgauntlet", function() handle_vehicle_spawn("polgauntlet", "polgauntlet") end)
    gui.add_option("police5", "Spawn police5", function() handle_vehicle_spawn("police5", "police5") end)
    gui.set_submenu_context(emergency_menu)
    local emergency_202501_menu = gui.add_submenu("2025 01", "2025 01 update")
    gui.set_submenu_context(emergency_202501_menu)
    gui.add_option("policeb2", "Spawn policeb2", function() handle_vehicle_spawn("policeb2", "policeb2") end)
    gui.set_submenu_context(emergency_menu)
    local emergency_doomsdayheist_menu = gui.add_submenu("Doomsday Heist", "Doomsday Heist update")
    gui.set_submenu_context(emergency_doomsdayheist_menu)
    gui.add_option("riot2", "Spawn riot2", function() handle_vehicle_spawn("riot2", "riot2") end)

    gui.set_submenu_context(spawner_menu)
    local military_menu = gui.add_submenu("Military", "Military vehicles")
    gui.set_submenu_context(military_menu)
    local military_gunrunning_menu = gui.add_submenu("Gunrunning", "Gunrunning update")
    gui.set_submenu_context(military_gunrunning_menu)
    gui.add_option("apc", "Spawn apc", function() handle_vehicle_spawn("apc", "apc") end)
    gui.add_option("halftrack", "Spawn halftrack", function() handle_vehicle_spawn("halftrack", "halftrack") end)
    gui.add_option("trailersmall2", "Spawn trailersmall2",
        function() handle_vehicle_spawn("trailersmall2", "trailersmall2") end)
    gui.set_submenu_context(military_menu)
    local military_launchmodels_menu = gui.add_submenu("Launch Models", "Launch Models update")
    gui.set_submenu_context(military_launchmodels_menu)
    gui.add_option("BARRACKS", "Spawn BARRACKS", function() handle_vehicle_spawn("BARRACKS", "barracks") end)
    gui.add_option("BARRACKS2", "Spawn BARRACKS2", function() handle_vehicle_spawn("BARRACKS2", "barracks2") end)
    gui.add_option("CRUSADER", "Spawn CRUSADER", function() handle_vehicle_spawn("CRUSADER", "crusader") end)
    gui.add_option("RHINO", "Spawn RHINO", function() handle_vehicle_spawn("RHINO", "rhino") end)
    gui.set_submenu_context(military_menu)
    local military_heist_menu = gui.add_submenu("Heist", "Heist update")
    gui.set_submenu_context(military_heist_menu)
    gui.add_option("BARRACKS3", "Spawn BARRACKS3", function() handle_vehicle_spawn("BARRACKS3", "barracks3") end)
    gui.set_submenu_context(military_menu)
    local military_doomsdayheist_menu = gui.add_submenu("Doomsday Heist", "Doomsday Heist update")
    gui.set_submenu_context(military_doomsdayheist_menu)
    gui.add_option("barrage", "Spawn barrage", function() handle_vehicle_spawn("barrage", "barrage") end)
    gui.add_option("chernobog", "Spawn chernobog", function() handle_vehicle_spawn("chernobog", "chernobog") end)
    gui.add_option("khanjali", "Spawn khanjali", function() handle_vehicle_spawn("khanjali", "khanjali") end)
    gui.add_option("thruster", "Spawn thruster", function() handle_vehicle_spawn("thruster", "thruster") end)
    gui.set_submenu_context(military_menu)
    local military_casinoheist_menu = gui.add_submenu("Casino Heist", "Casino Heist update")
    gui.set_submenu_context(military_casinoheist_menu)
    gui.add_option("minitank", "Spawn minitank", function() handle_vehicle_spawn("minitank", "minitank") end)
    gui.set_submenu_context(military_menu)
    local military_christmas2018_menu = gui.add_submenu("Christmas2018", "Christmas2018 update")
    gui.set_submenu_context(military_christmas2018_menu)
    gui.add_option("scarab", "Spawn scarab", function() handle_vehicle_spawn("scarab", "scarab") end)
    gui.add_option("scarab2", "Spawn scarab2", function() handle_vehicle_spawn("scarab2", "scarab2") end)
    gui.add_option("scarab3", "Spawn scarab3", function() handle_vehicle_spawn("scarab3", "scarab3") end)
    gui.set_submenu_context(military_menu)
    local military_cayoperico_menu = gui.add_submenu("Cayo Perico", "Cayo Perico update")
    gui.set_submenu_context(military_cayoperico_menu)
    gui.add_option("vetir", "Spawn vetir", function() handle_vehicle_spawn("vetir", "vetir") end)

    gui.set_submenu_context(spawner_menu)
    local muscle_menu = gui.add_submenu("Muscle", "Muscle vehicles")
    gui.set_submenu_context(muscle_menu)
    local muscle_g9ec_menu = gui.add_submenu("G9ec", "G9ec update")
    gui.set_submenu_context(muscle_g9ec_menu)
    gui.add_option("arbitergt", "Spawn arbitergt", function() handle_vehicle_spawn("arbitergt", "arbitergt") end)
    gui.set_submenu_context(muscle_menu)
    local muscle_hipster_menu = gui.add_submenu("Hipster", "Hipster update")
    gui.set_submenu_context(muscle_hipster_menu)
    gui.add_option("blade", "Spawn blade", function() handle_vehicle_spawn("blade", "blade") end)
    gui.set_submenu_context(muscle_menu)
    local muscle_sanandreasmercenaries_menu = gui.add_submenu("San Andreas Mercenaries", "San Andreas Mercenaries update")
    gui.set_submenu_context(muscle_sanandreasmercenaries_menu)
    gui.add_option("brigham", "Spawn brigham", function() handle_vehicle_spawn("brigham", "brigham") end)
    gui.add_option("buffalo5", "Spawn buffalo5", function() handle_vehicle_spawn("buffalo5", "buffalo5") end)
    gui.add_option("clique2", "Spawn clique2", function() handle_vehicle_spawn("clique2", "clique2") end)
    gui.set_submenu_context(muscle_menu)
    local muscle_christmas3_menu = gui.add_submenu("Christmas3", "Christmas3 update")
    gui.set_submenu_context(muscle_christmas3_menu)
    gui.add_option("broadway", "Spawn broadway", function() handle_vehicle_spawn("broadway", "broadway") end)
    gui.add_option("eudora", "Spawn eudora", function() handle_vehicle_spawn("eudora", "eudora") end)
    gui.add_option("tahoma", "Spawn tahoma", function() handle_vehicle_spawn("tahoma", "tahoma") end)
    gui.add_option("tulip2", "Spawn tulip2", function() handle_vehicle_spawn("tulip2", "tulip2") end)
    gui.set_submenu_context(muscle_menu)
    local muscle_launchmodels_menu = gui.add_submenu("Launch Models", "Launch Models update")
    gui.set_submenu_context(muscle_launchmodels_menu)
    gui.add_option("buccaneer", "Spawn buccaneer", function() handle_vehicle_spawn("buccaneer", "buccaneer") end)
    gui.add_option("Dominator", "Spawn Dominator", function() handle_vehicle_spawn("Dominator", "dominator") end)
    gui.add_option("Gauntlet", "Spawn Gauntlet", function() handle_vehicle_spawn("Gauntlet", "gauntlet") end)
    gui.add_option("hotknife", "Spawn hotknife", function() handle_vehicle_spawn("hotknife", "hotknife") end)
    gui.add_option("Phoenix", "Spawn Phoenix", function() handle_vehicle_spawn("Phoenix", "phoenix") end)
    gui.add_option("picador", "Spawn picador", function() handle_vehicle_spawn("picador", "picador") end)
    gui.add_option("ratloader", "Spawn ratloader", function() handle_vehicle_spawn("ratloader", "ratloader") end)
    gui.add_option("ruiner", "Spawn ruiner", function() handle_vehicle_spawn("ruiner", "ruiner") end)
    gui.add_option("sabregt", "Spawn sabregt", function() handle_vehicle_spawn("sabregt", "sabregt") end)
    gui.add_option("vigero", "Spawn vigero", function() handle_vehicle_spawn("vigero", "vigero") end)
    gui.add_option("voodoo2", "Spawn voodoo2", function() handle_vehicle_spawn("voodoo2", "voodoo2") end)
    gui.set_submenu_context(muscle_menu)
    local muscle_lowriders_menu = gui.add_submenu("Lowriders", "Lowriders update")
    gui.set_submenu_context(muscle_lowriders_menu)
    gui.add_option("buccaneer2", "Spawn buccaneer2", function() handle_vehicle_spawn("buccaneer2", "buccaneer2") end)
    gui.add_option("chino2", "Spawn chino2", function() handle_vehicle_spawn("chino2", "chino2") end)
    gui.add_option("faction", "Spawn faction", function() handle_vehicle_spawn("faction", "faction") end)
    gui.add_option("faction2", "Spawn faction2", function() handle_vehicle_spawn("faction2", "faction2") end)
    gui.add_option("moonbeam", "Spawn moonbeam", function() handle_vehicle_spawn("moonbeam", "moonbeam") end)
    gui.add_option("moonbeam2", "Spawn moonbeam2", function() handle_vehicle_spawn("moonbeam2", "moonbeam2") end)
    gui.add_option("voodoo", "Spawn voodoo", function() handle_vehicle_spawn("voodoo", "voodoo") end)
    gui.set_submenu_context(muscle_menu)
    local muscle_security_menu = gui.add_submenu("Security", "Security update")
    gui.set_submenu_context(muscle_security_menu)
    gui.add_option("buffalo4", "Spawn buffalo4", function() handle_vehicle_spawn("buffalo4", "buffalo4") end)
    gui.set_submenu_context(muscle_menu)
    local muscle_luxe2_menu = gui.add_submenu("Luxe2", "Luxe2 update")
    gui.set_submenu_context(muscle_luxe2_menu)
    gui.add_option("chino", "Spawn chino", function() handle_vehicle_spawn("chino", "chino") end)
    gui.add_option("coquette3", "Spawn coquette3", function() handle_vehicle_spawn("coquette3", "coquette3") end)
    gui.set_submenu_context(muscle_menu)
    local muscle_christmas2018_menu = gui.add_submenu("Christmas2018", "Christmas2018 update")
    gui.set_submenu_context(muscle_christmas2018_menu)
    gui.add_option("clique", "Spawn clique", function() handle_vehicle_spawn("clique", "clique") end)
    gui.add_option("deviant", "Spawn deviant", function() handle_vehicle_spawn("deviant", "deviant") end)
    gui.add_option("dominator4", "Spawn dominator4", function() handle_vehicle_spawn("dominator4", "dominator4") end)
    gui.add_option("dominator5", "Spawn dominator5", function() handle_vehicle_spawn("dominator5", "dominator5") end)
    gui.add_option("dominator6", "Spawn dominator6", function() handle_vehicle_spawn("dominator6", "dominator6") end)
    gui.add_option("impaler", "Spawn impaler", function() handle_vehicle_spawn("impaler", "impaler") end)
    gui.add_option("impaler2", "Spawn impaler2", function() handle_vehicle_spawn("impaler2", "impaler2") end)
    gui.add_option("impaler3", "Spawn impaler3", function() handle_vehicle_spawn("impaler3", "impaler3") end)
    gui.add_option("impaler4", "Spawn impaler4", function() handle_vehicle_spawn("impaler4", "impaler4") end)
    gui.add_option("imperator", "Spawn imperator", function() handle_vehicle_spawn("imperator", "imperator") end)
    gui.add_option("imperator2", "Spawn imperator2", function() handle_vehicle_spawn("imperator2", "imperator2") end)
    gui.add_option("imperator3", "Spawn imperator3", function() handle_vehicle_spawn("imperator3", "imperator3") end)
    gui.add_option("slamvan4", "Spawn slamvan4", function() handle_vehicle_spawn("slamvan4", "slamvan4") end)
    gui.add_option("slamvan5", "Spawn slamvan5", function() handle_vehicle_spawn("slamvan5", "slamvan5") end)
    gui.add_option("slamvan6", "Spawn slamvan6", function() handle_vehicle_spawn("slamvan6", "slamvan6") end)
    gui.add_option("tulip", "Spawn tulip", function() handle_vehicle_spawn("tulip", "tulip") end)
    gui.add_option("vamos", "Spawn vamos", function() handle_vehicle_spawn("vamos", "vamos") end)
    gui.set_submenu_context(muscle_menu)
    local muscle_bottomdollarbounties_menu = gui.add_submenu("Bottom Dollar Bounties", "Bottom Dollar Bounties update")
    gui.set_submenu_context(muscle_bottomdollarbounties_menu)
    gui.add_option("dominator10", "Spawn dominator10", function() handle_vehicle_spawn("dominator10", "dominator10") end)
    gui.set_submenu_context(muscle_menu)
    local muscle_spupgrade_menu = gui.add_submenu("Spupgrade", "Spupgrade update")
    gui.set_submenu_context(muscle_spupgrade_menu)
    gui.add_option("dominator2", "Spawn dominator2", function() handle_vehicle_spawn("dominator2", "dominator2") end)
    gui.add_option("dukes", "Spawn dukes", function() handle_vehicle_spawn("dukes", "dukes") end)
    gui.add_option("dukes2", "Spawn dukes2", function() handle_vehicle_spawn("dukes2", "dukes2") end)
    gui.add_option("gauntlet2", "Spawn gauntlet2", function() handle_vehicle_spawn("gauntlet2", "gauntlet2") end)
    gui.add_option("stalion", "Spawn stalion", function() handle_vehicle_spawn("stalion", "stalion") end)
    gui.add_option("stalion2", "Spawn stalion2", function() handle_vehicle_spawn("stalion2", "stalion2") end)
    gui.set_submenu_context(muscle_menu)
    local muscle_assault_menu = gui.add_submenu("Assault", "Assault update")
    gui.set_submenu_context(muscle_assault_menu)
    gui.add_option("dominator3", "Spawn dominator3", function() handle_vehicle_spawn("dominator3", "dominator3") end)
    gui.add_option("ellie", "Spawn ellie", function() handle_vehicle_spawn("ellie", "ellie") end)
    gui.set_submenu_context(muscle_menu)
    local muscle_tuner_menu = gui.add_submenu("Tuner", "Tuner update")
    gui.set_submenu_context(muscle_tuner_menu)
    gui.add_option("dominator7", "Spawn dominator7", function() handle_vehicle_spawn("dominator7", "dominator7") end)
    gui.add_option("dominator8", "Spawn dominator8", function() handle_vehicle_spawn("dominator8", "dominator8") end)
    gui.set_submenu_context(muscle_menu)
    local muscle_thechopshop_menu = gui.add_submenu("The Chop Shop", "The Chop Shop update")
    gui.set_submenu_context(muscle_thechopshop_menu)
    gui.add_option("dominator9", "Spawn dominator9", function() handle_vehicle_spawn("dominator9", "dominator9") end)
    gui.add_option("driftyosemite", "Spawn driftyosemite",
        function() handle_vehicle_spawn("driftyosemite", "driftyosemite") end)
    gui.add_option("impaler5", "Spawn impaler5", function() handle_vehicle_spawn("impaler5", "impaler5") end)
    gui.add_option("impaler6", "Spawn impaler6", function() handle_vehicle_spawn("impaler6", "impaler6") end)
    gui.add_option("vigero3", "Spawn vigero3", function() handle_vehicle_spawn("vigero3", "vigero3") end)
    gui.set_submenu_context(muscle_menu)
    local muscle_202501_menu = gui.add_submenu("2025 01", "2025 01 update")
    gui.set_submenu_context(muscle_202501_menu)
    gui.add_option("driftdominator10", "Spawn driftdominator10",
        function() handle_vehicle_spawn("driftdominator10", "driftdominator10") end)
    gui.add_option("driftgauntlet4", "Spawn driftgauntlet4",
        function() handle_vehicle_spawn("driftgauntlet4", "driftgauntlet4") end)
    gui.add_option("tampa4", "Spawn tampa4", function() handle_vehicle_spawn("tampa4", "tampa4") end)
    gui.set_submenu_context(muscle_menu)
    local muscle_202502_menu = gui.add_submenu("2025 02", "2025 02 update")
    gui.set_submenu_context(muscle_202502_menu)
    gui.add_option("driftdominator9", "Spawn driftdominator9",
        function() handle_vehicle_spawn("driftdominator9", "driftdominator9") end)
    gui.set_submenu_context(muscle_menu)
    local muscle_sum_menu = gui.add_submenu("Sum", "Sum update")
    gui.set_submenu_context(muscle_sum_menu)
    gui.add_option("dukes3", "Spawn dukes3", function() handle_vehicle_spawn("dukes3", "dukes3") end)
    gui.add_option("gauntlet5", "Spawn gauntlet5", function() handle_vehicle_spawn("gauntlet5", "gauntlet5") end)
    gui.add_option("manana2", "Spawn manana2", function() handle_vehicle_spawn("manana2", "manana2") end)
    gui.set_submenu_context(muscle_menu)
    local muscle_lowrider2_menu = gui.add_submenu("Lowrider2", "Lowrider2 update")
    gui.set_submenu_context(muscle_lowrider2_menu)
    gui.add_option("faction3", "Spawn faction3", function() handle_vehicle_spawn("faction3", "faction3") end)
    gui.add_option("sabregt2", "Spawn sabregt2", function() handle_vehicle_spawn("sabregt2", "sabregt2") end)
    gui.add_option("slamvan3", "Spawn slamvan3", function() handle_vehicle_spawn("slamvan3", "slamvan3") end)
    gui.add_option("virgo2", "Spawn virgo2", function() handle_vehicle_spawn("virgo2", "virgo2") end)
    gui.add_option("virgo3", "Spawn virgo3", function() handle_vehicle_spawn("virgo3", "virgo3") end)
    gui.set_submenu_context(muscle_menu)
    local muscle_vinewood_menu = gui.add_submenu("Vinewood", "Vinewood update")
    gui.set_submenu_context(muscle_vinewood_menu)
    gui.add_option("gauntlet3", "Spawn gauntlet3", function() handle_vehicle_spawn("gauntlet3", "gauntlet3") end)
    gui.add_option("gauntlet4", "Spawn gauntlet4", function() handle_vehicle_spawn("gauntlet4", "gauntlet4") end)
    gui.add_option("peyote2", "Spawn peyote2", function() handle_vehicle_spawn("peyote2", "peyote2") end)
    gui.set_submenu_context(muscle_menu)
    local muscle_sum2_menu = gui.add_submenu("Sum2", "Sum2 update")
    gui.set_submenu_context(muscle_sum2_menu)
    gui.add_option("greenwood", "Spawn greenwood", function() handle_vehicle_spawn("greenwood", "greenwood") end)
    gui.add_option("ruiner4", "Spawn ruiner4", function() handle_vehicle_spawn("ruiner4", "ruiner4") end)
    gui.add_option("vigero2", "Spawn vigero2", function() handle_vehicle_spawn("vigero2", "vigero2") end)
    gui.add_option("weevil2", "Spawn weevil2", function() handle_vehicle_spawn("weevil2", "weevil2") end)
    gui.set_submenu_context(muscle_menu)
    local muscle_doomsdayheist_menu = gui.add_submenu("Doomsday Heist", "Doomsday Heist update")
    gui.set_submenu_context(muscle_doomsdayheist_menu)
    gui.add_option("hermes", "Spawn hermes", function() handle_vehicle_spawn("hermes", "hermes") end)
    gui.add_option("hustler", "Spawn hustler", function() handle_vehicle_spawn("hustler", "hustler") end)
    gui.add_option("yosemite", "Spawn yosemite", function() handle_vehicle_spawn("yosemite", "yosemite") end)
    gui.set_submenu_context(muscle_menu)
    local muscle_halloween_menu = gui.add_submenu("Halloween", "Halloween update")
    gui.set_submenu_context(muscle_halloween_menu)
    gui.add_option("lurcher", "Spawn lurcher", function() handle_vehicle_spawn("lurcher", "lurcher") end)
    gui.set_submenu_context(muscle_menu)
    local muscle_apartment_menu = gui.add_submenu("Apartment", "Apartment update")
    gui.set_submenu_context(muscle_apartment_menu)
    gui.add_option("nightshade", "Spawn nightshade", function() handle_vehicle_spawn("nightshade", "nightshade") end)
    gui.set_submenu_context(muscle_menu)
    local muscle_christmas2_menu = gui.add_submenu("Christmas2", "Christmas2 update")
    gui.set_submenu_context(muscle_christmas2_menu)
    gui.add_option("ratloader2", "Spawn ratloader2", function() handle_vehicle_spawn("ratloader2", "ratloader2") end)
    gui.add_option("slamvan", "Spawn slamvan", function() handle_vehicle_spawn("slamvan", "slamvan") end)
    gui.set_submenu_context(muscle_menu)
    local muscle_importexport_menu = gui.add_submenu("Import/Export", "Import/Export update")
    gui.set_submenu_context(muscle_importexport_menu)
    gui.add_option("ruiner2", "Spawn ruiner2", function() handle_vehicle_spawn("ruiner2", "ruiner2") end)
    gui.add_option("ruiner3", "Spawn ruiner3", function() handle_vehicle_spawn("ruiner3", "ruiner3") end)
    gui.set_submenu_context(muscle_menu)
    local muscle_heist_menu = gui.add_submenu("Heist", "Heist update")
    gui.set_submenu_context(muscle_heist_menu)
    gui.add_option("slamvan2", "Spawn slamvan2", function() handle_vehicle_spawn("slamvan2", "slamvan2") end)
    gui.set_submenu_context(muscle_menu)
    local muscle_xmas604490_menu = gui.add_submenu("Xmas 604490", "Xmas 604490 update")
    gui.set_submenu_context(muscle_xmas604490_menu)
    gui.add_option("tampa", "Spawn tampa", function() handle_vehicle_spawn("tampa", "tampa") end)
    gui.set_submenu_context(muscle_menu)
    local muscle_gunrunning_menu = gui.add_submenu("Gunrunning", "Gunrunning update")
    gui.set_submenu_context(muscle_gunrunning_menu)
    gui.add_option("tampa3", "Spawn tampa3", function() handle_vehicle_spawn("tampa3", "tampa3") end)
    gui.set_submenu_context(muscle_menu)
    local muscle_luxe_menu = gui.add_submenu("Luxe", "Luxe update")
    gui.set_submenu_context(muscle_luxe_menu)
    gui.add_option("virgo", "Spawn virgo", function() handle_vehicle_spawn("virgo", "virgo") end)
    gui.set_submenu_context(muscle_menu)
    local muscle_casinoheist_menu = gui.add_submenu("Casino Heist", "Casino Heist update")
    gui.set_submenu_context(muscle_casinoheist_menu)
    gui.add_option("yosemite2", "Spawn yosemite2", function() handle_vehicle_spawn("yosemite2", "yosemite2") end)

    gui.set_submenu_context(spawner_menu)
    local commercial_menu = gui.add_submenu("Commercial", "Commercial vehicles")
    gui.set_submenu_context(commercial_menu)
    local commercial_launchmodels_menu = gui.add_submenu("Launch Models", "Launch Models update")
    gui.set_submenu_context(commercial_launchmodels_menu)
    gui.add_option("Benson", "Spawn Benson", function() handle_vehicle_spawn("Benson", "benson") end)
    gui.add_option("Biff", "Spawn Biff", function() handle_vehicle_spawn("Biff", "biff") end)
    gui.add_option("Hauler", "Spawn Hauler", function() handle_vehicle_spawn("Hauler", "hauler") end)
    gui.add_option("Mule", "Spawn Mule", function() handle_vehicle_spawn("Mule", "mule") end)
    gui.add_option("Mule2", "Spawn Mule2", function() handle_vehicle_spawn("Mule2", "mule2") end)
    gui.add_option("Packer", "Spawn Packer", function() handle_vehicle_spawn("Packer", "packer") end)
    gui.add_option("Phantom", "Spawn Phantom", function() handle_vehicle_spawn("Phantom", "phantom") end)
    gui.add_option("Pounder", "Spawn Pounder", function() handle_vehicle_spawn("Pounder", "pounder") end)
    gui.add_option("stockade", "Spawn stockade", function() handle_vehicle_spawn("stockade", "stockade") end)
    gui.add_option("stockade3", "Spawn stockade3", function() handle_vehicle_spawn("stockade3", "stockade3") end)
    gui.set_submenu_context(commercial_menu)
    local commercial_thechopshop_menu = gui.add_submenu("The Chop Shop", "The Chop Shop update")
    gui.set_submenu_context(commercial_thechopshop_menu)
    gui.add_option("benson2", "Spawn benson2", function() handle_vehicle_spawn("benson2", "benson2") end)
    gui.add_option("Phantom4", "Spawn Phantom4", function() handle_vehicle_spawn("Phantom4", "phantom4") end)
    gui.set_submenu_context(commercial_menu)
    local commercial_christmas2018_menu = gui.add_submenu("Christmas2018", "Christmas2018 update")
    gui.set_submenu_context(commercial_christmas2018_menu)
    gui.add_option("cerberus", "Spawn cerberus", function() handle_vehicle_spawn("cerberus", "cerberus") end)
    gui.add_option("cerberus2", "Spawn cerberus2", function() handle_vehicle_spawn("cerberus2", "cerberus2") end)
    gui.add_option("cerberus3", "Spawn cerberus3", function() handle_vehicle_spawn("cerberus3", "cerberus3") end)
    gui.set_submenu_context(commercial_menu)
    local commercial_gunrunning_menu = gui.add_submenu("Gunrunning", "Gunrunning update")
    gui.set_submenu_context(commercial_gunrunning_menu)
    gui.add_option("Hauler2", "Spawn Hauler2", function() handle_vehicle_spawn("Hauler2", "hauler2") end)
    gui.add_option("phantom3", "Spawn phantom3", function() handle_vehicle_spawn("phantom3", "phantom3") end)
    gui.set_submenu_context(commercial_menu)
    local commercial_heist_menu = gui.add_submenu("Heist", "Heist update")
    gui.set_submenu_context(commercial_heist_menu)
    gui.add_option("Mule3", "Spawn Mule3", function() handle_vehicle_spawn("Mule3", "mule3") end)
    gui.set_submenu_context(commercial_menu)
    local commercial_battle_menu = gui.add_submenu("Battle", "Battle update")
    gui.set_submenu_context(commercial_battle_menu)
    gui.add_option("mule4", "Spawn mule4", function() handle_vehicle_spawn("mule4", "mule4") end)
    gui.add_option("pounder2", "Spawn pounder2", function() handle_vehicle_spawn("pounder2", "pounder2") end)
    gui.add_option("terbyte", "Spawn terbyte", function() handle_vehicle_spawn("terbyte", "terbyte") end)
    gui.set_submenu_context(commercial_menu)
    local commercial_security_menu = gui.add_submenu("Security", "Security update")
    gui.set_submenu_context(commercial_security_menu)
    gui.add_option("mule5", "Spawn mule5", function() handle_vehicle_spawn("mule5", "mule5") end)
    gui.set_submenu_context(commercial_menu)
    local commercial_importexport_menu = gui.add_submenu("Import/Export", "Import/Export update")
    gui.set_submenu_context(commercial_importexport_menu)
    gui.add_option("phantom2", "Spawn phantom2", function() handle_vehicle_spawn("phantom2", "phantom2") end)
    gui.set_submenu_context(commercial_menu)
    local commercial_202501_menu = gui.add_submenu("2025 01", "2025 01 update")
    gui.set_submenu_context(commercial_202501_menu)
    gui.add_option("stockade4", "Spawn stockade4", function() handle_vehicle_spawn("stockade4", "stockade4") end)

    gui.set_submenu_context(spawner_menu)
    local industrial_menu = gui.add_submenu("Industrial", "Industrial vehicles")
    gui.set_submenu_context(industrial_menu)
    local industrial_launchmodels_menu = gui.add_submenu("Launch Models", "Launch Models update")
    gui.set_submenu_context(industrial_launchmodels_menu)
    gui.add_option("bulldozer", "Spawn bulldozer", function() handle_vehicle_spawn("bulldozer", "bulldozer") end)
    gui.add_option("cutter", "Spawn cutter", function() handle_vehicle_spawn("cutter", "cutter") end)
    gui.add_option("dump", "Spawn dump", function() handle_vehicle_spawn("dump", "dump") end)
    gui.add_option("FLATBED", "Spawn FLATBED", function() handle_vehicle_spawn("FLATBED", "flatbed") end)
    gui.add_option("handler", "Spawn handler", function() handle_vehicle_spawn("handler", "handler") end)
    gui.add_option("Mixer", "Spawn Mixer", function() handle_vehicle_spawn("Mixer", "mixer") end)
    gui.add_option("Mixer2", "Spawn Mixer2", function() handle_vehicle_spawn("Mixer2", "mixer2") end)
    gui.add_option("Rubble", "Spawn Rubble", function() handle_vehicle_spawn("Rubble", "rubble") end)
    gui.add_option("TipTruck", "Spawn TipTruck", function() handle_vehicle_spawn("TipTruck", "tiptruck") end)
    gui.add_option("TipTruck2", "Spawn TipTruck2", function() handle_vehicle_spawn("TipTruck2", "tiptruck2") end)
    gui.set_submenu_context(industrial_menu)
    local industrial_202501_menu = gui.add_submenu("2025 01", "2025 01 update")
    gui.set_submenu_context(industrial_202501_menu)
    gui.add_option("flatbed2", "Spawn flatbed2", function() handle_vehicle_spawn("flatbed2", "flatbed2") end)
    gui.set_submenu_context(industrial_menu)
    local industrial_heist_menu = gui.add_submenu("Heist", "Heist update")
    gui.set_submenu_context(industrial_heist_menu)
    gui.add_option("guardian", "Spawn guardian", function() handle_vehicle_spawn("guardian", "guardian") end)


    gui.reset_submenu_context()

    -- Submenu: Weapons
    local wep_menu = gui.add_submenu("Weapon Options", "Modify guns and ammo")
    gui.set_submenu_context(wep_menu)
    local ammunation_menu = gui.add_submenu("Ammunation", "Mobile weapon workshop")
    gui.set_submenu_context(ammunation_menu)

    local function apply_comp(suffix, use_generic, generic_hash_string)
        local ped = self.get_ped()
        local hash = WEAPON.GET_SELECTED_PED_WEAPON(ped)
        if hash ~= joaat("WEAPON_UNARMED") then
            if use_generic and generic_hash_string then
                WEAPON.GIVE_WEAPON_COMPONENT_TO_PED(ped, hash, joaat(generic_hash_string))
                notify.success("Component applied.")
            else
                local weapons_list = {
                    "WEAPON_BAT", "WEAPON_KNIFE", "WEAPON_HAMMER", "WEAPON_CROWBAR", "WEAPON_GOLFCLUB", "WEAPON_BOTTLE", "WEAPON_DAGGER", "WEAPON_HATCHET", "WEAPON_KNUCKLE", "WEAPON_MACHETE", "WEAPON_FLASHLIGHT", "WEAPON_SWITCHBLADE", "WEAPON_POOLCUE", "WEAPON_WRENCH", "WEAPON_BATTLEAXE", "WEAPON_STONE_HATCHET",
                    "WEAPON_PISTOL", "WEAPON_PISTOL_MK2", "WEAPON_COMBATPISTOL", "WEAPON_APPISTOL", "WEAPON_STUNGUN", "WEAPON_PISTOL50", "WEAPON_SNSPISTOL", "WEAPON_SNSPISTOL_MK2", "WEAPON_HEAVYPISTOL", "WEAPON_VINTAGEPISTOL", "WEAPON_FLAREGUN", "WEAPON_MARKSMANPISTOL", "WEAPON_REVOLVER", "WEAPON_REVOLVER_MK2", "WEAPON_DOUBLEACTION", "WEAPON_RAYPISTOL", "WEAPON_CERAMICPISTOL", "WEAPON_NAVYREVOLVER", "WEAPON_GADGETPISTOL",
                    "WEAPON_MICROSMG", "WEAPON_SMG", "WEAPON_SMG_MK2", "WEAPON_ASSAULTSMG", "WEAPON_COMBATPDW", "WEAPON_MACHINEPISTOL", "WEAPON_MINISMG", "WEAPON_RAYCARBINE",
                    "WEAPON_PUMPSHOTGUN", "WEAPON_PUMPSHOTGUN_MK2", "WEAPON_SAWNOFFSHOTGUN", "WEAPON_ASSAULTSHOTGUN", "WEAPON_BULLPUPSHOTGUN", "WEAPON_MUSKET", "WEAPON_HEAVYSHOTGUN", "WEAPON_DBSHOTGUN", "WEAPON_AUTOSHOTGUN", "WEAPON_COMBATSHOTGUN",
                    "WEAPON_ASSAULTRIFLE", "WEAPON_ASSAULTRIFLE_MK2", "WEAPON_CARBINERIFLE", "WEAPON_CARBINERIFLE_MK2", "WEAPON_ADVANCEDRIFLE", "WEAPON_SPECIALCARBINE", "WEAPON_SPECIALCARBINE_MK2", "WEAPON_BULLPUPRIFLE", "WEAPON_BULLPUPRIFLE_MK2", "WEAPON_COMPACTRIFLE", "WEAPON_MILITARYRIFLE", "WEAPON_HEAVYRIFLE", "WEAPON_TACTICALRIFLE",
                    "WEAPON_MG", "WEAPON_COMBATMG", "WEAPON_COMBATMG_MK2", "WEAPON_GUSENBERG",
                    "WEAPON_SNIPERRIFLE", "WEAPON_HEAVYSNIPER", "WEAPON_HEAVYSNIPER_MK2", "WEAPON_MARKSMANRIFLE", "WEAPON_MARKSMANRIFLE_MK2", "WEAPON_PRECISIONRIFLE",
                    "WEAPON_RPG", "WEAPON_GRENADELAUNCHER", "WEAPON_MINIGUN", "WEAPON_FIREWORK", "WEAPON_RAILGUN", "WEAPON_HOMINGLAUNCHER", "WEAPON_COMPACTLAUNCHER", "WEAPON_RAYMINIGUN", "WEAPON_EMPLAUNCHER",
                    "WEAPON_GRENADE", "WEAPON_BZGAS", "WEAPON_MOLOTOV", "WEAPON_STICKYBOMB", "WEAPON_PROXMINE", "WEAPON_SNOWBALL", "WEAPON_PIPEBOMB", "WEAPON_FLARE",
                    "WEAPON_PARACHUTE", "WEAPON_FIREEXTINGUISHER", "WEAPON_PETROLCAN", "WEAPON_HAZARDCAN"
                }
                for _, w in ipairs(weapons_list) do
                    if joaat(w) == hash then
                        local w_base = string.gsub(w, "WEAPON_", "COMPONENT_")
                        local comp_hash = joaat(w_base .. suffix)
                        WEAPON.GIVE_WEAPON_COMPONENT_TO_PED(ped, hash, comp_hash)
                        notify.success("Component applied.")
                        break
                    end
                end
            end
        else
            notify.error("No weapon held.")
        end
    end

    local ammo_menu = gui.add_submenu("Magazines & Ammo", "Clips and special rounds")
    gui.set_submenu_context(ammo_menu)
    gui.add_option("Default Clip", "Standard magazine", function() apply_comp("_CLIP_01", false) end)
    gui.add_option("Extended Clip", "Extended magazine", function() apply_comp("_CLIP_02", false) end)
    gui.add_option("Drum / Box Magazine", "Highest capacity magazine", function() apply_comp("_CLIP_03", false) end)
    gui.add_break("Special Ammo (Mk II)")
    gui.add_option("Tracer Rounds", "Colored bullet trails", function() apply_comp("_CLIP_TRACER", false) end)
    gui.add_option("Incendiary Rounds", "Sets targets on fire", function() apply_comp("_CLIP_INCENDIARY", false) end)
    gui.add_option("Hollow Point Rounds", "Extra damage to unarmored", function() apply_comp("_CLIP_HOLLOWPOINT", false) end)
    gui.add_option("Armor Piercing Rounds", "Penetrates armor", function() apply_comp("_CLIP_ARMORPIERCING", false) end)
    gui.add_option("Explosive Rounds", "Explodes on impact", function() apply_comp("_CLIP_EXPLOSIVE", false) end)
    gui.set_submenu_context(ammunation_menu)

    local attach_menu = gui.add_submenu("Attachments", "Suppressors, lights, grips")
    gui.set_submenu_context(attach_menu)
    gui.add_option("Suppressor (Pistols)", "Silences weapon", function() apply_comp("", true, "COMPONENT_AT_PI_SUPP") end)
    gui.add_option("Suppressor (Rifles)", "Silences weapon", function() apply_comp("", true, "COMPONENT_AT_AR_SUPP") end)
    gui.add_option("Suppressor (Snipers)", "Silences weapon", function() apply_comp("", true, "COMPONENT_AT_SR_SUPP") end)
    gui.add_option("Flashlight (Pistols)", "Tactical light", function() apply_comp("", true, "COMPONENT_AT_PI_FLSH") end)
    gui.add_option("Flashlight (Rifles)", "Tactical light", function() apply_comp("", true, "COMPONENT_AT_AR_FLSH") end)
    gui.add_option("Grip", "Forward grip for recoil", function() apply_comp("", true, "COMPONENT_AT_AR_AFGRIP") end)
    gui.set_submenu_context(ammunation_menu)

    local sights_menu = gui.add_submenu("Sights & Scopes", "Optics")
    gui.set_submenu_context(sights_menu)
    gui.add_option("Macro Scope", "Small optic", function() apply_comp("", true, "COMPONENT_AT_SCOPE_MACRO") end)
    gui.add_option("Small Scope", "Small optic", function() apply_comp("", true, "COMPONENT_AT_SCOPE_SMALL") end)
    gui.add_option("Medium Scope", "Medium optic", function() apply_comp("", true, "COMPONENT_AT_SCOPE_MEDIUM") end)
    gui.add_option("Large Scope", "Large optic", function() apply_comp("", true, "COMPONENT_AT_SCOPE_LARGE") end)
    gui.add_option("Max Scope", "Max zoom optic", function() apply_comp("", true, "COMPONENT_AT_SCOPE_MAX") end)
    gui.add_option("Night Vision Scope", "Advanced NV optic", function() apply_comp("", true, "COMPONENT_AT_SCOPE_NV") end)
    gui.add_option("Thermal Scope", "Advanced thermal optic", function() apply_comp("", true, "COMPONENT_AT_SCOPE_THERMAL") end)
    gui.set_submenu_context(ammunation_menu)

    local barrel_menu = gui.add_submenu("Barrels & Muzzles", "Muzzle brakes and heavy barrels")
    gui.set_submenu_context(barrel_menu)
    gui.add_option("Muzzle Brake 1", "Slotted", function() apply_comp("", true, "COMPONENT_AT_MUZZLE_01") end)
    gui.add_option("Muzzle Brake 2", "Squared", function() apply_comp("", true, "COMPONENT_AT_MUZZLE_02") end)
    gui.add_option("Muzzle Brake 3", "Bell", function() apply_comp("", true, "COMPONENT_AT_MUZZLE_03") end)
    gui.add_option("Muzzle Brake 4", "Heavy", function() apply_comp("", true, "COMPONENT_AT_MUZZLE_04") end)
    gui.add_option("Heavy Barrel (Mk II)", "Increases range", function() apply_comp("_BARREL_HEAVY", false) end)
    gui.set_submenu_context(ammunation_menu)

    if state.weapon_tint == nil then
        state.weapon_tint = { value = 0 }
    end
    local tint_menu = gui.add_submenu("Tints & Finishes", "Weapon colors")
    gui.set_submenu_context(tint_menu)
    gui.add_number_option("Weapon Tint", "Standard colors (0-7)", state.weapon_tint, 0, 7, 1)
    gui.add_option("Apply Tint", "Applies the selected tint to current weapon", function()
        local ped = self.get_ped()
        local hash = WEAPON.GET_SELECTED_PED_WEAPON(ped)
        if hash ~= joaat("WEAPON_UNARMED") then
            WEAPON.SET_PED_WEAPON_TINT_INDEX(ped, hash, state.weapon_tint.value)
            notify.success("Tint applied.")
        else
            notify.error("No weapon held.")
        end
    end)
    gui.add_break("Mk II Finishes")
    gui.add_option("Luxe Finish", "Gold / Platinum", function() apply_comp("_VARMOD_LUXE", false) end)
    gui.set_submenu_context(ammunation_menu)

    gui.set_submenu_context(wep_menu)
    gui.add_bool_option("Infinite Ammo", "Never reload again", state.infinite_ammo)
    gui.add_bool_option("Explosive Ammo", "All bullets detonate on impact", state.explosive_ammo)
    gui.add_bool_option("Flaming Ammo", "Ignite targets", state.flaming_ammo)
    gui.add_bool_option("Explosive Melee", "Explosive punches", state.explosive_melee)
    gui.add_bool_option("One-Hit Kill", "Kill with any weapon instantly", state.one_hit_kill)
    gui.add_option("Give All Weapons", "Grant standard weapon loadout", function()
        local ped = self.get_ped()
        local weapons = {
            "WEAPON_BAT", "WEAPON_KNIFE", "WEAPON_HAMMER", "WEAPON_CROWBAR", "WEAPON_GOLFCLUB", "WEAPON_BOTTLE", "WEAPON_DAGGER", "WEAPON_HATCHET", "WEAPON_KNUCKLE", "WEAPON_MACHETE", "WEAPON_FLASHLIGHT", "WEAPON_SWITCHBLADE", "WEAPON_POOLCUE", "WEAPON_WRENCH", "WEAPON_BATTLEAXE", "WEAPON_STONE_HATCHET",
            "WEAPON_PISTOL", "WEAPON_PISTOL_MK2", "WEAPON_COMBATPISTOL", "WEAPON_APPISTOL", "WEAPON_STUNGUN", "WEAPON_PISTOL50", "WEAPON_SNSPISTOL", "WEAPON_SNSPISTOL_MK2", "WEAPON_HEAVYPISTOL", "WEAPON_VINTAGEPISTOL", "WEAPON_FLAREGUN", "WEAPON_MARKSMANPISTOL", "WEAPON_REVOLVER", "WEAPON_REVOLVER_MK2", "WEAPON_DOUBLEACTION", "WEAPON_RAYPISTOL", "WEAPON_CERAMICPISTOL", "WEAPON_NAVYREVOLVER", "WEAPON_GADGETPISTOL",
            "WEAPON_MICROSMG", "WEAPON_SMG", "WEAPON_SMG_MK2", "WEAPON_ASSAULTSMG", "WEAPON_COMBATPDW", "WEAPON_MACHINEPISTOL", "WEAPON_MINISMG", "WEAPON_RAYCARBINE",
            "WEAPON_PUMPSHOTGUN", "WEAPON_PUMPSHOTGUN_MK2", "WEAPON_SAWNOFFSHOTGUN", "WEAPON_ASSAULTSHOTGUN", "WEAPON_BULLPUPSHOTGUN", "WEAPON_MUSKET", "WEAPON_HEAVYSHOTGUN", "WEAPON_DBSHOTGUN", "WEAPON_AUTOSHOTGUN", "WEAPON_COMBATSHOTGUN",
            "WEAPON_ASSAULTRIFLE", "WEAPON_ASSAULTRIFLE_MK2", "WEAPON_CARBINERIFLE", "WEAPON_CARBINERIFLE_MK2", "WEAPON_ADVANCEDRIFLE", "WEAPON_SPECIALCARBINE", "WEAPON_SPECIALCARBINE_MK2", "WEAPON_BULLPUPRIFLE", "WEAPON_BULLPUPRIFLE_MK2", "WEAPON_COMPACTRIFLE", "WEAPON_MILITARYRIFLE", "WEAPON_HEAVYRIFLE", "WEAPON_TACTICALRIFLE",
            "WEAPON_MG", "WEAPON_COMBATMG", "WEAPON_COMBATMG_MK2", "WEAPON_GUSENBERG",
            "WEAPON_SNIPERRIFLE", "WEAPON_HEAVYSNIPER", "WEAPON_HEAVYSNIPER_MK2", "WEAPON_MARKSMANRIFLE", "WEAPON_MARKSMANRIFLE_MK2", "WEAPON_PRECISIONRIFLE",
            "WEAPON_RPG", "WEAPON_GRENADELAUNCHER", "WEAPON_MINIGUN", "WEAPON_FIREWORK", "WEAPON_RAILGUN", "WEAPON_HOMINGLAUNCHER", "WEAPON_COMPACTLAUNCHER", "WEAPON_RAYMINIGUN", "WEAPON_EMPLAUNCHER",
            "WEAPON_GRENADE", "WEAPON_BZGAS", "WEAPON_MOLOTOV", "WEAPON_STICKYBOMB", "WEAPON_PROXMINE", "WEAPON_SNOWBALL", "WEAPON_PIPEBOMB", "WEAPON_FLARE",
            "WEAPON_PARACHUTE", "WEAPON_FIREEXTINGUISHER", "WEAPON_PETROLCAN", "WEAPON_HAZARDCAN"
        }
        for _, w in ipairs(weapons) do
            WEAPON.GIVE_DELAYED_WEAPON_TO_PED(ped, joaat(w), 9999, false)
        end
        notify.success("Loadout granted.")
    end)
    gui.add_option("Max All Weapons", "Fully upgrades all your weapons", function()
        local ped = self.get_ped()
        local weapons = {
            "WEAPON_BAT", "WEAPON_KNIFE", "WEAPON_HAMMER", "WEAPON_CROWBAR", "WEAPON_GOLFCLUB", "WEAPON_BOTTLE", "WEAPON_DAGGER", "WEAPON_HATCHET", "WEAPON_KNUCKLE", "WEAPON_MACHETE", "WEAPON_FLASHLIGHT", "WEAPON_SWITCHBLADE", "WEAPON_POOLCUE", "WEAPON_WRENCH", "WEAPON_BATTLEAXE", "WEAPON_STONE_HATCHET",
            "WEAPON_PISTOL", "WEAPON_PISTOL_MK2", "WEAPON_COMBATPISTOL", "WEAPON_APPISTOL", "WEAPON_STUNGUN", "WEAPON_PISTOL50", "WEAPON_SNSPISTOL", "WEAPON_SNSPISTOL_MK2", "WEAPON_HEAVYPISTOL", "WEAPON_VINTAGEPISTOL", "WEAPON_FLAREGUN", "WEAPON_MARKSMANPISTOL", "WEAPON_REVOLVER", "WEAPON_REVOLVER_MK2", "WEAPON_DOUBLEACTION", "WEAPON_RAYPISTOL", "WEAPON_CERAMICPISTOL", "WEAPON_NAVYREVOLVER", "WEAPON_GADGETPISTOL",
            "WEAPON_MICROSMG", "WEAPON_SMG", "WEAPON_SMG_MK2", "WEAPON_ASSAULTSMG", "WEAPON_COMBATPDW", "WEAPON_MACHINEPISTOL", "WEAPON_MINISMG", "WEAPON_RAYCARBINE",
            "WEAPON_PUMPSHOTGUN", "WEAPON_PUMPSHOTGUN_MK2", "WEAPON_SAWNOFFSHOTGUN", "WEAPON_ASSAULTSHOTGUN", "WEAPON_BULLPUPSHOTGUN", "WEAPON_MUSKET", "WEAPON_HEAVYSHOTGUN", "WEAPON_DBSHOTGUN", "WEAPON_AUTOSHOTGUN", "WEAPON_COMBATSHOTGUN",
            "WEAPON_ASSAULTRIFLE", "WEAPON_ASSAULTRIFLE_MK2", "WEAPON_CARBINERIFLE", "WEAPON_CARBINERIFLE_MK2", "WEAPON_ADVANCEDRIFLE", "WEAPON_SPECIALCARBINE", "WEAPON_SPECIALCARBINE_MK2", "WEAPON_BULLPUPRIFLE", "WEAPON_BULLPUPRIFLE_MK2", "WEAPON_COMPACTRIFLE", "WEAPON_MILITARYRIFLE", "WEAPON_HEAVYRIFLE", "WEAPON_TACTICALRIFLE",
            "WEAPON_MG", "WEAPON_COMBATMG", "WEAPON_COMBATMG_MK2", "WEAPON_GUSENBERG",
            "WEAPON_SNIPERRIFLE", "WEAPON_HEAVYSNIPER", "WEAPON_HEAVYSNIPER_MK2", "WEAPON_MARKSMANRIFLE", "WEAPON_MARKSMANRIFLE_MK2", "WEAPON_PRECISIONRIFLE",
            "WEAPON_RPG", "WEAPON_GRENADELAUNCHER", "WEAPON_MINIGUN", "WEAPON_FIREWORK", "WEAPON_RAILGUN", "WEAPON_HOMINGLAUNCHER", "WEAPON_COMPACTLAUNCHER", "WEAPON_RAYMINIGUN", "WEAPON_EMPLAUNCHER",
            "WEAPON_GRENADE", "WEAPON_BZGAS", "WEAPON_MOLOTOV", "WEAPON_STICKYBOMB", "WEAPON_PROXMINE", "WEAPON_SNOWBALL", "WEAPON_PIPEBOMB", "WEAPON_FLARE",
            "WEAPON_PARACHUTE", "WEAPON_FIREEXTINGUISHER", "WEAPON_PETROLCAN", "WEAPON_HAZARDCAN"
        }
        local generic_components = {
            "COMPONENT_AT_AR_FLSH", "COMPONENT_AT_PI_FLSH",
            "COMPONENT_AT_AR_SUPP", "COMPONENT_AT_AR_SUPP_02", "COMPONENT_AT_PI_SUPP", "COMPONENT_AT_PI_SUPP_02", "COMPONENT_AT_SR_SUPP", "COMPONENT_AT_SR_SUPP_03",
            "COMPONENT_AT_SCOPE_MACRO", "COMPONENT_AT_SCOPE_MACRO_02", "COMPONENT_AT_SCOPE_SMALL", "COMPONENT_AT_SCOPE_SMALL_02",
            "COMPONENT_AT_SCOPE_MEDIUM", "COMPONENT_AT_SCOPE_LARGE", "COMPONENT_AT_SCOPE_MAX", "COMPONENT_AT_SCOPE_NV", "COMPONENT_AT_SCOPE_THERMAL",
            "COMPONENT_AT_PI_COMP", "COMPONENT_AT_PI_COMP_02", "COMPONENT_AT_PI_COMP_03",
            "COMPONENT_AT_MUZZLE_01", "COMPONENT_AT_MUZZLE_02", "COMPONENT_AT_MUZZLE_03", "COMPONENT_AT_MUZZLE_04", "COMPONENT_AT_MUZZLE_05", "COMPONENT_AT_MUZZLE_06", "COMPONENT_AT_MUZZLE_07", "COMPONENT_AT_MUZZLE_08", "COMPONENT_AT_MUZZLE_09",
            "COMPONENT_AT_AR_AFGRIP", "COMPONENT_AT_AR_AFGRIP_02",
            "COMPONENT_GUNRUN_MK2_UPGRADE"
        }
        for _, w in ipairs(weapons) do
            local hash = joaat(w)
            if WEAPON.HAS_PED_GOT_WEAPON(ped, hash, false) then
                local w_base = string.gsub(w, "WEAPON_", "COMPONENT_")
                WEAPON.GIVE_WEAPON_COMPONENT_TO_PED(ped, hash, joaat(w_base .. "_CLIP_02"))
                WEAPON.GIVE_WEAPON_COMPONENT_TO_PED(ped, hash, joaat(w_base .. "_CLIP_03"))
                WEAPON.GIVE_WEAPON_COMPONENT_TO_PED(ped, hash, joaat(w_base .. "_VARMOD_LUXE"))
                for _, comp in ipairs(generic_components) do
                    WEAPON.GIVE_WEAPON_COMPONENT_TO_PED(ped, hash, joaat(comp))
                end
                WEAPON.SET_PED_WEAPON_TINT_INDEX(ped, hash, 7)
            end
        end
        notify.success("All weapons upgraded to maximum.")
    end)
    gui.add_option("Drop Current Weapon", "Drop equipped weapon", function()
        WEAPON.SET_PED_DROPS_WEAPON(self.get_ped())
    end)
   
    gui.add_break("Quick Actions")
    gui.add_option("Give Up-n-Atomizer", "Spawns the raygun", function()
        WEAPON.GIVE_DELAYED_WEAPON_TO_PED(self.get_ped(), joaat("WEAPON_RAYPISTOL"), 9999, true)
        notify.success("Weapon granted.")
    end)
    gui.add_option("Remove All Weapons", "Strips your weapon wheel", function()
        WEAPON.REMOVE_ALL_PED_WEAPONS(self.get_ped(), true)
        notify.info("Weapons removed.")
    end)
    gui.reset_submenu_context()

    -- Submenu: World & Network
    local world_menu = gui.add_submenu("World & Network", "Modify game environment and session")
    gui.set_submenu_context(world_menu)
    gui.add_bool_option("On-Screen HUD", "Draws health and coordinates", state.info_hud)
    gui.add_bool_option("Player ESP Text", "Draws distances to other players", state.player_esp)
    gui.add_break("Environment")
    gui.add_bool_option("Time Control", "Override session time", state.time_control)
    gui.add_number_option("Time Hour", "Set the hour", state.time_hour, 0, 23, 1)
    gui.add_bool_option("Blackout / EMP", "Turn off all lights in the city", state.blackout)
    gui.add_bool_option("Low Gravity", "Floaty physics", state.low_gravity)
    local weather_menu = gui.add_submenu("Change Weather", "Force local weather")
    gui.set_submenu_context(weather_menu)
    gui.add_option("Extra Sunny", "Set weather", function() MISC.SET_WEATHER_TYPE_NOW_PERSIST("EXTRASUNNY") end)
    gui.add_option("Rain", "Set weather", function() MISC.SET_WEATHER_TYPE_NOW_PERSIST("RAIN") end)
    gui.add_option("Thunder", "Set weather", function() MISC.SET_WEATHER_TYPE_NOW_PERSIST("THUNDER") end)
    gui.add_option("Snow", "Set weather", function() MISC.SET_WEATHER_TYPE_NOW_PERSIST("SNOW") end)
    gui.set_submenu_context(world_menu)

    gui.add_option("Clear Area", "Delete nearby entities", function()
        script.run_in_fiber(function()
            local count = 0
            local my_ped = self.get_ped()
            local my_veh = self.get_veh()
            for _, v in ipairs(entities.get_all_vehicles()) do
                if v ~= my_veh and entities.request_control(v) then
                    entities.delete(v); count = count + 1
                end
            end
            for _, p in ipairs(entities.get_all_peds()) do
                if p ~= my_ped and entities.request_control(p) then
                    entities.delete(p); count = count + 1
                end
            end
            for _, o in ipairs(entities.get_all_objects()) do
                if entities.request_control(o) then
                    entities.delete(o); count = count + 1
                end
            end
            notify.success(string.format("Cleared %d entities.", count))
        end)
    end)
    gui.add_break("World Actions")
    gui.add_option("Delete Nearby Vehicles", "Wipes all empty vehicles from the area", function()
        script.run_in_fiber(function()
            local count = 0
            local my_veh = self.get_veh()
            for _, v in ipairs(entities.get_all_vehicles()) do
                if v ~= my_veh then
                    if entities.request_control(v) then
                        entities.delete(v)
                        count = count + 1
                    end
                end
            end
            notify.info(string.format("Deleted %d vehicles.", count))
        end)
    end)
    gui.add_option("Fetch Random Joke (HTTP)", "Tests the HTTP module", function()
        http.get("https://official-joke-api.appspot.com/random_joke", function(status, body, err, success)
            if success and status == 200 then
                -- Very basic manual parsing to avoid loading full json library for one call
                local setup = string.match(body, '"setup":"(.-)"')
                local punchline = string.match(body, '"punchline":"(.-)"')
                if setup and punchline then
                    notify.info(setup .. " ... " .. punchline)
                else
                    notify.error("Failed to parse joke.")
                end
            else
                notify.error("HTTP request failed.")
            end
        end, 10)
    end)
    gui.reset_submenu_context()

    -- Submenu: Protections
    local protections_menu = gui.add_submenu("Protections", "Defend against other modders")
    gui.set_submenu_context(protections_menu)
    gui.add_bool_option("Block Malicious Script Events", "Intercepts bad TSEs", state.block_script_events)
    gui.add_bool_option("Explosion & Fire Immunity", "Immune to fire/explosions", state.explosion_immunity)
    gui.add_bool_option("Attachment Protection", "Detaches ANY objects stuck to you", state.attachment_protection)
    gui.add_bool_option("Block Invalid Sync Nodes", "Hook network stream to drop bad syncs", state.block_sync_nodes)
    
    gui.add_break("Crazy Defenses")
    if state.projectile_shield == nil then state.projectile_shield = { value = false } end
    if state.auto_delete_cages == nil then state.auto_delete_cages = { value = false } end
    gui.add_bool_option("Projectile Shield", "Deletes incoming rockets and grenades", state.projectile_shield)
    gui.add_bool_option("Auto-Delete Cages", "Instantly destroys objects spawned on you", state.auto_delete_cages)
    gui.add_option("Break Free", "Instantly escape frozen states and clear area", function()
        script.run_in_fiber(function()
            local ped = self.get_ped()
            TASK.CLEAR_PED_TASKS_IMMEDIATELY(ped)
            ENTITY.DETACH_ENTITY(ped, true, true)

            local count = 0
            local my_veh = self.get_veh()
            for _, v in ipairs(entities.get_all_vehicles()) do
                if v ~= my_veh and entities.request_control(v) then
                    entities.delete(v); count = count + 1
                end
            end
            for _, p in ipairs(entities.get_all_peds()) do
                if p ~= ped and entities.request_control(p) then
                    entities.delete(p); count = count + 1
                end
            end
            for _, o in ipairs(entities.get_all_objects()) do
                if entities.request_control(o) then
                    entities.delete(o); count = count + 1
                end
            end

            notify.success(string.format("Broke free and cleared %d nearby entities.", count))
        end)
    end)
    gui.reset_submenu_context()
    -- Dynamic Submenu: Online Players
    local session_menu = gui.add_dynamic_submenu("Online Players", "Interact with players in the lobby", function()
        if not network.is_session_started() then
            gui.add_break("Not in a session.")
            return
        end

        gui.add_break("Player Count: " .. network.get_player_count())

        for i = 0, 31 do
            local p = players.get(i)
            if p and p:valid() then
                local p_name = p:get_name()
                local prefix = p:is_modder() and "[M] " or ""
                local suffix = p:is_local() and " (You)" or ""
                local display_name = prefix .. p_name .. suffix

                -- Individual player nested submenu
                local p_sub = gui.add_submenu(display_name, "Interact with " .. p_name)
                gui.set_submenu_context(p_sub)

                gui.add_break("General Options")
                gui.add_option("Teleport to Player", "Move to their exact coordinates", function()
                    local pos = p:get_pos()
                    -- Elevate slightly to avoid clipping through ground
                    self.teleport(pos.x, pos.y, pos.z + 1.5)
                    notify.success("Teleported to " .. p_name)
                end)

                if not p:is_local() then
                    gui.add_option("Send Friendly SMS", "Send an in-game text", function()
                        network.send_text_message(p:id(), "Hello from Ethereal AIO!")
                        notify.success("Message sent.")
                    end)

                    gui.add_break("Malicious Options")
                    gui.add_option("Smart Kick", "Removes player from session", function()
                        network.kick_player(p:id())
                        notify.warning("Attempting to kick " .. p_name)
                    end)

                    gui.add_option("Network Timeout", "Blocks their data synchronization", function()
                        p:set_timeout(10000, "all") -- Drops sync for 10 seconds
                        notify.info("Applied 10s sync timeout to " .. p_name)
                    end)
                end

                gui.reset_submenu_context()
            end
        end
    end)

    local settings_menu = gui.add_submenu("Settings", "Menu configuration and credits")
    gui.set_submenu_context(settings_menu)
    
    gui.add_break("Script Data")
    gui.add_option("Save Config", "Saves all current toggle states", function()
        save_config()
        notify.success("Configuration saved to disk.")
    end)
    gui.add_option("Reload Config", "Reloads toggles from disk", function()
        notify.info("Config reloaded from disk.")
    end)

    gui.add_break("Preferences")
    if state.auto_save == nil then state.auto_save = { value = true } end
    if state.verbose_logs == nil then state.verbose_logs = { value = false } end
    gui.add_bool_option("Auto-Save Config", "Automatically save on exit", state.auto_save)
    gui.add_bool_option("Verbose Logging", "Print debug info to console", state.verbose_logs)

    local credits_menu = gui.add_submenu("Credits", "The people who made this possible")
    gui.set_submenu_context(credits_menu)
    gui.add_break("Developer")
    gui.add_option("@iitztoasty/Toastizle", "Creator and Lead Developer", function() notify.info("Thank you for using YNAAIOMM!") end)
    gui.add_break("Helpers")
    gui.add_option("AG IDE", "AI Coding Assistant", function() end)
    gui.add_option("ScripthookV", "Alexander Blade", function() end)
    
    gui.reset_submenu_context()
end)




