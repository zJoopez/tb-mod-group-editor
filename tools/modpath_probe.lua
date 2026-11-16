-- In-game probe: what the game tells a script about the loaded mod, to pick how MGE finds the mod's file.
-- Loads each mod in TARGETS with /lm, one after another, and records for each:
--   * the mod gamerule (get_game_rules().mod and get_gamerule("mod")): only the file name, or the folder too?
--   * find_mod of that name, and of the path typed: which file each one names
--   * how many objects exist at match_begin and a few frames later, and the first one's position: are the
--     objects in the world when match_begin runs (MGE reads the mod there)?
-- Run it WITHOUT MGE (MGE reloads on every mod change): /ls mge/tools/modpath_probe.lua
-- The results go to chat and to data/script/modpath_probe.log (outside the MGE repo). At the end the mod
-- that was loaded before is loaded again. /ls the script again to run it again.
-- Dev only: tools/ isn't in the release zip.

local HOOKS = "mge_modpath_probe"
remove_hooks(HOOKS)

-- the mods to load, as typed after /lm. Missing ones are fine: the probe says so and goes on
local TARGETS = {
    "classic",
    "modmaker/classic",
    "katana",
    "Combat/Weapons/katana",
    "modmaker/katana",
    "modmaker",
    "modmaker/modmaker",
}
local LATER_FRAMES = 15 -- frames after match_begin for the second object count
local TIMEOUT_FRAMES = 300 -- no match_begin this long after /lm: the load failed, go on

local LOG_PATH = "modpath_probe.log" -- from data/script (the game's io.open)
local log = io.open(LOG_PATH, "w")
local function say(text)
    echo("^04[probe] " .. text)
    if log then
        log:write(text, "\n")
        log:flush()
    end
end

local function show(v)
    if v == nil then return "nil" end
    return string.format("%q", tostring(v))
end

---Objects in the world: how many of ids 0-255 exist, and the first one's position
---@return string
local function objects()
    local count, first = 0, nil
    for i = 0, 255 do
        local ok, x, y, z = pcall(get_obj_pos, i)
        if ok and x ~= nil then
            count = count + 1
            first = first or string.format("id %d at %.3f %.3f %.3f", i + 1, x, y, z)
        end
    end
    return count .. " objects" .. (first and (", first " .. first) or "")
end

local before = get_game_rules().mod
local index = 0
local state = nil -- { target, frames, begun, laterIn }

local function finish()
    remove_hooks(HOOKS)
    say("done, loading the mod from before: " .. tostring(before))
    if log then log:close() end
    run_cmd("lm " .. tostring(before))
end

local function nextTarget()
    index = index + 1
    local target = TARGETS[index]
    if not target then return finish() end
    say("")
    say("=== /lm " .. target)
    say("find_mod(typed)        " .. show(find_mod(target)) .. "   with .tbm: " .. show(find_mod(target .. ".tbm")))
    state = { target = target, frames = 0, begun = false }
    run_cmd("lm " .. target)
end

add_hook("match_begin", HOOKS, function()
    if not state or state.begun then return end
    state.begun = true
    local mod = get_game_rules().mod
    say("get_game_rules().mod   " .. show(mod))
    say("get_gamerule(\"mod\")    " .. show(get_gamerule("mod")))
    say("find_mod(rule)         " .. show(find_mod(mod)))
    say("at match_begin         " .. objects())
    state.laterIn = LATER_FRAMES
end)

add_hook("draw2d", HOOKS, function()
    if not state then return end
    state.frames = state.frames + 1
    if state.begun then
        state.laterIn = state.laterIn - 1
        if state.laterIn <= 0 then
            say(LATER_FRAMES .. " frames later        " .. objects())
            state = nil
            nextTarget()
        end
    elseif state.frames > TIMEOUT_FRAMES then
        say("no match_begin after " .. TIMEOUT_FRAMES .. " frames: the load failed (missing mod?)")
        state = nil
        nextTarget()
    end
end)

say("mod before: " .. show(before) .. ", " .. #TARGETS .. " mods to load")
nextTarget()
