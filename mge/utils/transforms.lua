-- Move, rotate and scale for the selected objects: the math behind the editor's Pos/Move, Rot/Rotate and
-- Scale/Resize rows (ui/editor_core.lua). Live changes go to the game (set_obj_*) and the
-- mod data, then History.commit. Transforms.onChanged is called after each change (the editor
-- refreshes the measured rows), tests can leave it as is.
-- Positions and orientations are read from the mod data (pos and rot lines), not from the live world:
-- once the game runs, dynamic objects fall and tumble, and edits should start from where the file has
-- them. The live world only tells which objects exist (objects not in the world yet don't count).

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

-- defined further down, used by functions above them
local pickGroupFrame

---Called after every change, set by the editor to refresh the rows showing current values
Transforms.onChanged = function() end

-- Angle convention of the Rot and Rotate rows.
--   true:  the numbers are the rot line's, Rot shows what the file says and Rotate z 30 from 0 writes
--          "0 0 30". Positive angles turn clockwise when looking down the axis (the game's way).
--   false: standard right-handed angles, positive turns counterclockwise. Rotate z 30 shows Rot z 30
--          but writes "0 0 -30", and an object saved as "0 0 45" shows Rot z -45.
Transforms.fileAngles = true
---@return number 1 or -1, multiplies the typed / shown angles into the math's right-handed ones
local function angleSign() return Transforms.fileAngles and -1 or 1 end

-- Atmo objects (kind "atmo", utils/atmo_layer.lua, utils/atmo.lua) go through the same functions: they're
-- never in the world, everything about them comes from and goes to their lines. Their id is their place
-- in the atmo list, never handed to get_obj_* / set_obj_* (it's another object's id there)

---@param obj FileParserEnvObj
---@return boolean the object exists in the world (never an atmo object)
local function inWorld(obj)
    if obj.kind == "atmo" then return false end
    return get_obj_pos(obj.id - 1) ~= nil
end

---@param obj FileParserEnvObj
---@return boolean the object has a place to work on: in the world, or an atmo object (its lines)
local function present(obj)
    return obj.kind == "atmo" or inWorld(obj)
end

---Position from the pos line, the live position for objects without one (atmo objects: 0 0 0)
---@param obj FileParserEnvObj
---@return number[]
local function positionOf(obj)
    local x, y, z = (obj.props.pos or ""):match("(%S+)%s+(%S+)%s+(%S+)")
    x, y, z = tonumber(x), tonumber(y), tonumber(z)
    if x and y and z then return { x, y, z } end
    if obj.kind == "atmo" then return { 0, 0, 0 } end
    return { get_obj_pos(obj.id - 1) }
end

---Sides: the game's live ones, an atmo object's sides line
---@param obj FileParserEnvObj
---@return number, number, number
local function sidesOf(obj)
    if obj.kind == "atmo" then
        local s = {}
        for n in tostring(obj.props.sides or ""):gmatch("%S+") do s[#s + 1] = tonumber(n) end
        return s[1] or 1, s[2] or 1, s[3] or 1
    end
    return get_obj_sides(obj.id - 1)
end

---Shape (MGE.SHAPE): the game's, an atmo object's shape line
---@param obj FileParserEnvObj
---@return integer
local function shapeIdOf(obj)
    if obj.kind == "atmo" then
        local name = tostring(obj.props.shape or "box"):match("^%s*(%a+)") or "box"
        if name == "sphere" then return SHAPE.SPHERE end
        if name == "cylinder" or name == "capsule" then return SHAPE.CAPSULE end
        return SHAPE.BOX
    end
    return get_obj_shape(obj.id - 1)
end

---The objects that are in the world (atmo objects aren't): what joints and the game's live calls see
---@param objects FileParserEnvObj[]
---@return FileParserEnvObj[]
local function worldOnly(objects)
    local out = {}
    for _, obj in ipairs(objects) do
        if obj.kind ~= "atmo" then out[#out + 1] = obj end
    end
    return out
end

---What the rows work on (ModData.getEditSelection): the selected atmo objects on the Atmo list
---@return FileParserEnvObj[]
local function getSelected() return ModData.getEditSelection() end

---@param obj FileParserEnvObj
---@return number[] the rot line in radians, 0 0 0 without one
local function rotLine(obj)
    local x, y, z = (obj.props.rot or ""):match("(%S+)%s+(%S+)%s+(%S+)")
    return { math.rad(tonumber(x) or 0), math.rad(tonumber(y) or 0), math.rad(tonumber(z) or 0) }
end

---Puts the object's live rotation back to its rot line (after the game tumbled it)
---@param obj FileParserEnvObj
local function applyFileRotation(obj)
    if not inWorld(obj) then return end
    local r = rotLine(obj)
    set_obj_rot(obj.id - 1, r[1], r[2], r[3])
end

---Orientation from the rot line (degrees, no line is 0 0 0), columns are the object's axes in world
---space. The game reads rot x y z as (Rz(z) Ry(y) Rx(x))^T = Rx(-x) Ry(-y) Rz(-z): the convention in
---which rotating.lua's SetRotOffset turns objects the way SetRotPos moves them, and the one get_obj_rot
---matched in game (it gave the same axes as MGE's rotations)
---@param obj FileParserEnvObj
---@return number[][]
local function orientationOf(obj)
    local r = rotLine(obj)
    local x, y, z = r[1], r[2], r[3]
    return Mat3.mul(Mat3.rotX(-x), Mat3.mul(Mat3.rotY(-y), Mat3.rotZ(-z)))
end

---@param values number[]
local function writeVectorProperty(obj, key, values)
    local parts = {}
    for i, v in ipairs(values) do parts[i] = FileHandler.formatNumber(v) end
    obj.props[key] = table.concat(parts, " ")
end

---Applies fn to the anchor (and axis) of joints linked between the selected objects, then commits.
---Joints can't be moved live, so a change with linked joints saves to show them right away.
---@param selected FileParserEnvObj[]
---@param posFn (fun(x: number, y: number, z: number): number, number, number)?
---@param axisFn (fun(x: number, y: number, z: number): number, number, number)?
local function finishTransform(selected, posFn, axisFn)
    local linked = Joints.getLinked(Joints.idSet(worldOnly(selected))) -- atmo ids aren't object ids
    for _, joint in ipairs(linked) do
        if posFn then Joints.transformPos(joint, posFn) end
        if axisFn then Joints.transformAxis(joint, axisFn) end
    end
    History.commit()
    if #linked > 0 then MGE.apply() end
end

---@param selectedObjects FileParserEnvObj[]
---@return number, number, number
local function getSelectionPivot(selectedObjects)
    local total = #selectedObjects
    if total == 0 then return 0, 0, 0 end

    local sumX, sumY, sumZ, count = 0, 0, 0, 0
    for _, obj in ipairs(selectedObjects) do
        if present(obj) then -- objects not in the world (yet) don't count, atmo objects do
            local p = positionOf(obj)
            sumX, sumY, sumZ, count = sumX + p[1], sumY + p[2], sumZ + p[3], count + 1
        end
    end
    if count == 0 then return 0, 0, 0 end

    return sumX / count, sumY / count, sumZ / count
end

---Moves the objects (and joints linked between them) by offsets
---@param selectedObjects FileParserEnvObj[]
---@param offsets number[] x y z
local function moveBy(selectedObjects, offsets)
    local function move(x, y, z) return x + offsets[1], y + offsets[2], z + offsets[3] end
    for _, v in ipairs(selectedObjects) do
        local p = positionOf(v)
        local pos = { move(p[1], p[2], p[3]) }
        if inWorld(v) then set_obj_pos(v.id - 1, pos[1], pos[2], pos[3]) end
        applyFileRotation(v) -- the whole object goes back to the file's state, not only its position
        writeVectorProperty(v, "pos", pos)
    end

    -- camera follows the selection, backing off only if it no longer fits on screen
    -- (can be turned off with the camera button in the top menu)
    if MGE.Camera.followMoves then MGE.Camera.focus(selectedObjects, true) end
    finishTransform(selectedObjects, move)
    Transforms.onChanged()
end

---Live world only, the mod data is untouched: shows the objects moved by offset from where the file
---has them (gizmo drag). moveBy with the same offset makes it real, restoreLive takes it back
---@param selectedObjects FileParserEnvObj[]
---@param offset number[]
function Transforms.previewMove(selectedObjects, offset)
    for _, v in ipairs(selectedObjects) do
        if inWorld(v) then
            local p = positionOf(v)
            set_obj_pos(v.id - 1, p[1] + offset[1], p[2] + offset[2], p[3] + offset[3])
            applyFileRotation(v)
        end
    end
end

---Live world only: puts the objects back where the file has them (cancelled gizmo drag)
---@param selectedObjects FileParserEnvObj[]
---@param baseSides table<integer, number[]>? sizes to put back too (after previewScale), by object id
function Transforms.restoreLive(selectedObjects, baseSides)
    Transforms.previewMove(selectedObjects, { 0, 0, 0 })
    for _, v in ipairs(selectedObjects) do
        local s = baseSides and baseSides[v.id]
        if s and inWorld(v) then set_obj_sides(v.id - 1, s[1], s[2], s[3]) end
    end
end

---Live sizes of the objects, by object id. A scale preview changes them, and scaling reads sizes from
---the world (get_obj_sides), so a gizmo scale drag keeps these to plan every frame from the start
---@param selectedObjects FileParserEnvObj[]
---@return table<integer, number[]>
function Transforms.liveSides(selectedObjects)
    local out = {}
    for _, v in ipairs(selectedObjects) do
        if inWorld(v) then out[v.id] = { get_obj_sides(v.id - 1) } end
    end
    return out
end

---Move row: moves selected objects by the typed offsets
---@param typed (number?)[] x y z, nil axes don't move
function Transforms.move(typed)
    local selectedObjects = getSelected()
    if #selectedObjects == 0 then return end
    moveBy(selectedObjects, { typed[1] or 0, typed[2] or 0, typed[3] or 0 })
end

---Pos row: moves selected objects so their center (same pivot as rotate) lands on the typed
---coordinates, counted from POS_ORIGIN. Axes left empty don't move
---@param typed (number?)[] x y z, nil axes don't move
function Transforms.positionTo(typed)
    local selectedObjects = getSelected()
    if #selectedObjects == 0 then return end
    local pivot = { getSelectionPivot(selectedObjects) }
    local offsets = {}
    for i = 1, 3 do offsets[i] = typed[i] and typed[i] + POS_ORIGIN[i] - pivot[i] or 0 end
    moveBy(selectedObjects, offsets)
end

---Selection center as the Pos row shows it: relative to POS_ORIGIN
---@param selectedObjects FileParserEnvObj[]
---@return number[]
function Transforms.shownPosition(selectedObjects)
    local pivot = { getSelectionPivot(selectedObjects) }
    for i = 1, 3 do pivot[i] = pivot[i] - POS_ORIGIN[i] end
    return pivot
end

---Rotates the objects around their center by offsets (radians, applied z, then y, then x)
---@param selectedObjects FileParserEnvObj[]
---@param offsets number[] x y z
local function rotBy(selectedObjects, offsets)
    local pivot = { getSelectionPivot(selectedObjects) }

    for _, v in ipairs(selectedObjects) do
        local rot = rotLine(v)
        local pos = positionOf(v)

        local outPos = RotatingOld.SetRotPos(
            pos[1], pos[2], pos[3],
            pivot[1], pivot[2], pivot[3],
            offsets[1], offsets[2], offsets[3]
        )
        local outRot = RotatingOld.SetRotOffset(
            rot[1], rot[2], rot[3],
            offsets[1], offsets[2], offsets[3]
        )
        if inWorld(v) then
            set_obj_rot(v.id - 1, math.rad(outRot[1]), math.rad(outRot[2]), math.rad(outRot[3]))
            set_obj_pos(v.id - 1, outPos[1], outPos[2], outPos[3])
        end

        writeVectorProperty(v, "rot", outRot)
        writeVectorProperty(v, "pos", outPos)
    end
    -- anchors rotate around the same pivot, axis directions get the same rotation without translation
    finishTransform(selectedObjects, function(x, y, z)
        local p = RotatingOld.SetRotPos(x, y, z, pivot[1], pivot[2], pivot[3], offsets[1], offsets[2], offsets[3])
        return p[1], p[2], p[3]
    end, function(x, y, z)
        local a = RotatingOld.SetRotPos(x, y, z, 0, 0, 0, offsets[1], offsets[2], offsets[3])
        return a[1], a[2], a[3]
    end)
    Transforms.onChanged()
end

---Rotate row: rotates selected objects by the typed degrees (direction: Transforms.fileAngles)
---@param typed (number?)[] x y z degrees, nil axes don't turn
function Transforms.rotate(typed)
    local selectedObjects = getSelected()
    if #selectedObjects == 0 then return end
    local sign = angleSign()
    rotBy(selectedObjects, { sign * math.rad(typed[1] or 0), sign * math.rad(typed[2] or 0), sign * math.rad(typed[3] or 0) })
end

---World directions of an object's local x, y, z axes (columns of its orientation)
---@param obj FileParserEnvObj
---@return number[][]
local function getLocalAxes(obj)
    local m = orientationOf(obj)
    return { { m[1][1], m[2][1], m[3][1] }, { m[1][2], m[2][2], m[3][2] }, { m[1][3], m[2][3], m[3][3] } }
end

---Linear map that scales along the group frame axes: G * diag(scale) * G^T
---@param frame number[][] 3x3, columns are the group axes in world space
---@param scale number[]
---@return number[][]
local function groupScaleMatrix(frame, scale)
    return Mat3.mul(Mat3.mul(frame, { { scale[1], 0, 0 }, { 0, scale[2], 0 }, { 0, 0, scale[3] } }), Mat3.transpose(frame))
end

---New sides for an object scaled along the group frame's axes. An object tilted against the group
---can't stretch along the group's axes and stay a box, so each local axis gets a weighted geometric
---mean of the factors: weight = how much that axis points along each group axis (squared, they add
---up to 1). Exact for objects aligned with the group, and reversible: scaling by s and then by 1/s
---gives the original sides back (the old "how much the map stretches the axis" fit didn't, tilted
---objects drifted on every scale)
---@param obj FileParserEnvObj
---@param sides number[]
---@param frame number[][] group frame, columns are the group axes
---@param scale number[] factors along the group axes
---@param shapeName string? "box", "sphere" or "cylinder" (a pill): the shape line's, for objects not in
---the world (atmo objects); nil asks the game
---@return number[]
local function scaleSides(obj, sides, frame, scale, shapeName)
    local axes = getLocalAxes(obj)
    local logScale = {}
    for j = 1, 3 do logScale[j] = math.log(math.max(math.abs(scale[j]), 1e-9)) end -- mirroring keeps sizes
    local f = {}
    for i = 1, 3 do
        local a, sum = axes[i], 0
        for j = 1, 3 do
            local along = a[1] * frame[1][j] + a[2] * frame[2][j] + a[3] * frame[3][j]
            sum = sum + along * along * logScale[j]
        end
        f[i] = math.exp(sum)
    end

    local out
    local sphere, capsule
    if shapeName then
        sphere, capsule = shapeName == "sphere", shapeName == "cylinder"
    else
        local shape = shapeIdOf(obj)
        sphere, capsule = shape == SHAPE.SPHERE, shape == SHAPE.CAPSULE
    end
    if sphere then -- x radius, stays round: geometric mean of all axes
        local r = sides[1] * (f[1] * f[2] * f[3]) ^ (1 / 3)
        out = { r, r, r }
    elseif capsule then -- x radius (round across local x and y), y length along local z
        out = { sides[1] * math.sqrt(f[1] * f[2]), sides[2] * f[3], sides[3] }
    else
        out = { sides[1] * f[1], sides[2] * f[2], sides[3] * f[3] }
    end
    for i = 1, 3 do out[i] = math.max(math.abs(out[i]), MGE.MIN_SIDE) end -- zero sides crash physics
    return out
end

---@param a number[][]
---@param b number[][]
local function sameFrame(a, b)
    for i = 1, 3 do
        for j = 1, 3 do
            if math.abs(a[i][j] - b[i][j]) > 1e-4 then return false end
        end
    end
    return true
end

---The group's axes (what Rot shows and Scale / Resize stretch along): objects turned together share
---their orientation. If the selected objects point different ways, the orientation most of them
---share wins (a house's walls over its tilted roof pieces), ties go to the first object. Counted,
---not weighed by size: scaling changes sizes, and the axes must not switch halfway through a Scale
---or between a Resize and its inverse (rotating and scaling never change which objects match)
---@param objects FileParserEnvObj[]
---@return number[][]
pickGroupFrame = function(objects)
    local groups = {} -- { frame, weight }
    for _, obj in ipairs(objects) do
        local frame = orientationOf(obj)
        local weight = 1
        local group
        for _, g in ipairs(groups) do
            if sameFrame(g.frame, frame) then group = g break end
        end
        if group then
            group.weight = group.weight + weight
        else
            table.insert(groups, { frame = frame, weight = weight })
        end
    end
    local best = groups[1]
    for _, g in ipairs(groups) do
        if g.weight > best.weight then best = g end
    end
    return best and best.frame or Mat3.IDENTITY
end

---Rotation (rotBy offsets) that turns the group from `frame` to the angles `target` (radians, the
---Rot row's order)
---@param frame number[][]
---@param target number[]
---@return number[]
local function rotationTo(frame, target)
    local wanted = Mat3.mul(Mat3.rotX(target[1]), Mat3.mul(Mat3.rotY(target[2]), Mat3.rotZ(target[3])))
    -- rotation that turns the current orientation into the wanted one, applied like a Rotate
    return { Mat3.toEulerXYZ(Mat3.mul(wanted, Mat3.transpose(frame))) }
end

---Where scaling by factors along the group's axes puts each object, without changing anything
---(scaleBy applies it, Scale predicts with it)
---@param selectedObjects FileParserEnvObj[] objects in the world
---@param scale number[] x y z factors
---@return { obj: FileParserEnvObj, pos: number[], sides: number[] }[] planned
---@return fun(x: number, y: number, z: number): number, number, number scalePos
local function planScale(selectedObjects, scale)
    local pivot = { getSelectionPivot(selectedObjects) }

    -- scale along the group's own axes, as if scaled before rotating
    local frame = pickGroupFrame(selectedObjects)
    local map = groupScaleMatrix(frame, scale)
    local function scalePos(x, y, z)
        local rel = Mat3.apply(map, { x - pivot[1], y - pivot[2], z - pivot[3] })
        return pivot[1] + rel[1], pivot[2] + rel[2], pivot[3] + rel[3]
    end

    local planned = {}
    for _, v in ipairs(selectedObjects) do
        if present(v) then
            local p = positionOf(v)
            table.insert(planned, {
                obj = v,
                pos = { scalePos(p[1], p[2], p[3]) },
                sides = scaleSides(v, { sidesOf(v) }, frame, scale),
            })
        end
    end
    return planned, scalePos
end

---Scales the objects (sides and spacing) around their center by factors along the group's axes
---@param selectedObjects FileParserEnvObj[]
---@param scale number[] x y z factors
local function scaleBy(selectedObjects, scale)
    local planned, scalePos = planScale(selectedObjects, scale)
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
    -- same as moving: the camera follows, backing off only if the group no longer fits on screen
    if MGE.Camera.followMoves then MGE.Camera.focus(selectedObjects, true) end
    finishTransform(selectedObjects, scalePos)
    Transforms.onChanged()
end

---Resize row: multiplies size and spacing of selected objects by the typed factors
---@param typed (number?)[] x y z factors, nil (or 0 / -1) axes don't change
function Transforms.scale(typed)
    local selectedObjects = getSelected()
    if #selectedObjects == 0 then return end
    local scale = {}
    for i = 1, 3 do
        local value = typed[i] or 0
        scale[i] = (value == 0 or value == -1) and 1 or value -- 0 and -1 mean no change
    end
    scaleBy(selectedObjects, scale)
end

---Group axes (columns of the group frame) as vectors
---@param frame number[][]
---@return number[][]
local function frameAxes(frame)
    return {
        { frame[1][1], frame[2][1], frame[3][1] },
        { frame[1][2], frame[2][2], frame[3][2] },
        { frame[1][3], frame[2][3], frame[3][3] },
    }
end

---Where the selection starts and ends along three axes, objects' own size and rotation included
---@param selectedObjects FileParserEnvObj[]
---@param axes number[][] unit axes to measure along
---@param scale number[]? after scaling by these factors (planScale), nil for now
---@return number[] min, number[] max along each axis (math.huge / -math.huge when nothing is in the world)
local function groupBounds(selectedObjects, axes, scale)
    local placed = {} -- object -> planned pos and sides (by table: an atmo object's id is another object's)
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
            for i, a in ipairs(axes) do
                local function along(k) return math.abs(localAxes[k][1] * a[1] + localAxes[k][2] * a[2] + localAxes[k][3] * a[3]) end
                local half
                if shape == SHAPE.SPHERE then
                    half = sx
                elseif shape == SHAPE.CAPSULE then -- x radius, y length along local z
                    half = sx + along(3) * sy / 2
                else
                    half = (along(1) * sx + along(2) * sy + along(3) * sz) / 2
                end
                local c = x * a[1] + y * a[2] + z * a[3]
                min[i] = math.min(min[i], c - half)
                max[i] = math.max(max[i], c + half)
            end
        end
    end
    return min, max
end

---Overall size of the selection along the group's axes (what Scale scales along), objects' own
---size and rotation included
---@param selectedObjects FileParserEnvObj[]
---@param scale number[]? size after scaling by these factors (planScale), nil for the current size
---@return number[] extents x y z, 0 when nothing is in the world
local function groupExtents(selectedObjects, scale)
    local min, max = groupBounds(selectedObjects, frameAxes(pickGroupFrame(selectedObjects)), scale)
    local extents = {}
    for i = 1, 3 do extents[i] = max[i] > min[i] and max[i] - min[i] or 0 end
    return extents
end

---Scale row: scales the selection so its overall size along the group's X, Y or Z becomes the typed
---value. Axes left empty (or 0 and below) don't change.
---Size doesn't follow the factor one to one: pill caps keep their radius when the length scales,
---spheres stay round (their radius takes the average factor) and rotated objects only partly stretch.
---So the factors are found by predicting the result (planScale) and correcting until it matches.
---Each step corrects by how fast the size actually followed the factor last time (in log space:
---a sphere's size grows with the cube root of one axis' factor), so it takes a few steps, not dozens
---@param typed (number?)[] x y z sizes, nil (or 0 and below) axes don't change
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

    ---@type number[]
    local scale = { 1, 1, 1 }
    ---@type table<integer, { scale: number, size: number }> per axis: log factor and log size of the step before
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
                    -- how much the size moved per factor change, 1 for plain boxes; kept in a sane
                    -- range, axes affect each other (spheres) so a step can be off
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

---Group orientation as the Rot row shows it (radians, Transforms.fileAngles), from the rot lines
---@param selectedObjects FileParserEnvObj[]
---@return number[]
function Transforms.groupAngles(selectedObjects)
    local sign = angleSign()
    local x, y, z = Mat3.toEulerXYZ(pickGroupFrame(selectedObjects))
    return { sign * x, sign * y, sign * z }
end

---Angle row: rotates the selection so the group's orientation becomes the typed degrees on the
---entered axis, the other axes keep their current angle
---@param typed (number?)[] x y z degrees, nil axes keep their angle
function Transforms.angleTo(typed)
    local selectedObjects = getSelected()
    if #selectedObjects == 0 then return end
    local frame = pickGroupFrame(selectedObjects)
    local target = Transforms.groupAngles(selectedObjects) -- as shown, typed axes replace theirs
    local changed = false
    for i = 1, 3 do
        if typed[i] then target[i], changed = math.rad(typed[i]), true end
    end
    if not changed then return end
    local sign = angleSign()
    rotBy(selectedObjects, rotationTo(frame, { sign * target[1], sign * target[2], sign * target[3] }))
end


-- used by the editor rows, the generator and the offline tests
Transforms.writeVector = writeVectorProperty
Transforms.getSelectionPivot = getSelectionPivot
Transforms.positionOf = positionOf
Transforms.moveBy = moveBy -- gizmo drag commit
Transforms.groupFrame = function(selectedObjects) return pickGroupFrame(selectedObjects) end

---Live world only, the mod data is untouched: shows the objects turned by a rotation matrix around
---their center (gizmo ring drag). rotateByMatrix with the same matrix makes it real
---@param selectedObjects FileParserEnvObj[]
---@param rotation number[][]
function Transforms.previewRotate(selectedObjects, rotation)
    local pivot = { getSelectionPivot(selectedObjects) }
    for _, v in ipairs(selectedObjects) do
        if inWorld(v) then
            local p = positionOf(v)
            local rel = Mat3.apply(rotation, { p[1] - pivot[1], p[2] - pivot[2], p[3] - pivot[3] })
            set_obj_pos(v.id - 1, pivot[1] + rel[1], pivot[2] + rel[2], pivot[3] + rel[3])
            -- rot line angles of the turned orientation: it's Rx(-x) Ry(-y) Rz(-z), see orientationOf
            local x, y, z = Mat3.toEulerXYZ(Mat3.mul(rotation, orientationOf(v)))
            set_obj_rot(v.id - 1, -x, -y, -z)
        end
    end
end

---Turns the objects by a rotation matrix around their center, like the Rotate row (file and world,
---undo step, joints follow)
---@param selectedObjects FileParserEnvObj[]
---@param rotation number[][]
function Transforms.rotateByMatrix(selectedObjects, rotation)
    rotBy(selectedObjects, { Mat3.toEulerXYZ(rotation) }) -- rotBy's offsets: rotX(x) rotY(y) rotZ(z)
end

---Live world only, the mod data is untouched: shows the objects scaled by factors along the group's
---axes like Resize would (gizmo scale drag). Planned from baseSides (the sizes at the grab), not the
---already previewed ones. Put baseSides back (restoreLive) before scaleBy makes it real
---@param selectedObjects FileParserEnvObj[]
---@param scale number[]
---@param baseSides table<integer, number[]> Transforms.liveSides at the grab
function Transforms.previewScale(selectedObjects, scale, baseSides)
    for _, v in ipairs(selectedObjects) do
        local s = baseSides[v.id]
        if s and inWorld(v) then set_obj_sides(v.id - 1, s[1], s[2], s[3]) end
    end
    for _, p in ipairs((planScale(selectedObjects, scale))) do
        if inWorld(p.obj) then
            local id = p.obj.id - 1
            set_obj_pos(id, p.pos[1], p.pos[2], p.pos[3])
            set_obj_sides(id, p.sides[1], p.sides[2], p.sides[3])
            applyFileRotation(p.obj)
        end
    end
end
Transforms.orientationOf = orientationOf
Transforms.scaleSidesFor = scaleSides -- atmo objects' scale (utils/atmo_layer.lua) passes their shape
Transforms.groupExtents = groupExtents
Transforms.rotBy = rotBy
Transforms.scaleBy = scaleBy

return Transforms
