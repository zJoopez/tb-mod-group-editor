







local Transforms = {}
MGE.Transforms = Transforms

local RotatingOld = dofile(MGE.scriptPath .. "utils/rotating.lua")
local ModData = MGE.ModData
local History = MGE.History
local Joints = MGE.Joints
local Mat3 = MGE.Mat3
local FileHandler = MGE.FileHandler
local SHAPE = MGE.SHAPE
local POS_ORIGIN = MGE.POS_ORIGIN


local pickGroupFrame


Transforms.onChanged = function() end






Transforms.fileAngles = true

local function angleSign() return Transforms.fileAngles and -1 or 1 end







local function inWorld(obj)
    if obj.kind == "atmo" then return false end
    return get_obj_pos(obj.id - 1) ~= nil
end



local function present(obj)
    return obj.kind == "atmo" or inWorld(obj)
end




local function positionOf(obj)


    if obj.kind == "atmo" and MGE.AtmoLayer then
        local g = MGE.AtmoLayer.ghost(obj)
        if g and g.pos[3] then return { g.pos[1], g.pos[2], g.pos[3] } end
        if not g then return { 0, 0, 0 } end
    end
    local x, y, z = (obj.props.pos or ""):match("(%S+)%s+(%S+)%s+(%S+)")
    x, y, z = tonumber(x), tonumber(y), tonumber(z)
    if x and y and z then return { x, y, z } end
    if obj.kind == "atmo" then return { 0, 0, 0 } end
    return { get_obj_pos(obj.id - 1) }
end




local function sidesOf(obj)
    if obj.kind == "atmo" then

        local g = MGE.AtmoLayer and MGE.AtmoLayer.ghost(obj)
        if g then
            local s = g.fileSides
            return s[1] or 1, s[2] or 1, s[3] or 1
        end
        local s = {}
        for n in tostring(obj.props.sides or ""):gmatch("%S+") do s[#s + 1] = tonumber(n) end
        return s[1] or 1, s[2] or 1, s[3] or 1
    end
    return get_obj_sides(obj.id - 1)
end




local function shapeIdOf(obj)
    if obj.kind == "atmo" then
        local name = tostring(obj.props.shape or "box"):match("^%s*(%a+)") or "box"
        if name == "sphere" then return SHAPE.SPHERE end
        if name == "cylinder" or name == "capsule" then return SHAPE.CAPSULE end
        return SHAPE.BOX
    end
    return get_obj_shape(obj.id - 1)
end




local function worldOnly(objects)
    local out = {}
    for _, obj in ipairs(objects) do
        if obj.kind ~= "atmo" then out[#out + 1] = obj end
    end
    return out
end



local function getSelected() return ModData.getEditSelection() end



local function rotLine(obj)
    local x, y, z = (obj.props.rot or ""):match("(%S+)%s+(%S+)%s+(%S+)")
    return { math.rad(tonumber(x) or 0), math.rad(tonumber(y) or 0), math.rad(tonumber(z) or 0) }
end



local function applyFileRotation(obj)
    if not inWorld(obj) then return end
    local r = rotLine(obj)
    set_obj_rot(obj.id - 1, r[1], r[2], r[3])
end











local orientationByRot, orientationCount = {}, 0

local function orientationOf(obj)
    local line = obj.props.rot or ""
    local m = orientationByRot[line]
    if m then return m end
    local r = rotLine(obj)
    local x, y, z = r[1], r[2], r[3]
    m = Mat3.mul(Mat3.rotX(-x), Mat3.mul(Mat3.rotY(-y), Mat3.rotZ(-z)))
    if orientationCount >= 4096 then orientationByRot, orientationCount = {}, 0 end
    orientationByRot[line], orientationCount = m, orientationCount + 1
    return m
end


local function writeVectorProperty(obj, key, values)
    local parts = {}
    for i, v in ipairs(values) do parts[i] = FileHandler.formatNumber(v) end
    obj.props[key] = table.concat(parts, " ")
end






local function finishTransform(selected, posFn, axisFn)
    local linked = Joints.getLinked(Joints.idSet(worldOnly(selected)))
    for _, joint in ipairs(linked) do
        if posFn then Joints.transformPos(joint, posFn) end
        if axisFn then Joints.transformAxis(joint, axisFn) end
    end
    History.commit()
    if #linked > 0 then MGE.apply() end
end



local function getSelectionPivot(selectedObjects)
    local total = #selectedObjects
    if total == 0 then return 0, 0, 0 end

    local sumX, sumY, sumZ, count = 0, 0, 0, 0
    for _, obj in ipairs(selectedObjects) do
        if present(obj) then
            local p = positionOf(obj)
            sumX, sumY, sumZ, count = sumX + p[1], sumY + p[2], sumZ + p[3], count + 1
        end
    end
    if count == 0 then return 0, 0, 0 end

    return sumX / count, sumY / count, sumZ / count
end




local function moveBy(selectedObjects, offsets)
    local function move(x, y, z) return x + offsets[1], y + offsets[2], z + offsets[3] end
    for _, v in ipairs(selectedObjects) do
        local p = positionOf(v)
        local pos = { move(p[1], p[2], p[3]) }
        if inWorld(v) then set_obj_pos(v.id - 1, pos[1], pos[2], pos[3]) end
        applyFileRotation(v)
        writeVectorProperty(v, "pos", pos)
    end



    if MGE.Camera.followMoves then MGE.Camera.focus(selectedObjects) end
    finishTransform(selectedObjects, move)
    Transforms.onChanged()
end





function Transforms.previewMove(selectedObjects, offset)
    for _, v in ipairs(selectedObjects) do
        if inWorld(v) then
            local p = positionOf(v)
            set_obj_pos(v.id - 1, p[1] + offset[1], p[2] + offset[2], p[3] + offset[3])
            applyFileRotation(v)
        end
    end
end




function Transforms.restoreLive(selectedObjects, baseSides)
    Transforms.previewMove(selectedObjects, { 0, 0, 0 })
    for _, v in ipairs(selectedObjects) do
        local s = baseSides and baseSides[v.id]
        if s and inWorld(v) then set_obj_sides(v.id - 1, s[1], s[2], s[3]) end
    end
end





function Transforms.liveSides(selectedObjects)
    local out = {}
    for _, v in ipairs(selectedObjects) do
        if inWorld(v) then out[v.id] = { get_obj_sides(v.id - 1) } end
    end
    return out
end




function Transforms.positionTo(typed)
    local selectedObjects = getSelected()
    if #selectedObjects == 0 then return end
    local pivot = { getSelectionPivot(selectedObjects) }
    local offsets = {}
    for i = 1, 3 do offsets[i] = typed[i] and typed[i] + POS_ORIGIN[i] - pivot[i] or 0 end
    moveBy(selectedObjects, offsets)
end




function Transforms.shownPosition(selectedObjects)
    local pivot = { getSelectionPivot(selectedObjects) }
    for i = 1, 3 do pivot[i] = pivot[i] - POS_ORIGIN[i] end
    return pivot
end





local function rotBy(selectedObjects, offsets, pivot)
    pivot = pivot or { getSelectionPivot(selectedObjects) }




    local turn = {}
    for k = 1, 3 do
        local e = { 0, 0, 0 }
        e[k] = 1
        turn[k] = RotatingOld.SetRotPos(e[1], e[2], e[3], 0, 0, 0, offsets[1], offsets[2], offsets[3])
    end
    local rotByLine = {}

    for _, v in ipairs(selectedObjects) do
        local pos = positionOf(v)
        local dx, dy, dz = pos[1] - pivot[1], pos[2] - pivot[2], pos[3] - pivot[3]
        local outPos = {
            pivot[1] + turn[1][1] * dx + turn[2][1] * dy + turn[3][1] * dz,
            pivot[2] + turn[1][2] * dx + turn[2][2] * dy + turn[3][2] * dz,
            pivot[3] + turn[1][3] * dx + turn[2][3] * dy + turn[3][3] * dz,
        }
        local line = v.props.rot or ""
        local outRot = rotByLine[line]
        if not outRot then
            local rot = rotLine(v)
            outRot = RotatingOld.SetRotOffset(rot[1], rot[2], rot[3], offsets[1], offsets[2], offsets[3])
            rotByLine[line] = outRot
        end
        if inWorld(v) then
            set_obj_rot(v.id - 1, math.rad(outRot[1]), math.rad(outRot[2]), math.rad(outRot[3]))
            set_obj_pos(v.id - 1, outPos[1], outPos[2], outPos[3])
        end

        writeVectorProperty(v, "rot", outRot)
        writeVectorProperty(v, "pos", outPos)
    end

    finishTransform(selectedObjects, function(x, y, z)
        local p = RotatingOld.SetRotPos(x, y, z, pivot[1], pivot[2], pivot[3], offsets[1], offsets[2], offsets[3])
        return p[1], p[2], p[3]
    end, function(x, y, z)
        local a = RotatingOld.SetRotPos(x, y, z, 0, 0, 0, offsets[1], offsets[2], offsets[3])
        return a[1], a[2], a[3]
    end)
    Transforms.onChanged()
end





local axesByOrientation = setmetatable({}, { __mode = "k" })

local function getLocalAxes(obj)
    local m = orientationOf(obj)
    local axes = axesByOrientation[m]
    if not axes then
        axes = { { m[1][1], m[2][1], m[3][1] }, { m[1][2], m[2][2], m[3][2] }, { m[1][3], m[2][3], m[3][3] } }
        axesByOrientation[m] = axes
    end
    return axes
end





local function groupScaleMatrix(frame, scale)
    return Mat3.mul(Mat3.mul(frame, { { scale[1], 0, 0 }, { 0, scale[2], 0 }, { 0, 0, scale[3] } }), Mat3.transpose(frame))
end














local scaleSidesAlong

local function scaleSides(obj, sides, frame, scale, shapeName)
    return scaleSidesAlong(getLocalAxes(obj), sides, frame, scale, shapeName or nil, obj)
end

















local function sideFactors(axes, frame, scale)
    local logScale = {}
    for j = 1, 3 do logScale[j] = math.log(math.max(math.abs(scale[j]), 1e-9)) end
    local f = {}
    for i = 1, 3 do
        local a, sum = axes[i], 0
        for j = 1, 3 do
            local along = a[1] * frame[1][j] + a[2] * frame[2][j] + a[3] * frame[3][j]
            sum = sum + along * along * logScale[j]
        end
        f[i] = math.exp(sum)
    end
    return f
end







local function applySideFactors(sides, f, sphere, capsule)
    local out
    if sphere then
        local r = sides[1] * (f[1] * f[2] * f[3]) ^ (1 / 3)
        out = { r, r, r }
    elseif capsule then
        out = { sides[1] * math.sqrt(f[1] * f[2]), sides[2] * f[3], sides[3] }
    else
        out = { sides[1] * f[1], sides[2] * f[2], sides[3] * f[3] }
    end
    for i = 1, 3 do out[i] = math.max(math.abs(out[i]), MGE.MIN_SIDE) end
    return out
end
Transforms.sideFactors = sideFactors
Transforms.applySideFactors = applySideFactors

scaleSidesAlong = function(axes, sides, frame, scale, shapeName, obj)
    local f = sideFactors(axes, frame, scale)
    local sphere, capsule
    if shapeName then
        sphere, capsule = shapeName == "sphere", shapeName == "cylinder"
    else
        local shape = obj and shapeIdOf(obj)
        sphere, capsule = shape == SHAPE.SPHERE, shape == SHAPE.CAPSULE
    end
    return applySideFactors(sides, f, sphere, capsule)
end



local function sameFrame(a, b)
    for i = 1, 3 do
        for j = 1, 3 do
            if math.abs(a[i][j] - b[i][j]) > 1e-4 then return false end
        end
    end
    return true
end








pickGroupFrame = function(objects)

    local byLine, lines = {}, {}
    for _, obj in ipairs(objects) do
        local line = obj.props.rot or ""
        local entry = byLine[line]
        if entry then
            entry.weight = entry.weight + 1
        else
            entry = { obj = obj, weight = 1 }
            byLine[line] = entry
            lines[#lines + 1] = line
        end
    end



    local groups, byKey = {}, {}
    for _, line in ipairs(lines) do
        local entry = byLine[line]
        local frame = orientationOf(entry.obj)
        local key = string.format("%d %d %d %d %d %d %d %d %d",
            math.floor(frame[1][1] * 1000 + 0.5), math.floor(frame[1][2] * 1000 + 0.5), math.floor(frame[1][3] * 1000 + 0.5),
            math.floor(frame[2][1] * 1000 + 0.5), math.floor(frame[2][2] * 1000 + 0.5), math.floor(frame[2][3] * 1000 + 0.5),
            math.floor(frame[3][1] * 1000 + 0.5), math.floor(frame[3][2] * 1000 + 0.5), math.floor(frame[3][3] * 1000 + 0.5))
        local group
        for _, g in ipairs(byKey[key] or {}) do
            if sameFrame(g.frame, frame) then group = g break end
        end
        if group then
            group.weight = group.weight + entry.weight
        else
            group = { frame = frame, weight = entry.weight }
            groups[#groups + 1] = group
            byKey[key] = byKey[key] or {}
            table.insert(byKey[key], group)
        end
    end
    local best = groups[1]
    for _, g in ipairs(groups) do
        if g.weight > best.weight then best = g end
    end
    return best and best.frame or Mat3.IDENTITY
end






local function rotationTo(frame, target)
    local wanted = Mat3.mul(Mat3.rotX(target[1]), Mat3.mul(Mat3.rotY(target[2]), Mat3.rotZ(target[3])))

    return { Mat3.toEulerXYZ(Mat3.mul(wanted, Mat3.transpose(frame))) }
end









local function planScale(selectedObjects, scale, pivot, frame)
    pivot = pivot or { getSelectionPivot(selectedObjects) }


    frame = frame or pickGroupFrame(selectedObjects)
    local map = groupScaleMatrix(frame, scale)
    local function scalePos(x, y, z)
        local rel = Mat3.apply(map, { x - pivot[1], y - pivot[2], z - pivot[3] })
        return pivot[1] + rel[1], pivot[2] + rel[2], pivot[3] + rel[3]
    end


    local factorsByLine = {}
    local function scaleSidesCached(v, sides)
        local line = v.props.rot or ""
        local f = factorsByLine[line]
        if not f then
            f = Transforms.sideFactors(getLocalAxes(v), frame, scale)
            factorsByLine[line] = f
        end
        local shape = shapeIdOf(v)
        return Transforms.applySideFactors(sides, f, shape == SHAPE.SPHERE, shape == SHAPE.CAPSULE)
    end

    local planned = {}
    for _, v in ipairs(selectedObjects) do
        if present(v) then
            local p = positionOf(v)
            table.insert(planned, {
                obj = v,
                pos = { scalePos(p[1], p[2], p[3]) },
                sides = scaleSidesCached(v, { sidesOf(v) }),
            })
        end
    end
    return planned, scalePos
end






local function scaleBy(selectedObjects, scale, pivot, frame)
    local planned, scalePos = planScale(selectedObjects, scale, pivot, frame)
    for _, p in ipairs(planned) do
        local id = p.obj.id - 1
        if inWorld(p.obj) then
            set_obj_pos(id, p.pos[1], p.pos[2], p.pos[3])
            set_obj_sides(id, p.sides[1], p.sides[2], p.sides[3])
        end
        applyFileRotation(p.obj)
        writeVectorProperty(p.obj, "pos", p.pos)
        writeVectorProperty(p.obj, "sides", p.sides)
    end

    if MGE.Camera.followMoves then MGE.Camera.focus(selectedObjects) end
    finishTransform(selectedObjects, scalePos)
    Transforms.onChanged()
end




local function frameAxes(frame)
    return {
        { frame[1][1], frame[2][1], frame[3][1] },
        { frame[1][2], frame[2][2], frame[3][2] },
        { frame[1][3], frame[2][3], frame[3][3] },
    }
end






local function groupBounds(selectedObjects, axes, scale)
    local placed = {}
    if scale then
        for _, p in ipairs((planScale(selectedObjects, scale))) do placed[p.obj] = p end
    end
    local min, max = { math.huge, math.huge, math.huge }, { -math.huge, -math.huge, -math.huge }
    for _, v in ipairs(selectedObjects) do
        local x, y, z
        local sx, sy, sz
        if present(v) then
            local pos = positionOf(v)
            x, y, z = pos[1], pos[2], pos[3]
            sx, sy, sz = sidesOf(v)
        end
        local p = placed[v]
        if p then
            x, y, z = p.pos[1], p.pos[2], p.pos[3]
            sx, sy, sz = p.sides[1], p.sides[2], p.sides[3]
        end
        if x then
            local shape = shapeIdOf(v)
            local localAxes = getLocalAxes(v)
            local l1, l2, l3 = localAxes[1], localAxes[2], localAxes[3]
            for i, a in ipairs(axes) do

                local a1, a2, a3 = a[1], a[2], a[3]
                local along3 = math.abs(l3[1] * a1 + l3[2] * a2 + l3[3] * a3)
                local half
                if shape == SHAPE.SPHERE then
                    half = sx
                elseif shape == SHAPE.CAPSULE then
                    half = sx + along3 * sy / 2
                else
                    local along1 = math.abs(l1[1] * a1 + l1[2] * a2 + l1[3] * a3)
                    local along2 = math.abs(l2[1] * a1 + l2[2] * a2 + l2[3] * a3)
                    half = (along1 * sx + along2 * sy + along3 * sz) / 2
                end
                local c = x * a[1] + y * a[2] + z * a[3]
                min[i] = math.min(min[i], c - half)
                max[i] = math.max(max[i], c + half)
            end
        end
    end
    return min, max
end






local function groupExtents(selectedObjects, scale)
    local min, max = groupBounds(selectedObjects, frameAxes(pickGroupFrame(selectedObjects)), scale)
    local extents = {}
    for i = 1, 3 do extents[i] = max[i] > min[i] and max[i] - min[i] or 0 end
    return extents
end









function Transforms.sizeTo(typed)
    local selectedObjects = getSelected()
    if #selectedObjects == 0 then return end
    local current = groupExtents(selectedObjects)
    local targets, changed = {}, false
    for i = 1, 3 do
        if typed[i] and typed[i] > 0 and current[i] > 1e-9 then
            targets[i], changed = typed[i], true
        end
    end
    if not changed then return end


    local scale = { 1, 1, 1 }

    local previous = {}
    for _ = 1, 50 do
        local extents = groupExtents(selectedObjects, scale)
        local done = true
        for i = 1, 3 do
            if targets[i] and extents[i] > 1e-9 then
                local logScale, logSize = math.log(scale[i]), math.log(extents[i])
                local miss = math.log(targets[i]) - logSize
                if math.abs(miss) > 1e-10 then
                    done = false


                    local response = 1
                    local p = previous[i]
                    if p and math.abs(logScale - p.scale) > 1e-12 then
                        response = math.min(math.max((logSize - p.size) / (logScale - p.scale), 0.05), 2)
                    end
                    previous[i] = { scale = logScale, size = logSize }
                    scale[i] = math.min(math.max(math.exp(logScale + miss / response), 1e-4), 1e4)
                end
            end
        end
        if done then break end
    end
    scaleBy(selectedObjects, scale)
end




function Transforms.groupAngles(selectedObjects)
    local sign = angleSign()
    local x, y, z = Mat3.toEulerXYZ(pickGroupFrame(selectedObjects))
    return { sign * x, sign * y, sign * z }
end




function Transforms.angleTo(typed)
    local selectedObjects = getSelected()
    if #selectedObjects == 0 then return end
    local frame = pickGroupFrame(selectedObjects)
    local target = Transforms.groupAngles(selectedObjects)
    local changed = false
    for i = 1, 3 do
        if typed[i] then target[i], changed = math.rad(typed[i]), true end
    end
    if not changed then return end
    local sign = angleSign()
    rotBy(selectedObjects, rotationTo(frame, { sign * target[1], sign * target[2], sign * target[3] }))
end



Transforms.writeVector = writeVectorProperty
Transforms.getSelectionPivot = getSelectionPivot
Transforms.positionOf = positionOf
Transforms.moveBy = moveBy
Transforms.groupFrame = function(selectedObjects) return pickGroupFrame(selectedObjects) end






local function inWorldOnly(objects)
    local out = {}
    for _, v in ipairs(objects) do
        if inWorld(v) then out[#out + 1] = v end
    end
    return out
end






function Transforms.previewRotate(selectedObjects, rotation, pivot)
    local world = inWorldOnly(selectedObjects)
    if #world == 0 then return end
    pivot = pivot or { getSelectionPivot(selectedObjects) }
    for _, v in ipairs(world) do
        if inWorld(v) then
            local p = positionOf(v)
            local rel = Mat3.apply(rotation, { p[1] - pivot[1], p[2] - pivot[2], p[3] - pivot[3] })
            set_obj_pos(v.id - 1, pivot[1] + rel[1], pivot[2] + rel[2], pivot[3] + rel[3])

            local x, y, z = Mat3.toEulerXYZ(Mat3.mul(rotation, orientationOf(v)))
            set_obj_rot(v.id - 1, -x, -y, -z)
        end
    end
end






function Transforms.rotateByMatrix(selectedObjects, rotation, pivot)
    rotBy(selectedObjects, { Mat3.toEulerXYZ(rotation) }, pivot)
end









function Transforms.previewScale(selectedObjects, scale, baseSides, pivot, frame)
    local world = inWorldOnly(selectedObjects)
    if #world == 0 then return end

    pivot = pivot or { getSelectionPivot(selectedObjects) }
    frame = frame or pickGroupFrame(selectedObjects)
    for _, v in ipairs(world) do
        local s = baseSides[v.id]
        if s then set_obj_sides(v.id - 1, s[1], s[2], s[3]) end
    end
    for _, p in ipairs((planScale(world, scale, pivot, frame))) do
        if inWorld(p.obj) then
            local id = p.obj.id - 1
            set_obj_pos(id, p.pos[1], p.pos[2], p.pos[3])
            set_obj_sides(id, p.sides[1], p.sides[2], p.sides[3])
            applyFileRotation(p.obj)
        end
    end
end
Transforms.orientationOf = orientationOf
Transforms.scaleSidesFor = scaleSides
Transforms.scaleSidesAlong = function(...) return scaleSidesAlong(...) end
Transforms.groupExtents = groupExtents
Transforms.rotBy = rotBy
Transforms.scaleBy = scaleBy

return Transforms
