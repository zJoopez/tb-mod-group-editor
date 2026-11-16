















local Mat3 = MGE.Mat3
local History = MGE.History
local HOOK_SET = MGE.hookname .. "_players"
local atan2 = math.atan2 or math.atan


local Players = {}
MGE.Players = Players

local POS, ROT = "engageplayerpos", "engageplayerrot"


function Players.count()
    return math.max(tonumber(get_game_rules().numplayers) or 2, 1)
end




local function readList(name)
    local value = tostring(get_gamerule(name) or "")
    if value:match("^[%s0%.,%-]*$") then return nil end
    local list = {}
    for part in (value .. ","):gmatch("([^,]*),") do table.insert(list, tonumber(part) or 0) end
    for i = #list + 1, Players.count() * 3 do list[i] = 0 end
    return list
end






local function formatList(list, count)
    local parts = {}
    for i = 1, (count or Players.count()) * 3 do parts[i] = MGE.FileHandler.formatNumber(list[i] or 0) end
    return table.concat(parts, ",")
end






function Players.wholeDegrees(degrees)
    local r = math.floor(degrees + 0.5)
    return r == 0 and 0 or r
end
local wholeDegrees = Players.wholeDegrees


function Players.hasPositions()
    return readList(POS) ~= nil
end




function Players.getPos(player)
    local list = readList(POS)
    return list and { list[player * 3 + 1], list[player * 3 + 2], list[player * 3 + 3] }
end




function Players.getRot(player)
    if not Players.hasPositions() then return nil end
    local list = readList(ROT) or {}
    return { list[player * 3 + 1] or 0, list[player * 3 + 2] or 0, list[player * 3 + 3] or 0 }
end






local function bodyRot(b)
    local r = b.rot
    return { { r.r0, r.r1, r.r2 }, { r.r4, r.r5, r.r6 }, { r.r8, r.r9, r.r10 } }
end



function Players.exists(player)
    if player < 0 or player >= Players.count() then return false end
    local ok, b = pcall(get_body_info, player, BODYPARTS.HEAD)
    return ok and b ~= nil and b.pos ~= nil
end




function Players.center(player)
    local s, n = { 0, 0, 0 }, 0
    for _, id in pairs(BODYPARTS) do
        local p = get_body_info(player, id).pos
        s[1], s[2], s[3], n = s[1] + p.x, s[2] + p.y, s[3] + p.z, n + 1
    end
    return { s[1] / n, s[2] / n, s[3] / n }
end




function Players.head(player)
    local p = get_body_info(player, BODYPARTS.HEAD).pos
    return { p.x, p.y, p.z }
end




function Players.yaw(player)
    local m = bodyRot(get_body_info(player, BODYPARTS.GROIN))
    return math.deg(atan2(m[2][1], m[1][1]))
end






function Players.snapshot(player)
    local s = { bodies = {} }
    for _, id in pairs(BODYPARTS) do
        local b = get_body_info(player, id)
        s.bodies[id] = { pos = { b.pos.x, b.pos.y, b.pos.z }, rot = bodyRot(b) }
    end
    return s
end



Players.scalePreview = nil








local function placeFrom(player, snap, fn, turn)
    for id, b in pairs(snap.bodies) do
        local p = fn(b.pos)
        set_body_pos(player, id, p[1], p[2], p[3])
        local m = turn and Mat3.mul(turn, b.rot) or b.rot
        set_body_rotation_m(player, id, MGE.Highlight.toMatrixTB(m))
    end
end







local function commit(pos, rot, count)
    set_gamerule(POS, formatList(pos, count))
    set_gamerule(ROT, formatList(rot, count))

    MGE.FileHandler.ensureVersion(MGE.ModData.parsed)
    MGE.syncGamerules()
    History.commit()
    MGE.apply()
end



local pending = nil



local function afterReload(fn)
    pending = { run = fn }
    MGE.FileHandler.ensureVersion(MGE.ModData.parsed)
    MGE.apply()
end

add_hook("draw3d", HOOK_SET, function()
    if not pending or MGE.reloadPending then return end
    pending.waitFrames = (pending.waitFrames or 3) - 1
    if pending.waitFrames > 0 then return end
    local done = pending
    pending = nil
    local ok, err = pcall(done.run)
    if not ok then MGE.say("players: " .. tostring(err)) end
end)






local function correctedPositions(targets)
    local pos = readList(POS) or {}
    for p, t in pairs(targets) do
        local c = Players.center(p)
        for k = 1, 3 do pos[p * 3 + k] = (pos[p * 3 + k] or 0) + t[k] - c[k] end
    end
    return pos
end






local function ensurePositions(then_)
    if Players.hasPositions() then return then_() end
    if pending then return end
    local pos, rot, targets = {}, {}, {}
    for p = 0, Players.count() - 1 do
        local head = Players.head(p)
        targets[p] = Players.center(p)
        pos[p * 3 + 1], pos[p * 3 + 2], pos[p * 3 + 3] = head[1], head[2], head[3]
        rot[p * 3 + 1], rot[p * 3 + 2], rot[p * 3 + 3] = 0, 0, wholeDegrees(Players.yaw(p))
    end
    set_gamerule(POS, formatList(pos))
    set_gamerule(ROT, formatList(rot))

    afterReload(function()
        local corrected = correctedPositions(targets)
        set_gamerule(POS, formatList(corrected))

        for p, t in pairs(targets) do
            local c, snap = Players.center(p), Players.snapshot(p)
            local d = { t[1] - c[1], t[2] - c[2], t[3] - c[3] }
            placeFrom(p, snap, function(q) return { q[1] + d[1], q[2] + d[2], q[3] + d[3] } end)
        end
        then_()
    end)
end

table.insert(MGE.onQuit, function() remove_hooks(HOOK_SET) end)



local function asList(players)
    return type(players) == "table" and players or { players }
end




function Players.moveBy(players, offset)
    local list = asList(players)

    MGE.Camera.followPlayer(list, { offset = offset })
    ensurePositions(function()
        local pos, rot = readList(POS) or {}, readList(ROT) or {}
        for _, player in ipairs(list) do
            for k = 1, 3 do pos[player * 3 + k] = (pos[player * 3 + k] or 0) + offset[k] end
        end
        commit(pos, rot)
    end)
end




function Players.groupCenter(players)
    local s = { 0, 0, 0 }
    for _, player in ipairs(players) do
        local c = Players.center(player)
        for k = 1, 3 do s[k] = s[k] + c[k] / #players end
    end
    return s
end





local function rotMatrix(r)
    return Mat3.fromEulerDegrees(r[1], r[2], r[3])
end








function Players.rotateByMatrix(players, m, pivot)
    local list = asList(players)
    ensurePositions(function()
        local pos, rot = readList(POS) or {}, readList(ROT) or {}
        local p = pivot or Players.groupCenter(list)
        for _, player in ipairs(list) do
            local i = player * 3
            local current = rotMatrix({ rot[i + 1] or 0, rot[i + 2] or 0, rot[i + 3] or 0 })
            local x, y, z = Mat3.toEulerXYZ(Mat3.mul(m, current))


            local turned = { wholeDegrees(math.deg(x)), wholeDegrees(math.deg(y)), wholeDegrees(math.deg(z)) }
            rot[i + 1], rot[i + 2], rot[i + 3] = turned[1], turned[2], turned[3]
            local mi = Mat3.mul(rotMatrix(turned), Mat3.transpose(current))
            local c, h = Players.center(player), Players.head(player)
            local wanted = Mat3.apply(mi, { c[1] - p[1], c[2] - p[2], c[3] - p[3] })
            local byHead = Mat3.apply(mi, { c[1] - h[1], c[2] - h[2], c[3] - h[3] })
            for k = 1, 3 do pos[i + k] = (pos[i + k] or 0) + (p[k] + wanted[k]) - (h[k] + byHead[k]) end
        end
        commit(pos, rot)
    end)
end





local function currentRotation(player)
    local rot = Players.hasPositions() and readList(ROT)
    if rot then
        local i = player * 3
        return rotMatrix({ rot[i + 1] or 0, rot[i + 2] or 0, rot[i + 3] or 0 })
    end
    return bodyRot(get_body_info(player, BODYPARTS.GROIN))
end






function Players.shown(players)
    local list = asList(players)
    local c, o = Players.groupCenter(list), MGE.POS_ORIGIN or { 0, 0, 0 }
    local x, y, z = Mat3.toEulerXYZ(currentRotation(list[1]))
    return { c[1] - o[1], c[2] - o[2], c[3] - o[3] }, { math.deg(x), math.deg(y), math.deg(z) }
end





function Players.setShownPos(players, typed)
    local shown = Players.shown(players)
    local offset = {}
    for k = 1, 3 do offset[k] = typed[k] and typed[k] - shown[k] or 0 end
    Players.moveBy(players, offset)
end





function Players.setShownRot(players, typed)
    local list = asList(players)
    local _, shownRot = Players.shown(list)
    local wanted = {}
    for k = 1, 3 do wanted[k] = typed[k] or shownRot[k] end

    Players.rotateByMatrix(list, Mat3.mul(rotMatrix(wanted), Mat3.transpose(currentRotation(list[1]))))
end





function Players.groupPartAverage(players, key)
    local list, sum = asList(players), 0
    for _, player in ipairs(list) do sum = sum + Players.partAverage(player, key) end
    return #list > 0 and sum / #list or 0
end




function Players.rotateBy(player, degrees)
    Players.rotateByMatrix(player, Mat3.rotZ(math.rad(degrees)))
end





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




local function getProp(part, key)
    for _, p in ipairs(part.props) do if p.key == key then return p.value end end
    return nil
end




local function setProp(part, key, value)
    for _, p in ipairs(part.props) do
        if p.key == key then
            p.value, p.raw = value, nil
            return
        end
    end
    table.insert(part.props, { key = key, value = value })
end



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



local function readVec(value)
    local x, y, z = tostring(value or ""):match("(%S+)%s+(%S+)%s+(%S+)")
    x, y, z = tonumber(x), tonumber(y), tonumber(z)
    return x and y and z and { x, y, z } or nil
end






local function scaleSection(player, factor)
    local ModData, FH = MGE.ModData, MGE.FileHandler
    local lines = FH.getPlayerLines(ModData.parsed, player) or FH.getSharedPlayerLines(ModData.parsed) or {}
    local section = parseSection(lines)
    local byKey = {}
    for _, part in ipairs(section.parts) do byKey[part.kind .. ":" .. part.name] = part end

    local function partFor(kind, name)
        local key = kind .. ":" .. name
        if not byKey[key] then
            byKey[key] = { kind = kind, name = name, props = {} }
            table.insert(section.parts, byKey[key])
        end
        return byKey[key]
    end



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



local DEFAULT_DENSITY = 0.25
local DEFAULT_STRENGTH = {
    neck = 1, chest = 4, lumbar = 3, abs = 3, r_pecs = 3, r_shoulder = 4, r_elbow = 2, l_pecs = 3,
    l_shoulder = 4, l_elbow = 2, r_wrist = 2, l_wrist = 2, r_glute = 4, l_glute = 4, r_hip = 2, l_hip = 2,
    r_knee = 4, l_knee = 4, r_ankle = 1, l_ankle = 1,
}

local PART_KEYS = {
    density = { body = true, default = function() return DEFAULT_DENSITY end },
    strength = { joint = true, default = function(name) return DEFAULT_STRENGTH[name] or 1 end },
    friction = { body = true, joint = true, default = function() return 0.3 end },
    bounce = { body = true, joint = true, default = function() return 0.1 end },
}







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


local function playerSection(player)
    local ModData, FH = MGE.ModData, MGE.FileHandler
    return parseSection(FH.getPlayerLines(ModData.parsed, player) or FH.getSharedPlayerLines(ModData.parsed) or {})
end






function Players.partAverage(player, key)
    local sum, n = 0, 0
    eachPart(playerSection(player), key, false, function(_, value)
        sum, n = sum + value, n + 1
    end)
    return n > 0 and sum / n or 0
end


local DEFAULT_HEAD, DEFAULT_GROIN = { 1, 0.85, 2.65 }, { 1, 1, 1.55 }


local function distance(a, b)
    local x, y, z = a[1] - b[1], a[2] - b[2], a[3] - b[3]
    return math.sqrt(x * x + y * y + z * z)
end






function Players.size(player)
    local head, groin
    for _, part in ipairs(playerSection(player).parts) do
        if part.kind == "body" and part.name == "head" then head = readVec(getProp(part, "pos")) end
        if part.kind == "body" and part.name == "groin" then groin = readVec(getProp(part, "pos")) end
    end
    return distance(head or DEFAULT_HEAD, groin or DEFAULT_GROIN) / distance(DEFAULT_HEAD, DEFAULT_GROIN)
end




function Players.groupSize(players)
    local list, sum = asList(players), 0
    for _, player in ipairs(list) do sum = sum + Players.size(player) end
    return #list > 0 and sum / #list or 1
end




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
    MGE.apply()
end






function Players.multiplyParts(players, key, factor)
    local list = asList(players)
    if #list == 0 or factor < 0 or math.abs(factor - 1) < 1e-9 then return end
    changeParts(list, key, function(value) return value * factor end)
end





function Players.setParts(players, key, value)
    local list = asList(players)
    if #list == 0 then return end
    changeParts(list, key, function() return value end)
end





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







function Players.scaleBy(players, factor, pivot)
    local list = asList(players)
    if #list == 0 or factor <= 0 or math.abs(factor - 1) < 1e-9 then return end
    MGE.Camera.followPlayer(list, { factor = factor, pivot = pivot or Players.groupCenter(list) })
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
            commit(correctedPositions(targets), rot)
        end)
    end)
end



Players.MAX = 4
local NUMPLAYERS = "numplayers"
local DUPLICATE_GAP = 0.3


local function haveRoom(n)
    if Players.count() + n <= Players.MAX then return true end
    MGE.say("a mod can have at most " .. Players.MAX .. " players")
    return false
end



local function groupBounds(list)
    local lo, hi = { math.huge, math.huge, math.huge }, { -math.huge, -math.huge, -math.huge }
    for _, player in ipairs(list) do
        local b = Players.bounds(player)
        for k = 1, 3 do lo[k], hi[k] = math.min(lo[k], b.min[k]), math.max(hi[k], b.max[k]) end
    end
    return { min = lo, max = hi }
end










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
                local d = MGE.Camera.spawnShift(b, p)
                targets[id] = { c[1] + d[1], c[2] + d[2], c[3] + d[3] }
            end
            if done then done(ids) end


            local now, offset = Players.groupCenter(ids), { 0, 0, 0 }
            for _, id in ipairs(ids) do
                for k = 1, 3 do offset[k] = offset[k] + targets[id][k] / #ids end
            end
            for k = 1, 3 do offset[k] = offset[k] - now[k] end
            MGE.Camera.followPlayer(ids, { offset = offset })
            commit(correctedPositions(targets), readList(ROT) or {})
        end)
    end)
end




function Players.addNew(point, done)
    addPlayers({ false }, { 0, 0, 0 }, point, done)
end




function Players.duplicate(players, done)
    local list = asList(players)
    if #list == 0 then return end
    local b = groupBounds(list)
    addPlayers(list, { b.max[1] - b.min[1] + DUPLICATE_GAP, 0, 0 }, nil, done)
end






function Players.remove(players, done)
    local removed = {}
    for _, p in ipairs(asList(players)) do
        if p >= 0 and p < Players.count() then removed[p] = true end
    end
    local n = 0
    for _ in pairs(removed) do n = n + 1 end
    if n == 0 then return end
    if n >= Players.count() then
        MGE.say("a mod needs at least one player")
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

        MGE.FileHandler.renumberPlayers(MGE.ModData.parsed, map)
        set_gamerule(NUMPLAYERS, tostring(kept))
        if done then done(map) end
        commit(newPos, newRot, kept)
    end)
end








function Players.target(players)
    if pending then return nil end
    local list = {}
    for _, player in ipairs(asList(players)) do
        if Players.exists(player) then table.insert(list, player) end
    end
    if #list == 0 then return nil end
    local snaps, pivot = nil, Players.groupCenter(list)

    local t = { players = list, scalable = true, uniformScaleOnly = true }
    function t.pivot() return pivot end
    function t.frame() return Mat3.IDENTITY end
    function t.begin()
        snaps = {}
        for _, player in ipairs(list) do snaps[player] = Players.snapshot(player) end
    end


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
