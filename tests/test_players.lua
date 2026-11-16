-- utils/players.lua against a small simulated game: the engageplayerpos / engageplayerrot gamerules and
-- the bodies the game places from them, as measured in game (the header of players.lua):
--   * with positions set, a player's parts sit at pos + R (part - head) + OFFSET, R being
--     engageplayerrot (rotX * rotY * rotZ). OFFSET stands in for where the game really puts a model,
--     which MGE doesn't know and measures after a reload (correctedPositions)
--   * engageplayerrot does nothing in a mod without a version line (the old format)
--   * without positions the game places them itself: player 1 turned 180 degrees and moved
-- Bodies are placed when the mod (re)loads (MGE.apply), live moves (set_body_pos) last until the next
-- one. Players.lua's draw3d hook runs the work waiting for a reload, tick() calls it
local T = ...
local Mat3, FileHandler = MGE.Mat3, MGE.FileHandler

local OFFSET = { 0.3, -0.2, 0.1 }
local DEFAULT_MODEL = {
    body = { head = { 1, 0.85, 2.65 }, groin = { 1, 1, 1.55 }, chest = { 1, 0.9, 1.95 }, l_foot = { 1.2, 0.9, 0.1 } },
    joint = { neck = { 1, 0.9, 2.5 }, l_knee = { 1.2, 1, 0.8 } },
}
local BODY_IDS = { HEAD = 0, GROIN = 1, CHEST = 2, L_FOOT = 3 }
local JOINT_IDS = { NECK = 0, L_KNEE = 1 }

local function rotMatrix(r)
    return Mat3.mul(Mat3.rotX(math.rad(r[1])), Mat3.mul(Mat3.rotY(math.rad(r[2])), Mat3.rotZ(math.rad(r[3]))))
end

---Starts the simulated game on a mod text, loads a fresh Players on it and runs fn. Globals and MGE
---fields are put back afterwards
---@param text string the mod
---@param fn fun(sim: table)
local function withGame(text, fn)
    local G = { "BODYPARTS", "JOINTS", "get_game_rules", "get_gamerule", "set_gamerule", "get_body_info",
        "get_joint_pos", "get_joint_radius", "set_body_pos", "set_body_rotation_m", "add_hook" }
    local savedGlobals = {}
    for _, name in ipairs(G) do savedGlobals[name] = _G[name] end
    local savedMGE = {}
    for _, name in ipairs({ "Players", "ModData", "History", "apply", "syncGamerules", "Camera", "Highlight",
        "reloadPending", "POS_ORIGIN" }) do savedMGE[name] = MGE[name] end

    T.files["players.tbm"] = text
    local sim = { rules = {}, loaded = {}, live = {}, commits = 0, reloads = 0 }
    sim.parsed = FileHandler.ParseMod("players.tbm")
    for _, line in ipairs(sim.parsed.ignores) do
        local key, value = line:match("^%s*(%S+)%s+(.-)%s*$")
        if key == "numplayers" or key == "engageplayerpos" or key == "engageplayerrot" then sim.rules[key] = value end
    end
    sim.rules.numplayers = sim.rules.numplayers or "2"

    ---@return number[] list or nil when not set (empty, 0, all zeros)
    local function list(value)
        value = tostring(value or "")
        if value:match("^[%s0%.,%-]*$") then return nil end
        local out = {}
        for part in (value .. ","):gmatch("([^,]*),") do out[#out + 1] = tonumber(part) or 0 end
        return out
    end
    local function versioned()
        for _, line in ipairs(sim.parsed.ignores) do if line:match("^%s*version%s+%d") then return true end end
        return false
    end
    ---The model of a player: its section's pos lines, the default body where there are none
    local function model(p)
        local lines = FileHandler.getPlayerLines(sim.parsed, p) or FileHandler.getSharedPlayerLines(sim.parsed) or {}
        local m = { body = {}, joint = {} }
        for kind, parts in pairs(DEFAULT_MODEL) do
            for name, v in pairs(parts) do m[kind][name] = { v[1], v[2], v[3] } end
        end
        local kind, name
        for _, line in ipairs(lines) do
            local k, n = line:match("^%s*(%a+)%s+(%S+)%s*$")
            if k == "body" or k == "joint" then
                kind, name = k, n
            elseif kind then
                local x, y, z = line:match("^%s*pos%s+(%S+)%s+(%S+)%s+(%S+)")
                if x and m[kind][name] then m[kind][name] = { tonumber(x), tonumber(y), tonumber(z) } end
            end
        end
        return m
    end
    ---Places every player from the loaded gamerules
    local function place()
        sim.world = {}
        local pos, rot = list(sim.loaded.engageplayerpos), list(sim.loaded.engageplayerrot) or {}
        for p = 0, tonumber(sim.loaded.numplayers) - 1 do
            local m = model(p)
            local head = m.body.head
            local R, base
            if pos then
                R = versioned() and rotMatrix({ rot[p * 3 + 1] or 0, rot[p * 3 + 2] or 0, rot[p * 3 + 3] or 0 }) or Mat3.IDENTITY
                base = { pos[p * 3 + 1] + OFFSET[1], pos[p * 3 + 2] + OFFSET[2], pos[p * 3 + 3] + OFFSET[3] }
            else
                R = p == 1 and Mat3.rotZ(math.pi) or Mat3.IDENTITY
                base = p == 1 and { head[1], head[2] + 2.5, head[3] } or head
            end
            local placed = { body = {}, joint = {}, rot = R }
            for kind, parts in pairs(m) do
                for name, v in pairs(parts) do
                    local r = Mat3.apply(R, { v[1] - head[1], v[2] - head[2], v[3] - head[3] })
                    placed[kind][name] = { base[1] + r[1], base[2] + r[2], base[3] + r[3] }
                end
            end
            sim.world[p] = placed
        end
        sim.live = {}
    end
    function sim.reload()
        sim.loaded = {}
        for k, v in pairs(sim.rules) do sim.loaded[k] = v end
        sim.reloads = sim.reloads + 1
        place()
    end
    local hook
    function sim.tick(n)
        for _ = 1, n or 5 do if hook then hook() end end
    end
    function sim.center(p)
        local s, n = { 0, 0, 0 }, 0
        for name in pairs(DEFAULT_MODEL.body) do
            local v = sim.bodyPos(p, name)
            for k = 1, 3 do s[k] = s[k] + v[k] end
            n = n + 1
        end
        return { s[1] / n, s[2] / n, s[3] / n }
    end
    function sim.bodyPos(p, name)
        local live = sim.live[p .. ":" .. name]
        return live or sim.world[p].body[name]
    end

    BODYPARTS, JOINTS = BODY_IDS, JOINT_IDS
    local bodyName, jointName = {}, {}
    for name, id in pairs(BODY_IDS) do bodyName[id] = name:lower() end
    for name, id in pairs(JOINT_IDS) do jointName[id] = name:lower() end
    get_game_rules = function() return { numplayers = sim.rules.numplayers } end
    get_gamerule = function(name) return sim.rules[name] end
    set_gamerule = function(name, value) sim.rules[name] = value end
    get_body_info = function(p, id)
        local v = sim.bodyPos(p, bodyName[id])
        local m = sim.world[p].rot
        return { pos = { x = v[1], y = v[2], z = v[3] }, sides = { x = 0.2, y = 0.2, z = 0.2 }, shape = 1,
            rot = { r0 = m[1][1], r1 = m[1][2], r2 = m[1][3], r4 = m[2][1], r5 = m[2][2], r6 = m[2][3],
                r8 = m[3][1], r9 = m[3][2], r10 = m[3][3] } }
    end
    get_joint_pos = function(p, id)
        local v = sim.world[p].joint[jointName[id]]
        return v[1], v[2], v[3]
    end
    get_joint_radius = function() return 0.1 end
    set_body_pos = function(p, id, x, y, z) sim.live[p .. ":" .. bodyName[id]] = { x, y, z } end
    set_body_rotation_m = function() end
    add_hook = function(event, _, f) if event == "draw3d" then hook = f end end

    MGE.ModData = { parsed = sim.parsed }
    MGE.History = { commit = function() sim.commits = sim.commits + 1 end }
    MGE.apply = function() sim.reload() end
    MGE.syncGamerules = function() end
    MGE.Camera = { followPlayer = function() end }
    MGE.Highlight = { toMatrixTB = function(m) return m end }
    MGE.reloadPending = false
    MGE.POS_ORIGIN = { 0, 0, 0 }

    sim.reload()
    local ok, err = pcall(function()
        dofile(MGE.scriptPath .. "utils/players.lua")
        fn(sim)
    end)
    for _, name in ipairs(G) do _G[name] = savedGlobals[name] end
    for name, v in pairs(savedMGE) do MGE[name] = v end
    MGE.reloadPending = savedMGE.reloadPending
    if not ok then error(err, 0) end
end

local NO_POSITIONS = "#!/usr/bin/toribash\ngamerule\nnumplayers 2\n"
local POSITIONED = "#!/usr/bin/toribash\nversion 15\ngamerule\nnumplayers 2\n" ..
    "engageplayerpos 0,0,3,0,3,3\nengageplayerrot 0,0,0,0,0,180\n"

---Yaw (degrees, 0-360) of a player in the simulated world, from its placed rotation
local function yaw(sim, p)
    local m = sim.world[p].rot
    return math.deg(math.atan2(m[2][1], m[1][1])) % 360
end

T.test("players: whole degrees", function()
    withGame(POSITIONED, function()
        local whole = MGE.Players.wholeDegrees
        T.eq(whole(2.5), 3, "half up")
        T.eq(whole(-2.5), -2, "half up, negative")
        T.eq(whole(-0.4), 0, "small negative is 0")
        T.eq(tostring(whole(-0.4)), "0", "not -0")
    end)
end)

T.test("players: moving a positioned player moves it exactly", function()
    withGame(POSITIONED, function(sim)
        local before0, before1 = sim.center(0), sim.center(1)
        MGE.Players.moveBy(1, { 0.5, -1, 0.25 })
        sim.tick()
        local after1 = sim.center(1)
        T.nearList({ after1[1] - before1[1], after1[2] - before1[2], after1[3] - before1[3] }, { 0.5, -1, 0.25 }, 1e-9, "moved by the offset")
        T.nearList(sim.center(0), before0, 1e-9, "the other player stays")
        T.eq(sim.commits, 1, "one undo step")
    end)
end)

T.test("players: turning a positioned player keeps its center, whole degrees", function()
    withGame(POSITIONED, function(sim)
        local before = sim.center(0)
        MGE.Players.rotateBy(0, 90.4)
        sim.tick()
        T.near(yaw(sim, 0), 90, 1e-9, "turned 90 (90.4 rounded)")
        T.nearList(sim.center(0), before, 1e-9, "center kept")
        T.eq(sim.rules.engageplayerrot:match("^([^,]*,[^,]*,[^,]*)"), "0,0,90", "written in whole degrees")
    end)
end)

T.test("players: Rot row turns to the typed angle", function()
    withGame(POSITIONED, function(sim)
        local before = sim.center(1)
        MGE.Players.setShownRot({ 1 }, { nil, nil, 45 })
        sim.tick()
        T.near(yaw(sim, 1), 45, 1e-9, "player 1 at 45")
        T.nearList(sim.center(1), before, 1e-9, "center kept")
        local _, rot = MGE.Players.shown({ 1 })
        T.near(rot[3], 45, 1e-9, "shown again as 45")
    end)
end)

T.test("players: a mod without positions or version gets both, nobody jumps", function()
    withGame(NO_POSITIONS, function(sim)
        local before0, before1 = sim.center(0), sim.center(1)
        local yaw1 = yaw(sim, 1)
        T.ok(not MGE.Players.hasPositions(), "no positions to start with")
        MGE.Players.rotateBy(1, 30)
        sim.tick() -- the fill-in's reload and correction, then the turn
        sim.tick()
        T.ok(MGE.Players.hasPositions(), "positions filled in")
        local versioned = false
        for _, line in ipairs(sim.parsed.ignores) do if line:match("^version 15") then versioned = true end end
        T.ok(versioned, "version line added (engageplayerrot works only with it)")
        T.nearList(sim.center(0), before0, 1e-9, "player 0 not moved")
        T.nearList(sim.center(1), before1, 1e-9, "player 1 turned in place")
        T.near(yaw(sim, 1), (yaw1 + 30) % 360, 1e-9, "player 1 turned by 30")
        T.eq(sim.commits, 1, "the fill-in isn't an undo step of its own")
    end)
end)

T.test("players: scaling doubles the size, the center stays", function()
    withGame(POSITIONED, function(sim)
        local Players = MGE.Players
        T.near(Players.size(0), 1, 1e-9, "default body: size 1")
        local before = sim.center(0)
        Players.scaleBy({ 0 }, 2)
        sim.tick()
        sim.tick()
        T.near(Players.size(0), 2, 1e-9, "size 2")
        T.near(Players.size(1), 1, 1e-9, "the other player stays")
        T.nearList(sim.center(0), before, 1e-9, "center kept after the correction")
        T.near(Players.groupSize({ 0, 1 }), 1.5, 1e-9, "group size: the average")
        T.eq(sim.commits, 1, "one undo step")
    end)
end)
