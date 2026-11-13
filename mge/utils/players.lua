-- Players' start positions and rotations: the engageplayerpos / engageplayerrot gamerules, x y z per
-- player separated by commas ("2.50,0.00,1.00,-2.50,0.00,1.00"). Measured in game
-- (mge/debug_playerpos_probe.lua):
--   * a change in engageplayerpos moves every part of that player by exactly that much
--   * engageplayerrot turns the player around its head (the head stays where it is), x y z degrees
--     as rotX(x) * rotY(y) * rotZ(z) (mge/debug_playerrot_probe.lua)
--   * empty, "0" or all zeros means not set: engagedistance / engageheight place the players and
--     engageplayerrot is ignored. Custom player models are placed by it too (their part positions
--     are relative)
-- So edits work in offsets from what's in the world: Move adds to the position, Rotate changes the
-- rotation and shifts the position so the player's center stays put. In a mod without positions the
-- first edit fills them in for every player: a first guess, a reload, then the measured difference
-- is corrected (one reload you don't see), so nobody moves until the edit itself.
-- Changes go through set_gamerule, then MGE.syncGamerules writes them into the mod data (one undo
-- step, History.commit) and MGE.apply reloads so the game places the players.

local Mat3 = MGE.Mat3
local History = MGE.History
local HOOK_SET = MGE.hookname .. "_players"
local atan2 = math.atan2 or math.atan -- the game's Lua has atan2, newer Lua takes two arguments in atan

---@class Players
local Players = {}
MGE.Players = Players

local POS, ROT = "engageplayerpos", "engageplayerrot"

---@return integer
function Players.count()
    return math.max(tonumber(get_game_rules().numplayers) or 2, 1)
end

---Numbers of a gamerule list, 3 per player, nil when it isn't set (empty, "0" or all zeros)
---@param name string
---@return number[]?
local function readList(name)
    local value = tostring(get_gamerule(name) or "")
    if value:match("^[%s0%.,%-]*$") then return nil end
    local list = {}
    for part in (value .. ","):gmatch("([^,]*),") do table.insert(list, tonumber(part) or 0) end
    for i = #list + 1, Players.count() * 3 do list[i] = 0 end
    return list
end

---Precise like everything MGE writes (FileHandler.formatNumber), "2.50" style would round off up to
---0.005 on every edit and the rotation's center keeping would drift
---@param list number[]
---@param count integer? players, default numplayers (given while numplayers is being changed)
---@return string
local function formatList(list, count)
    local parts = {}
    for i = 1, (count or Players.count()) * 3 do parts[i] = MGE.FileHandler.formatNumber(list[i] or 0) end
    return table.concat(parts, ",")
end

---@return boolean the mod sets player positions
function Players.hasPositions()
    return readList(POS) ~= nil
end

---Position (engageplayerpos) of a player, nil when not set
---@param player integer 0-based
---@return number[]?
function Players.getPos(player)
    local list = readList(POS)
    return list and { list[player * 3 + 1], list[player * 3 + 2], list[player * 3 + 3] }
end

---Rotation in degrees (engageplayerrot) of a player, nil when positions aren't set
---@param player integer
---@return number[]?
function Players.getRot(player)
    if not Players.hasPositions() then return nil end
    local list = readList(ROT) or {}
    return { list[player * 3 + 1] or 0, list[player * 3 + 2] or 0, list[player * 3 + 3] or 0 }
end

-- live bodies ---------------------------------------------------------------------------------------

---Rotation of a body part, rows like the game's matrix (r0 r1 r2 is the first row)
---@param b BodyInfo
---@return number[][]
local function bodyRot(b)
    local r = b.rot
    return { { r.r0, r.r1, r.r2 }, { r.r4, r.r5, r.r6 }, { r.r8, r.r9, r.r10 } }
end

---@param player integer
---@return boolean the player is in the world
function Players.exists(player)
    if player < 0 or player >= Players.count() then return false end
    local ok, b = pcall(get_body_info, player, BODYPARTS.HEAD)
    return ok and b ~= nil and b.pos ~= nil
end

---Average of the body part positions
---@param player integer
---@return number[]
function Players.center(player)
    local s, n = { 0, 0, 0 }, 0
    for _, id in pairs(BODYPARTS) do
        local p = get_body_info(player, id).pos
        s[1], s[2], s[3], n = s[1] + p.x, s[2] + p.y, s[3] + p.z, n + 1
    end
    return { s[1] / n, s[2] / n, s[3] / n }
end

---Head position: engageplayerrot turns the player around it
---@param player integer
---@return number[]
function Players.head(player)
    local p = get_body_info(player, BODYPARTS.HEAD).pos
    return { p.x, p.y, p.z }
end

---Facing in degrees around z, from the groin's rotation (0: like player 0 without rotation)
---@param player integer
---@return number
function Players.yaw(player)
    local m = bodyRot(get_body_info(player, BODYPARTS.GROIN))
    return math.deg(atan2(m[2][1], m[1][1]))
end

---Live state of every body part, to preview a drag from and put back after it. Joint positions
---aren't kept: the game moves them with the bodies (mge/debug_playerjoint_probe.lua: bodies only,
---joints 0.000 off)
---@param player integer
---@return table
function Players.snapshot(player)
    local s = { bodies = {} }
    for _, id in pairs(BODYPARTS) do
        local b = get_body_info(player, id)
        s.bodies[id] = { pos = { b.pos.x, b.pos.y, b.pos.z }, rot = bodyRot(b) }
    end
    return s
end

---@type { players: integer[], pivot: number[], factor: number }? a scale drag in progress, the highlight
---draws these players scaled (the bodies can't be resized live)
Players.scalePreview = nil

---Puts every body part where fn says, from a snapshot (fn gets and returns a position, turn a
---rotation added to the part's own). Joints follow the bodies on their own: setting them too
---(set_joint_pos) moved them a second time, up to 0.28 off in the rotate preview
---@param player integer
---@param snap table Players.snapshot
---@param fn fun(p: number[]): number[]
---@param turn number[][]? rotation added to every part's own rotation
local function placeFrom(player, snap, fn, turn)
    for id, b in pairs(snap.bodies) do
        local p = fn(b.pos)
        set_body_pos(player, id, p[1], p[2], p[3])
        local m = turn and Mat3.mul(turn, b.rot) or b.rot
        set_body_rotation_m(player, id, MGE.Highlight.toMatrixTB(m))
    end
end

-- writing -------------------------------------------------------------------------------------------

---Writes the lists as gamerules, then into the mod data as one undo step, and reloads
---@param pos number[]
---@param rot number[]
---@param count integer? players, see formatList
local function commit(pos, rot, count)
    set_gamerule(POS, formatList(pos, count))
    set_gamerule(ROT, formatList(rot, count))
    MGE.syncGamerules()
    History.commit()
    MGE.apply()
end

---@type { waitFrames: integer, run: fun() }? work waiting for a reload: the fill-in of ensurePositions,
---the measured correction after a scale. Players are placed a couple of frames after the reload
local pending = nil

---Reloads (MGE.apply, no undo step) and runs fn once the players are placed again, to measure them
---@param fn fun()
local function afterReload(fn)
    pending = { run = fn }
    MGE.apply()
end

add_hook("draw3d", HOOK_SET, function()
    if not pending or MGE.reloadPending then return end
    pending.waitFrames = (pending.waitFrames or 3) - 1
    if pending.waitFrames > 0 then return end
    local done = pending
    pending = nil -- before running: the work may wait for another reload
    local ok, err = pcall(done.run)
    if not ok then echo("^04[MGE] players: " .. tostring(err)) end
end)

---Moves every listed player's positions so their centers are at targets (measured now), returns the
---corrected position list. The game places players in ways that aren't simple for custom models,
---measuring after a reload and adding the difference is exact: positions move a player as they are
---@param targets table<integer, number[]> player -> wanted center
---@return number[]
local function correctedPositions(targets)
    local pos = readList(POS) or {}
    for p, t in pairs(targets) do
        local c = Players.center(p)
        for k = 1, 3 do pos[p * 3 + k] = (pos[p * 3 + k] or 0) + t[k] - c[k] end
    end
    return pos
end

---Runs then() once the mod has positions for every player that keep them where they are now. With
---positions already set that's right away. Otherwise every player gets its head as a first guess
---(and its facing as rotation), the mod reloads without an undo step, and after the reload the
---difference between where the players should be and where they are is added
---@param then_ fun()
local function ensurePositions(then_)
    if Players.hasPositions() then return then_() end
    if pending then return end -- already waiting for a reload, the edit waiting for it wins
    local pos, rot, targets = {}, {}, {}
    for p = 0, Players.count() - 1 do
        local head = Players.head(p)
        targets[p] = Players.center(p)
        pos[p * 3 + 1], pos[p * 3 + 2], pos[p * 3 + 3] = head[1], head[2], head[3]
        rot[p * 3 + 1], rot[p * 3 + 2], rot[p * 3 + 3] = 0, 0, Players.yaw(p)
    end
    set_gamerule(POS, formatList(pos))
    set_gamerule(ROT, formatList(rot))
    -- no undo step: undoing the edit goes back to no positions at all
    afterReload(function()
        local corrected = correctedPositions(targets)
        set_gamerule(POS, formatList(corrected))
        -- the bodies are where the guess put them, shift them to the corrected place for the edit
        for p, t in pairs(targets) do
            local c, snap = Players.center(p), Players.snapshot(p)
            local d = { t[1] - c[1], t[2] - c[2], t[3] - c[3] }
            placeFrom(p, snap, function(q) return { q[1] + d[1], q[2] + d[2], q[3] + d[3] } end)
        end
        then_()
    end)
end

table.insert(MGE.onQuit, function() remove_hooks(HOOK_SET) end)

---@param players integer|integer[] one player or several
---@return integer[]
local function asList(players)
    return type(players) == "table" and players or { players }
end

---Moves players by offset (world units), one undo step for all of them
---@param players integer|integer[] 0-based
---@param offset number[]
function Players.moveBy(players, offset)
    local list = asList(players)
    -- camera follow, like moving objects: measured now, the bodies are placed after the reload
    MGE.Camera.followPlayer(list, { offset = offset })
    ensurePositions(function()
        local pos, rot = readList(POS) or {}, readList(ROT) or {}
        for _, player in ipairs(list) do
            for k = 1, 3 do pos[player * 3 + k] = (pos[player * 3 + k] or 0) + offset[k] end
        end
        commit(pos, rot)
    end)
end

---Center of several players (average of their centers), what the gizmo turns them around
---@param players integer[]
---@return number[]
function Players.groupCenter(players)
    local s = { 0, 0, 0 }
    for _, player in ipairs(players) do
        local c = Players.center(player)
        for k = 1, 3 do s[k] = s[k] + c[k] / #players end
    end
    return s
end

---Rotation matrix of engageplayerrot's x y z (degrees): rotX(x) * rotY(y) * rotZ(z), standard right
---handed, measured in game (mge/debug_playerrot_probe.lua: 30 40 50 gave exactly that matrix)
---@param r number[] x y z degrees
---@return number[][]
local function rotMatrix(r)
    return Mat3.mul(Mat3.rotX(math.rad(r[1])), Mat3.mul(Mat3.rotY(math.rad(r[2])), Mat3.rotZ(math.rad(r[3]))))
end

---Turns players by a world rotation around pivot (default: their center) as one rigid group, one undo
---step: each player's rotation is composed with it and written back as x y z, and its position moves
---so its center ends up at pivot + m (center - pivot). The game turns a player around its head h,
---which alone would put the center at h + m (center - h): the position takes up the difference
---@param players integer|integer[] 0-based
---@param m number[][] world rotation
---@param pivot number[]? default Players.groupCenter
function Players.rotateByMatrix(players, m, pivot)
    local list = asList(players)
    ensurePositions(function()
        local pos, rot = readList(POS) or {}, readList(ROT) or {}
        local p = pivot or Players.groupCenter(list)
        for _, player in ipairs(list) do
            local i = player * 3
            local current = rotMatrix({ rot[i + 1] or 0, rot[i + 2] or 0, rot[i + 3] or 0 })
            local x, y, z = Mat3.toEulerXYZ(Mat3.mul(m, current))
            rot[i + 1], rot[i + 2], rot[i + 3] = math.deg(x), math.deg(y), math.deg(z)
            local c, h = Players.center(player), Players.head(player)
            local wanted = Mat3.apply(m, { c[1] - p[1], c[2] - p[2], c[3] - p[3] })
            local byHead = Mat3.apply(m, { c[1] - h[1], c[2] - h[2], c[3] - h[3] })
            for k = 1, 3 do pos[i + k] = (pos[i + k] or 0) + (p[k] + wanted[k]) - (h[k] + byHead[k]) end
        end
        commit(pos, rot)
    end)
end

---Player's current rotation as a matrix: engageplayerrot when the mod sets positions, otherwise how the
---body is turned now (its groin)
---@param player integer
---@return number[][]
local function currentRotation(player)
    local rot = Players.hasPositions() and readList(ROT)
    if rot then
        local i = player * 3
        return rotMatrix({ rot[i + 1] or 0, rot[i + 2] or 0, rot[i + 3] or 0 })
    end
    return bodyRot(get_body_info(player, BODYPARTS.GROIN))
end

---Where the players panel shows the players, like objects' Pos / Rot rows for a selection: the group's
---center counted from the dojo center (MGE.POS_ORIGIN), and the rotation in degrees (x y z,
---engageplayerrot's order) of the first one, the group's frame (the picked player)
---@param players integer|integer[] first: the one whose rotation is shown
---@return number[] pos, number[] rot
function Players.shown(players)
    local list = asList(players)
    local c, o = Players.groupCenter(list), MGE.POS_ORIGIN or { 0, 0, 0 }
    local x, y, z = Mat3.toEulerXYZ(currentRotation(list[1]))
    return { c[1] - o[1], c[2] - o[2], c[3] - o[3] }, { math.deg(x), math.deg(y), math.deg(z) }
end

---Pos row: moves the players so their group's center is at the typed axes (counted from the dojo
---center), the other axes stay. They move together, the distances between them stay
---@param players integer|integer[]
---@param typed (number?)[]
function Players.setShownPos(players, typed)
    local shown = Players.shown(players)
    local offset = {}
    for k = 1, 3 do offset[k] = typed[k] and typed[k] - shown[k] or 0 end
    Players.moveBy(players, offset)
end

---Rot row: turns the players so the first one has the typed angles (degrees, the other axes stay),
---all of them as one rigid group around their center like the Rotate gizmo
---@param players integer|integer[] first: the one the angles are for
---@param typed (number?)[]
function Players.setShownRot(players, typed)
    local list = asList(players)
    local _, shownRot = Players.shown(list)
    local wanted = {}
    for k = 1, 3 do wanted[k] = typed[k] or shownRot[k] end
    -- the world rotation from the first one's now to the wanted one
    Players.rotateByMatrix(list, Mat3.mul(rotMatrix(wanted), Mat3.transpose(currentRotation(list[1]))))
end

---Average of partAverage over players: what the players panel shows for a selection
---@param players integer|integer[]
---@param key "density"|"strength"|"friction"|"bounce"
---@return number
function Players.groupPartAverage(players, key)
    local list, sum = asList(players), 0
    for _, player in ipairs(list) do sum = sum + Players.partAverage(player, key) end
    return #list > 0 and sum / #list or 0
end

---Turns a player around z by degrees, around its center
---@param player integer
---@param degrees number
function Players.rotateBy(player, degrees)
    Players.rotateByMatrix(player, Mat3.rotZ(math.rad(degrees)))
end

---Pos / Rot rows: sets the typed axes of a player's position or rotation (nil axes stay)
---@param player integer
---@param typedPos (number?)[]?
---@param typedRot (number?)[]?
function Players.setValues(player, typedPos, typedRot)
    ensurePositions(function()
        local pos, rot = readList(POS) or {}, readList(ROT) or {}
        for k = 1, 3 do
            if typedPos and typedPos[k] then pos[player * 3 + k] = typedPos[k] end
            if typedRot and typedRot[k] then rot[player * 3 + k] = typedRot[k] end
        end
        commit(pos, rot)
    end)
end

-- scaling -------------------------------------------------------------------------------------------
-- A player's size is its `player N` section: every body part's pos and sides, every joint's pos and
-- radius, in the model's own frame (engageplayerrot turns it, engageplayerpos moves it). Scaling
-- rewrites them, uniformly, around the model's center. Density stays: a bigger player is heavier,
-- like a bigger object. Joint strength stays too.

---Parts of a player section: ordered entries { kind, name, header, props = { { key, value } } },
---lines before the first part kept as they are
---@param lines string[]
---@return { preamble: string[], parts: table[] }
local function parseSection(lines)
    local out, current = { preamble = {}, parts = {} }, nil
    for _, line in ipairs(lines) do
        local kind, name = line:match("^%s*(%a+)%s+(%S+)%s*$")
        if kind == "body" or kind == "joint" then
            current = { kind = kind, name = name:lower(), header = line, props = {} }
            table.insert(out.parts, current)
        elseif current and line:match("%S") then
            local key, value = line:match("^%s*(%S+)%s*(.-)%s*$")
            table.insert(current.props, { key = key, value = value, raw = line })
        elseif not current then
            table.insert(out.preamble, line)
        end
    end
    return out
end

---@param part table parseSection entry
---@param key string
---@return string?
local function getProp(part, key)
    for _, p in ipairs(part.props) do if p.key == key then return p.value end end
    return nil
end

---@param part table
---@param key string
---@param value string
local function setProp(part, key, value)
    for _, p in ipairs(part.props) do
        if p.key == key then
            p.value, p.raw = value, nil
            return
        end
    end
    table.insert(part.props, { key = key, value = value })
end

---@param section { preamble: string[], parts: table[] }
---@return string[]
local function sectionLines(section)
    local lines = {}
    for _, l in ipairs(section.preamble) do table.insert(lines, l) end
    for _, part in ipairs(section.parts) do
        table.insert(lines, part.header or ("   " .. part.kind .. " " .. part.name))
        for _, p in ipairs(part.props) do
            table.insert(lines, p.raw or ("      " .. p.key .. " " .. p.value))
        end
    end
    return lines
end

---@param value string?
---@return number[]?
local function readVec(value)
    local x, y, z = tostring(value or ""):match("(%S+)%s+(%S+)%s+(%S+)")
    x, y, z = tonumber(x), tonumber(y), tonumber(z)
    return x and y and z and { x, y, z } or nil
end

---Rewrites a player's section scaled by factor around its model center: every body part and joint
---gets explicit pos and sides / radius lines (taken from the live body where the section has none),
---everything else stays. A player using the shared part lines (all players) gets its own section
---@param player integer
---@param factor number
local function scaleSection(player, factor)
    local ModData, FH = MGE.ModData, MGE.FileHandler
    local lines = FH.getPlayerLines(ModData.parsed, player) or FH.getSharedPlayerLines(ModData.parsed) or {}
    local section = parseSection(lines)
    local byKey = {}
    for _, part in ipairs(section.parts) do byKey[part.kind .. ":" .. part.name] = part end
    ---@return table
    local function partFor(kind, name)
        local key = kind .. ":" .. name
        if not byKey[key] then
            byKey[key] = { kind = kind, name = name, props = {} }
            table.insert(section.parts, byKey[key])
        end
        return byKey[key]
    end

    -- live -> model frame: model = ref + R^T (live - liveRef). The model's head as written, or any
    -- fixed point for a default body: a shift of the whole model is corrected after the reload
    local rot = readList(ROT) or {}
    local Rt = Mat3.transpose(rotMatrix({ rot[player * 3 + 1] or 0, rot[player * 3 + 2] or 0, rot[player * 3 + 3] or 0 }))
    local liveRef = Players.head(player)
    local ref = readVec(byKey["body:head"] and getProp(byKey["body:head"], "pos")) or { 1, 0.9, 2.9 }
    local function toModel(live)
        local r = Mat3.apply(Rt, { live[1] - liveRef[1], live[2] - liveRef[2], live[3] - liveRef[3] })
        return { ref[1] + r[1], ref[2] + r[2], ref[3] + r[3] }
    end

    local entries = {}
    for name, id in pairs(BODYPARTS) do
        local part = partFor("body", name:lower())
        local b = get_body_info(player, id)
        local pos = readVec(getProp(part, "pos")) or toModel({ b.pos.x, b.pos.y, b.pos.z })
        local sides = readVec(getProp(part, "sides")) or { b.sides.x, b.sides.y, b.sides.z }
        table.insert(entries, { part = part, pos = pos, sides = sides })
    end
    for name, id in pairs(JOINTS) do
        local part = partFor("joint", name:lower())
        local pos = readVec(getProp(part, "pos")) or toModel({ get_joint_pos(player, id) })
        local radius = tonumber(getProp(part, "radius")) or get_joint_radius(player, id)
        table.insert(entries, { part = part, pos = pos, radius = radius })
    end

    local center, n = { 0, 0, 0 }, 0
    for _, e in ipairs(entries) do
        if e.sides then
            for k = 1, 3 do center[k] = center[k] + e.pos[k] end
            n = n + 1
        end
    end
    for k = 1, 3 do center[k] = center[k] / n end
    local fmt = FH.formatNumbers
    for _, e in ipairs(entries) do
        local p = {}
        for k = 1, 3 do p[k] = center[k] + (e.pos[k] - center[k]) * factor end
        setProp(e.part, "pos", fmt(p[1], p[2], p[3]))
        if e.sides then
            setProp(e.part, "sides", fmt(e.sides[1] * factor, e.sides[2] * factor, e.sides[3] * factor))
        else
            setProp(e.part, "radius", FH.formatNumber(e.radius * factor))
        end
    end
    FH.setPlayerLines(ModData.parsed, player, sectionLines(section))
end

-- defaults for parts without the line, from the game's own modmaker.tbm (data/mod): every body part
-- 0.25 density, joint strengths per joint, every body part and joint 0.3 friction and 0.1 bounce
local DEFAULT_DENSITY = 0.25
local DEFAULT_STRENGTH = {
    neck = 1, chest = 4, lumbar = 3, abs = 3, r_pecs = 3, r_shoulder = 4, r_elbow = 2, l_pecs = 3,
    l_shoulder = 4, l_elbow = 2, r_wrist = 2, l_wrist = 2, r_glute = 4, l_glute = 4, r_hip = 2, l_hip = 2,
    r_knee = 4, l_knee = 4, r_ankle = 1, l_ankle = 1,
}
-- which parts have the line (body parts / joints) and its default per part name
local PART_KEYS = {
    density = { body = true, default = function() return DEFAULT_DENSITY end },
    strength = { joint = true, default = function(name) return DEFAULT_STRENGTH[name] or 1 end },
    friction = { body = true, joint = true, default = function() return 0.3 end },
    bounce = { body = true, joint = true, default = function() return 0.1 end },
}

---Calls fn(part, value) for every part a key applies to in a parsed player section, value being the
---line's number or the default. With create, parts missing from the section are added
---@param section table parseSection result
---@param key "density"|"strength"|"friction"|"bounce"
---@param create boolean
---@param fn fun(part: table|nil, value: number, name: string)
local function eachPart(section, key, create, fn)
    local spec = PART_KEYS[key]
    for _, kind in ipairs({ "body", "joint" }) do
        if spec[kind] then
            local byName = {}
            for _, part in ipairs(section.parts) do
                if part.kind == kind then byName[part.name] = part end
            end
            for name in pairs(kind == "body" and BODYPARTS or JOINTS) do
                name = name:lower()
                local part = byName[name]
                if not part and create then
                    part = { kind = kind, name = name, props = {} }
                    table.insert(section.parts, part)
                end
                fn(part, part and tonumber(getProp(part, key)) or spec.default(name), name)
            end
        end
    end
end

---A player's parsed section: its own lines, else the shared ones
local function playerSection(player)
    local ModData, FH = MGE.ModData, MGE.FileHandler
    return parseSection(FH.getPlayerLines(ModData.parsed, player) or FH.getSharedPlayerLines(ModData.parsed) or {})
end

---Average density of a player's body parts, strength of its joints, or friction / bounce of both, as
---the mod sets them (parts without the line count with the game's default): what the players panel shows
---@param player integer
---@param key "density"|"strength"|"friction"|"bounce"
---@return number
function Players.partAverage(player, key)
    local sum, n = 0, 0
    eachPart(playerSection(player), key, false, function(_, value)
        sum, n = sum + value, n + 1
    end)
    return n > 0 and sum / n or 0
end

---Rewrites a value of every part of players with change(value) -> new value, one undo step and a
---reload. Parts without the line get it, other lines stay. A player using the shared part lines gets its
---own section. Positions don't change, no correction needed
local function changeParts(list, key, change)
    local FH = MGE.FileHandler
    for _, player in ipairs(list) do
        local section = playerSection(player)
        eachPart(section, key, true, function(part, value)
            setProp(part, key, FH.formatNumber(change(value)))
        end)
        FH.setPlayerLines(MGE.ModData.parsed, player, sectionLines(section))
    end
    History.commit()
    MGE.apply() -- body and joint changes need a reload
end

---Multiplies a value of the parts of players (density: body parts, strength: joints, friction /
---bounce: both), their ratios stay
---@param players integer|integer[] 0-based
---@param key "density"|"strength"|"friction"|"bounce"
---@param factor number
function Players.multiplyParts(players, key, factor)
    local list = asList(players)
    if #list == 0 or factor < 0 or math.abs(factor - 1) < 1e-9 then return end
    changeParts(list, key, function(value) return value * factor end)
end

---Sets a value on every part of players (where a factor can't work: the average is 0)
---@param players integer|integer[] 0-based
---@param key "density"|"strength"|"friction"|"bounce"
---@param value number
function Players.setParts(players, key, value)
    local list = asList(players)
    if #list == 0 then return end
    changeParts(list, key, function() return value end)
end

---World bounds of a player's body parts (each part as a box / sphere / capsule's reach around its
---center, rotation ignored: close enough to put a player on the floor)
---@param player integer
---@return { min: number[], max: number[] }
function Players.bounds(player)
    local lo, hi = { math.huge, math.huge, math.huge }, { -math.huge, -math.huge, -math.huge }
    for _, id in pairs(BODYPARTS) do
        local b = get_body_info(player, id)
        local s = b.sides
        local half = b.shape == 0 and s.x or (b.shape == 2 and s.y / 2 + s.x) or math.max(s.x, s.y, s.z) / 2
        local p = { b.pos.x, b.pos.y, b.pos.z }
        for k = 1, 3 do
            lo[k], hi[k] = math.min(lo[k], p[k] - half), math.max(hi[k], p[k] + half)
        end
    end
    return { min = lo, max = hi }
end

---Scales players uniformly around pivot (default: their center) as one group, one undo step: every
---player's model by factor, and its center moves to pivot + factor (center - pivot). Where the game
---puts a rewritten model is measured after a reload and corrected with the position
---@param players integer|integer[] 0-based
---@param factor number
---@param pivot number[]? default Players.groupCenter
function Players.scaleBy(players, factor, pivot)
    local list = asList(players)
    if #list == 0 or factor <= 0 or math.abs(factor - 1) < 1e-9 then return end -- nothing selected / no change
    MGE.Camera.followPlayer(list, { factor = factor, pivot = pivot or Players.groupCenter(list) }) -- like moveBy
    ensurePositions(function()
        local p = pivot or Players.groupCenter(list)
        local targets = {}
        for _, player in ipairs(list) do
            local c = Players.center(player)
            targets[player] = { p[1] + (c[1] - p[1]) * factor, p[2] + (c[2] - p[2]) * factor, p[3] + (c[3] - p[3]) * factor }
            scaleSection(player, factor)
        end
        afterReload(function()
            local rot = readList(ROT) or {}
            commit(correctedPositions(targets), rot) -- the sections and the corrected positions, one undo step
        end)
    end)
end

-- adding and removing players -----------------------------------------------------------------------

Players.MAX = 4 -- the game's gamerules menu goes from one to four players
local NUMPLAYERS = "numplayers"
local DUPLICATE_GAP = 0.3 -- between the copied players and their copies, along x

---@return boolean room for n more players (says why not in chat)
local function haveRoom(n)
    if Players.count() + n <= Players.MAX then return true end
    echo("^04[MGE] a mod can have at most " .. Players.MAX .. " players")
    return false
end

---@param list integer[]
---@return { min: number[], max: number[] }
local function groupBounds(list)
    local lo, hi = { math.huge, math.huge, math.huge }, { -math.huge, -math.huge, -math.huge }
    for _, player in ipairs(list) do
        local b = Players.bounds(player)
        for k = 1, 3 do lo[k], hi[k] = math.min(lo[k], b.min[k]), math.max(hi[k], b.max[k]) end
    end
    return { min = lo, max = hi }
end

---Adds players after the last one, one undo step. Every entry is a copy of a player (its own part
---lines, rotation and position + shift) or false for a default body (nothing in the section, shared
---part lines still apply) whose position is first a guess. After the reload each new player is
---measured and corrected: copies to their source's center + shift, new bodies onto the floor at
---spawnPoint. Calls done(new ids) after the first reload, when the mod has them
---@param sources (integer|false)[]
---@param shift number[] for copies
---@param spawnPoint number[]? for default bodies (floor point), default in front of player 0
---@param done fun(ids: integer[])?
local function addPlayers(sources, shift, spawnPoint, done)
    if #sources == 0 or not haveRoom(#sources) then return end
    ensurePositions(function()
        if not haveRoom(#sources) then return end
        local ModData, FH = MGE.ModData, MGE.FileHandler
        local first = Players.count()
        local pos, rot = readList(POS) or {}, readList(ROT) or {}
        local targets, fresh, ids = {}, {}, {}
        for i, src in ipairs(sources) do
            local id = first + i - 1
            ids[i] = id
            if src then
                local c = Players.center(src)
                targets[id] = { c[1] + shift[1], c[2] + shift[2], c[3] + shift[3] }
                for k = 1, 3 do
                    pos[id * 3 + k] = (pos[src * 3 + k] or 0) + shift[k]
                    rot[id * 3 + k] = rot[src * 3 + k] or 0
                end
                local own = FH.getPlayerLines(ModData.parsed, src)
                if own then FH.setPlayerLines(ModData.parsed, id, own) else FH.renumberPlayers(ModData.parsed, { [id] = false }) end
            else
                -- a leftover section with this id (past the old numplayers) would give it that model
                FH.renumberPlayers(ModData.parsed, { [id] = false })
                local p = spawnPoint or Players.head(0)
                fresh[id] = p
                pos[id * 3 + 1], pos[id * 3 + 2], pos[id * 3 + 3] = p[1], p[2], p[3] + 1
                rot[id * 3 + 1], rot[id * 3 + 2], rot[id * 3 + 3] = 0, 0, 0
            end
        end
        local count = first + #sources
        set_gamerule(NUMPLAYERS, tostring(count))
        set_gamerule(POS, formatList(pos, count))
        set_gamerule(ROT, formatList(rot, count))
        afterReload(function()
            for id, p in pairs(fresh) do
                local b, c = Players.bounds(id), Players.center(id)
                local d = MGE.Camera.spawnShift(b, p) -- center over the point, lowest part on the floor
                targets[id] = { c[1] + d[1], c[2] + d[2], c[3] + d[3] }
            end
            if done then done(ids) end -- the mod has them now (numplayers loaded)
            commit(correctedPositions(targets), readList(ROT) or {}) -- one undo step for all of it
        end)
    end)
end

---New player with the default body (or the mod's shared part lines), standing on the floor at point
---@param point number[]? floor point, default in front of player 0
---@param done fun(ids: integer[])? called with the new id
function Players.addNew(point, done)
    addPlayers({ false }, { 0, 0, 0 }, point, done)
end

---Copies of players (their part lines, rotation), placed next to them along x as one group
---@param players integer|integer[] 0-based
---@param done fun(ids: integer[])? called with the copies' ids
function Players.duplicate(players, done)
    local list = asList(players)
    if #list == 0 then return end
    local b = groupBounds(list)
    addPlayers(list, { b.max[1] - b.min[1] + DUPLICATE_GAP, 0, 0 }, nil, done)
end

---Removes players, one undo step: their sections go, later players move down to fill the ids (their
---sections, positions and rotations with them), numplayers follows. At least one player stays.
---Positions are filled in first, so the players left stay where they are
---@param players integer|integer[] 0-based
---@param done fun(map: table<integer, integer|false>)? old id -> new id, false for removed
function Players.remove(players, done)
    local removed = {}
    for _, p in ipairs(asList(players)) do
        if p >= 0 and p < Players.count() then removed[p] = true end
    end
    local n = 0
    for _ in pairs(removed) do n = n + 1 end
    if n == 0 then return end
    if n >= Players.count() then
        echo("^04[MGE] a mod needs at least one player")
        return
    end
    ensurePositions(function()
        local count = Players.count()
        local pos, rot = readList(POS) or {}, readList(ROT) or {}
        local map, newPos, newRot, kept = {}, {}, {}, 0
        for p = 0, count - 1 do
            if removed[p] then
                map[p] = false
            else
                map[p] = kept
                for k = 1, 3 do
                    newPos[kept * 3 + k] = pos[p * 3 + k] or 0
                    newRot[kept * 3 + k] = rot[p * 3 + k] or 0
                end
                kept = kept + 1
            end
        end
        -- one pass: every header is renamed from its old id, a rename never meets a renamed one
        MGE.FileHandler.renumberPlayers(MGE.ModData.parsed, map)
        set_gamerule(NUMPLAYERS, tostring(kept))
        if done then done(map) end
        commit(newPos, newRot, kept)
    end)
end

-- gizmo target --------------------------------------------------------------------------------------

---Gizmo target for one or several players (utils/gizmo.lua): Move, Rotate (rings on the world axes)
---and uniform Scale as one group around their shared center. Measured when made, so the pivot stays
---where the drag started while the preview moves the bodies
---@param players integer|integer[] 0-based
---@return table?
function Players.target(players)
    if pending then return nil end -- waiting for a reload, the players are about to be placed again
    local list = {}
    for _, player in ipairs(asList(players)) do
        if Players.exists(player) then table.insert(list, player) end
    end
    if #list == 0 then return nil end
    local snaps, pivot = nil, Players.groupCenter(list)
    -- Scale: the white cube only, players grow and shrink evenly (Players.scaleBy)
    local t = { players = list, scalable = true, uniformScaleOnly = true }
    function t.pivot() return pivot end
    function t.frame() return Mat3.IDENTITY end
    function t.begin()
        snaps = {}
        for _, player in ipairs(list) do snaps[player] = Players.snapshot(player) end
    end
    ---@param fn fun(p: number[]): number[]
    ---@param turn number[][]?
    local function placeAll(fn, turn)
        if not snaps then return end
        for player, snap in pairs(snaps) do placeFrom(player, snap, fn, turn) end
    end
    function t.previewMove(offset)
        placeAll(function(p) return { p[1] + offset[1], p[2] + offset[2], p[3] + offset[3] } end)
    end
    function t.previewRotate(m)
        placeAll(function(p)
            local r = Mat3.apply(m, { p[1] - pivot[1], p[2] - pivot[2], p[3] - pivot[3] })
            return { pivot[1] + r[1], pivot[2] + r[2], pivot[3] + r[3] }
        end, m)
    end
    -- Scale isn't previewed on the bodies: set_body_sides / set_joint_radius don't change anything
    -- live (mge/debug_playerscale_probe.lua: chest sides stayed 0.5, wanted 0.75) and joints keep their
    -- old offsets, the parts looked scattered. The highlight draws the scaled players instead
    -- (Players.scalePreview, utils/highlight.lua), the real ones stay until the release reloads
    function t.previewScale(factors)
        Players.scalePreview = { players = list, pivot = pivot, factor = factors[1] }
    end
    function t.restoreLive()
        Players.scalePreview = nil
        placeAll(function(p) return p end)
    end
    function t.scaleBy(factors)
        t.restoreLive()
        Players.scaleBy(list, factors[1], pivot)
    end
    function t.moveBy(offset)
        t.restoreLive()
        Players.moveBy(list, offset)
    end
    function t.rotateByMatrix(m)
        t.restoreLive()
        Players.rotateByMatrix(list, m, pivot)
    end
    return t
end

return Players
