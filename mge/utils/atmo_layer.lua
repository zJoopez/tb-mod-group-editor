













local ModData = MGE.ModData
local History = MGE.History
local Mat3 = MGE.Mat3
local FileHandler = MGE.FileHandler


local AtmoLayer = {
    color = { 0.75, 0.45, 1.0 },
    alpha = 0.15,




    maxAtmo = 256,

    seeThroughAlpha = 0.15,


    live = nil,
}
MGE.AtmoLayer = AtmoLayer



local function numbers(value)

    local text = tostring(value or "")
    local a, b, c, rest = text:match("^%s*(%S+)%s+(%S+)%s+(%S+)%s*(.*)$")
    if a and rest == "" then return { tonumber(a) or 0, tonumber(b) or 0, tonumber(c) or 0 } end
    local out = {}
    for n in text:gmatch("%S+") do out[#out + 1] = tonumber(n) or 0 end
    return out
end



local function shapeOf(obj)
    local shape = tostring(obj.props.shape or "box"):match("^%s*(%a+)") or "box"
    if shape == "sphere" or shape == "cylinder" or shape == "capsule" then
        return shape == "capsule" and "cylinder" or shape
    end
    return "box"
end
AtmoLayer.shapeOf = shapeOf







function AtmoLayer.frameOf(rot)
    local r = math.rad
    return Mat3.mul(Mat3.mul(Mat3.rotX(-r(rot[1] or 0)), Mat3.rotY(-r(rot[2] or 0))), Mat3.rotZ(-r(rot[3] or 0)))
end














local frameByRot = {}




function AtmoLayer.ghost(obj)
    local p = obj.props
    if not p.pos then return nil end


    local cached = obj.ghostCache
    if cached and cached.pos == p.pos and cached.rot == p.rot and cached.sides == p.sides and cached.shape == p.shape then
        return cached.ghost
    end
    local fileSides = numbers(p.sides)
    local sides = {}
    for k = 1, 3 do sides[k] = math.max(math.abs(fileSides[k] or 0), 0.01) end
    local shape = shapeOf(obj)
    local radius = shape == "sphere" and sides[1] or shape == "cylinder" and sides[2] / 2 + sides[1]
        or math.sqrt(sides[1] ^ 2 + sides[2] ^ 2 + sides[3] ^ 2) / 2
    local rotLine = p.rot or ""
    local frame = frameByRot[rotLine]
    if not frame then
        frame = AtmoLayer.frameOf(numbers(p.rot))
        frameByRot[rotLine] = frame
    end
    local ghost = { shape = shape, pos = numbers(p.pos), frame = frame, sides = sides, radius = radius,
        fileSides = fileSides }
    obj.ghostCache = { pos = p.pos, rot = p.rot, sides = p.sides, shape = p.shape, ghost = ghost }
    return ghost
end




local function writeMissingLines(obj)
    local id = obj.id - 1
    if obj.props.flag == nil then
        local flag = get_obj_flag(id)
        obj.props.flag = tostring(flag or MGE.FLAGS.STATIC)
    end
    if obj.props.color == nil then
        local ok, r, g, b, a = pcall(get_obj_color, id)
        if ok and type(r) == "table" then r, g, b, a = r[1], r[2], r[3], r[4] end
        if ok and tonumber(r) then obj.props.color = FileHandler.formatNumbers(r, g, b, a or 1) end
    end
end



function AtmoLayer.moveIn()
    local selected = ModData.getSelected()
    if #selected == 0 then
        MGE.say("select the objects to move to the atmo first")
        return
    end
    ModData.refreshJointIds()
    local moved, joined = {}, 0
    for i = #ModData.parsed.env_obj, 1, -1 do
        local obj = ModData.parsed.env_obj[i]
        if obj.selected then
            if ModData.jointIds[obj.id] then
                joined = joined + 1
            else
                writeMissingLines(obj)
                MGE.Atmo.fromMod(obj)
                obj.kind = "atmo"
                table.remove(ModData.parsed.env_obj, i)
                ModData.releaseId(obj.id)
                table.insert(moved, 1, obj)
            end
        end
    end
    if joined > 0 then
        MGE.say("" .. joined .. " objects joined by joints stay in the game, remove their joints to move them")
    end
    if #moved == 0 then return end
    for _, obj in ipairs(moved) do
        table.insert(ModData.parsed.atmo, obj)
        obj.id = #ModData.parsed.atmo
    end
    MGE.say("moved " .. #moved .. " objects to the atmo (" .. #ModData.parsed.atmo .. " atmo objects in all)")
    History.commit()
    MGE.apply()
end



function AtmoLayer.moveOut()
    local list = ModData.getSelectedAtmo()
    if #list == 0 then
        MGE.say("select atmo objects (the Atmo list) to move back first")
        return
    end
    local free = ModData.freeCount()
    local count = math.min(#list, free)
    if count == 0 then
        MGE.say("no free object ids (" .. MGE.MAX_ENV_OBJECTS .. " in the game): move or delete objects first")
        return
    end
    local plans = {}
    for i = 1, count do plans[i] = { pool = ModData.idPool(list[i], false, {}), linked = false } end
    local ids = ModData.allocateIds(plans)
    if not ids then return end
    local back = {}
    for i = 1, count do
        back[list[i]] = true
        list[i].id, list[i].kind = ids[i], "env_obj"
        table.insert(ModData.parsed.env_obj, list[i])
    end
    local stay = {}
    for _, obj in ipairs(ModData.parsed.atmo) do
        if not back[obj] then
            stay[#stay + 1] = obj
            obj.id = #stay
        end
    end
    ModData.parsed.atmo = stay
    ModData.sortObjects()
    MGE.say("moved " .. count .. " atmo objects back to objects" ..
        (count < #list and (", " .. (#list - count) .. " stay in the atmo: no more free ids") or ""))
    History.commit()
    MGE.apply()
end


function AtmoLayer.toAtmo()
    local before = #ModData.parsed.atmo
    AtmoLayer.moveIn()
    if #ModData.parsed.atmo > before and MGE.Main then MGE.Main.setListTab("atmo") end
end


function AtmoLayer.toObjects()
    local before = #ModData.parsed.atmo
    AtmoLayer.moveOut()
    if #ModData.parsed.atmo < before and MGE.Main then MGE.Main.setListTab("objects") end
end


function AtmoLayer.room()
    return math.max(0, AtmoLayer.maxAtmo - #ModData.parsed.atmo)
end




function AtmoLayer.add(objects)
    for _, obj in ipairs(objects) do
        obj.kind, obj.selected = "atmo", true
        MGE.Atmo.fromMod(obj)
        table.insert(ModData.parsed.atmo, obj)
        obj.id = #ModData.parsed.atmo
    end
end








function AtmoLayer.unloadGameAtmo()
    if rawget(_G, "_ATMO") == nil then return false end
    local manager = rawget(_G, "Atmospheres")
    if type(manager) ~= "table" or type(manager.Unload) ~= "function" then return false end
    local ok = pcall(manager.Unload)
    if ok then MGE.say("unloaded the game's atmo: MGE draws the atmo it edits itself") end
    return ok
end



function AtmoLayer.removeSelected()
    local stay = {}
    for _, obj in ipairs(ModData.parsed.atmo) do
        if not obj.selected then
            stay[#stay + 1] = obj
            obj.id = #stay
        end
    end
    local removed = #ModData.parsed.atmo - #stay
    ModData.parsed.atmo = stay
    return removed
end




function AtmoLayer.isAtmo(obj)
    return obj.kind == "atmo"
end




local function posOf(obj)
    local p = numbers(obj.props.pos)
    return { p[1] or 0, p[2] or 0, p[3] or 0 }
end
AtmoLayer.posOf = posOf




function AtmoLayer.center(list)
    local c = { 0, 0, 0 }
    for _, obj in ipairs(list) do
        local p = posOf(obj)
        for k = 1, 3 do c[k] = c[k] + p[k] / #list end
    end
    return c
end






function AtmoLayer.moveBy(list, offset, props)
    for _, obj in ipairs(list) do
        local target = props and props[obj] or obj
        local p = numbers(target.props.pos)
        MGE.Transforms.writeVector(target, "pos", { (p[1] or 0) + offset[1], (p[2] or 0) + offset[2], (p[3] or 0) + offset[3] })
    end
end

local RotatingOld = dofile(MGE.scriptPath .. "utils/rotating.lua")








function AtmoLayer.rotateBy(list, rotation, pivot, props)
    local ox, oy, oz = Mat3.toEulerXYZ(rotation)
    for _, obj in ipairs(list) do
        local target = props and props[obj] or obj
        local pos, rot = numbers(target.props.pos), numbers(target.props.rot)
        local r = math.rad
        local outPos = RotatingOld.SetRotPos(pos[1] or 0, pos[2] or 0, pos[3] or 0, pivot[1], pivot[2], pivot[3], ox, oy, oz)
        local outRot = RotatingOld.SetRotOffset(r(rot[1] or 0), r(rot[2] or 0), r(rot[3] or 0), ox, oy, oz)
        MGE.Transforms.writeVector(target, "rot", outRot)
        MGE.Transforms.writeVector(target, "pos", outPos)
    end
end









function AtmoLayer.scaleBy(list, factors, pivot, frame, props)
    local T = MGE.Transforms
    local map = Mat3.mul(Mat3.mul(frame, { { factors[1], 0, 0 }, { 0, factors[2], 0 }, { 0, 0, factors[3] } }), Mat3.transpose(frame))
    for _, obj in ipairs(list) do
        local target = props and props[obj] or obj
        local p = numbers(target.props.pos)
        local rel = Mat3.apply(map, { (p[1] or 0) - pivot[1], (p[2] or 0) - pivot[2], (p[3] or 0) - pivot[3] })
        local s = numbers(target.props.sides)
        local sides = T.scaleSidesFor(target, { s[1] or 1, s[2] or 1, s[3] or 1 }, frame, factors, shapeOf(target))
        T.writeVector(target, "pos", { pivot[1] + rel[1], pivot[2] + rel[2], pivot[3] + rel[3] })
        T.writeVector(target, "sides", sides)
    end
end










function AtmoLayer.liveGhost(g, live)

    local x, y, z = g.pos[1], g.pos[2], g.pos[3]
    local frame, sides, radius = g.frame, g.sides, g.radius
    if live.move then
        local m = live.move
        x, y, z = x + m[1], y + m[2], z + m[3]
    end
    if live.rotation then
        local c, r = live.pivot, live.rotation
        local dx, dy, dz = x - c[1], y - c[2], z - c[3]
        x = c[1] + r[1][1] * dx + r[1][2] * dy + r[1][3] * dz
        y = c[2] + r[2][1] * dx + r[2][2] * dy + r[2][3] * dz
        z = c[3] + r[3][1] * dx + r[3][2] * dy + r[3][3] * dz

        live.turned = live.turned or {}
        local turned = live.turned[frame]
        if not turned then
            turned = Mat3.mul(r, frame)
            live.turned[frame] = turned
        end
        frame = turned
    end
    if live.scale then
        local c, gf = live.pivot, live.frame


        local map = live.map
        if not map then
            map = Mat3.mul(Mat3.mul(gf, { { live.scale[1], 0, 0 }, { 0, live.scale[2], 0 }, { 0, 0, live.scale[3] } }),
                Mat3.transpose(gf))
            live.map = map
        end
        local dx, dy, dz = x - c[1], y - c[2], z - c[3]
        x = c[1] + map[1][1] * dx + map[1][2] * dy + map[1][3] * dz
        y = c[2] + map[2][1] * dx + map[2][2] * dy + map[2][3] * dz
        z = c[3] + map[3][1] * dx + map[3][2] * dy + map[3][3] * dz
        live.factorsBy = live.factorsBy or {}
        local f = live.factorsBy[frame]
        if not f then
            local axes = { { frame[1][1], frame[2][1], frame[3][1] }, { frame[1][2], frame[2][2], frame[3][2] },
                { frame[1][3], frame[2][3], frame[3][3] } }
            f = MGE.Transforms.sideFactors(axes, gf, live.scale)
            live.factorsBy[frame] = f
        end
        sides = MGE.Transforms.applySideFactors(sides, f, g.shape == "sphere", g.shape == "cylinder")
        radius = g.shape == "sphere" and sides[1] or g.shape == "cylinder" and sides[2] / 2 + sides[1]
            or math.sqrt(sides[1] ^ 2 + sides[2] ^ 2 + sides[3] ^ 2) / 2
    end

    return { shape = g.shape, pos = { x, y, z }, frame = frame, sides = sides, radius = radius }
end




function AtmoLayer.liveCopies()
    local live = AtmoLayer.live
    if not live then return nil end
    local list, copies = {}, {}
    for _, obj in ipairs(ModData.getSelectedAtmo()) do
        list[#list + 1] = obj
        copies[obj] = { kind = obj.kind, id = obj.id, props = ModData.copy(obj.props), selected = true }
    end
    if live.move then AtmoLayer.moveBy(list, live.move, copies) end
    if live.rotation then AtmoLayer.rotateBy(list, live.rotation, live.pivot, copies) end
    if live.scale then AtmoLayer.scaleBy(list, live.scale, live.pivot, live.frame, copies) end
    return copies
end


local seeThrough = nil





function AtmoLayer.setObjectsSeeThrough(on)
    if on then
        if seeThrough then return end
        seeThrough = {}
        for _, obj in ipairs(ModData.parsed.env_obj) do
            local id = obj.id - 1
            if get_obj_pos(id) ~= nil then
                local ok, r, g, b, a = pcall(get_obj_color, id)
                if ok and type(r) == "table" then r, g, b, a = r[1], r[2], r[3], r[4] end
                if ok and tonumber(r) then
                    seeThrough[id] = { r, g, b, a or 1 }
                    pcall(set_obj_color, id, r, g, b, math.min(a or 1, AtmoLayer.seeThroughAlpha))
                end
            end
        end
    elseif seeThrough then
        for id, c in pairs(seeThrough) do
            if get_obj_pos(id) ~= nil then pcall(set_obj_color, id, c[1], c[2], c[3], c[4]) end
        end
        seeThrough = nil
    end
end


function AtmoLayer.reapplySeeThrough()
    if not seeThrough then return end
    seeThrough = nil
    AtmoLayer.setObjectsSeeThrough(true)
end

table.insert(MGE.onQuit, function() AtmoLayer.setObjectsSeeThrough(false) end)



function AtmoLayer.exportAtmo()
    if not MGE.sourcePath then
        MGE.say("save the mod first: its atmo is named after it")
        return
    end
    if #ModData.parsed.atmo == 0 then
        MGE.say("the atmo is empty: To atmo (Objects > Advanced) or New add to it")
        return
    end
    if not MGE.Atmo.hasChanges() then
        MGE.say("data/atmospheres/" .. tostring(MGE.Atmo.fileName(MGE.sourcePath)) .. " is up to date")
        return
    end
    MGE.Atmo.saveFor(MGE.sourcePath)
end

return AtmoLayer
