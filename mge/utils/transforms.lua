-- Move, rotate and scale for the selected objects: the math behind the editor's Pos/Move, Rot/Rotate and
-- Scale/Resize rows (ui/editor_core.lua). Live changes go to the game (set_obj_*) and the
-- mod data, then History.commit. Transforms.onChanged is called after each change (the editor
-- refreshes the measured rows), tests can leave it as is.
require("toriui.uielement3d") -- Utils3D.MatrixToMatrixTB

local Transforms = {}
MGE.Transforms = Transforms

local RotatingOld = dofile(MGE.scriptPath .. "utils/rotating.lua")
local ModData = MGE.ModData
local History = MGE.History
local Joints = MGE.Joints
local Mat3 = MGE.Mat3
local FileHandler = MGE.FileHandler
local SHAPE = MGE.SHAPE
local getSelected = ModData.getSelected
local POS_ORIGIN = MGE.POS_ORIGIN

-- defined further down, used by functions above them
local pickGroupFrame

---Called after every change, set by the editor to refresh the rows showing current values
Transforms.onChanged = function() end

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
    local linked = Joints.getLinked(Joints.idSet(selected))
    for _, joint in ipairs(linked) do
        if posFn then Joints.transformPos(joint, posFn) end
        if axisFn then Joints.transformAxis(joint, axisFn) end
    end
    History.commit()
    if #linked > 0 then MGE.save() end
end

---@param selectedObjects FileParserEnvObj[]
---@return number, number, number
local function getSelectionPivot(selectedObjects)
    local total = #selectedObjects
    if total == 0 then return 0, 0, 0 end

    local sumX, sumY, sumZ, count = 0, 0, 0, 0
    for _, obj in ipairs(selectedObjects) do
        local x, y, z = get_obj_pos(obj.id - 1)
        if x then -- objects not in the world (yet) don't count
            sumX, sumY, sumZ, count = sumX + x, sumY + y, sumZ + z, count + 1
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
        local pos = { move(get_obj_pos(v.id - 1)) }
        set_obj_pos(v.id - 1, pos[1], pos[2], pos[3])
        writeVectorProperty(v, "pos", pos)
    end

    -- camera follows the selection, backing off only if it no longer fits on screen
    -- (can be turned off with the camera button in the top menu)
    if MGE.Camera.followMoves then MGE.Camera.focus(selectedObjects, true) end
    finishTransform(selectedObjects, move)
    Transforms.onChanged()
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
        local rotValue = v.props.rot or "0 0 0"
        local x, y, z = rotValue:match("(%S+)%s+(%S+)%s+(%S+)")
        local rot = { math.rad(tonumber(x) or 0), math.rad(tonumber(y) or 0), math.rad(tonumber(z) or 0) }
        local pos = { get_obj_pos(v.id - 1) }

        local outPos = RotatingOld.SetRotPos(
            pos[1], pos[2], pos[3],
            pivot[1], pivot[2], pivot[3],
            offsets[1], offsets[2], offsets[3]
        )
        local outRot = RotatingOld.SetRotOffset(
            rot[1], rot[2], rot[3],
            offsets[1], offsets[2], offsets[3]
        )
        set_obj_rot(v.id - 1, math.rad(outRot[1]), math.rad(outRot[2]), math.rad(outRot[3]))
        set_obj_pos(v.id - 1, outPos[1], outPos[2], outPos[3])

        writeVectorProperty(v, "rot", outRot)
        writeVectorProperty(v, "pos", outPos)
    end
    -- each object remembers the rotation MGE applied to it (saved in the mod), so scaling can use the
    -- group's own axes later, even after reselecting. Same rotation SetRotPos applies: z, then y, then x
    local rotation = Mat3.mul(Mat3.rotX(offsets[1]), Mat3.mul(Mat3.rotY(offsets[2]), Mat3.rotZ(offsets[3])))
    for _, v in ipairs(selectedObjects) do
        v.frame = Mat3.mul(rotation, v.frame or Mat3.IDENTITY)
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

---Rotate row: rotates selected objects by the typed degrees
---@param typed (number?)[] x y z degrees, nil axes don't turn
function Transforms.rotate(typed)
    local selectedObjects = getSelected()
    if #selectedObjects == 0 then return end
    rotBy(selectedObjects, { math.rad(typed[1] or 0), math.rad(typed[2] or 0), math.rad(typed[3] or 0) })
end

---World directions of an object's local x, y, z axes.
---get_obj_rot is row-major (r0 r1 r2 = first row, verified in game against MGE's own rotation),
---so the local axes are its columns.
---@param id integer 0-based object id
---@return number[][]
local function getLocalAxes(id)
    local raw = get_obj_rot(id)
    if type(raw) ~= "table" then return { { 1, 0, 0 }, { 0, 1, 0 }, { 0, 0, 1 } } end
    local m = Utils3D.MatrixToMatrixTB(raw)
    return { { m.r0, m.r4, m.r8 }, { m.r1, m.r5, m.r9 }, { m.r2, m.r6, m.r10 } }
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
---@param id integer 0-based object id
---@param sides number[]
---@param frame number[][] group frame, columns are the group axes
---@param scale number[] factors along the group axes
---@return number[]
local function scaleSides(id, sides, frame, scale)
    local axes = getLocalAxes(id)
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
    local shape = get_obj_shape(id)
    if shape == SHAPE.SPHERE then -- x radius, stays round: geometric mean of all axes
        local r = sides[1] * (f[1] * f[2] * f[3]) ^ (1 / 3)
        out = { r, r, r }
    elseif shape == SHAPE.CAPSULE then -- x radius (round across local x and y), y length along local z
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

---Frame to scale the selection in: objects rotated together share the frame MGE stored on them.
---If selected objects carry different frames, the one covering the most volume wins.
---Objects never rotated by MGE count as the world frame.
---@param objects FileParserEnvObj[]
---@return number[][]
pickGroupFrame = function(objects)
    local groups = {} -- { frame, weight }
    for _, obj in ipairs(objects) do
        local frame = obj.frame or Mat3.IDENTITY
        local sx, sy, sz = get_obj_sides(obj.id - 1)
        local weight = math.abs((sx or 1) * (sy or 1) * (sz or 1)) + 1e-6
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

    -- scale along the group's own axes (world axes if never rotated by MGE), as if scaled before rotating
    local frame = pickGroupFrame(selectedObjects)
    local map = groupScaleMatrix(frame, scale)
    local function scalePos(x, y, z)
        local rel = Mat3.apply(map, { x - pivot[1], y - pivot[2], z - pivot[3] })
        return pivot[1] + rel[1], pivot[2] + rel[2], pivot[3] + rel[3]
    end

    local planned = {}
    for _, v in ipairs(selectedObjects) do
        if get_obj_pos(v.id - 1) ~= nil then
            table.insert(planned, {
                obj = v,
                pos = { scalePos(get_obj_pos(v.id - 1)) },
                sides = scaleSides(v.id - 1, { get_obj_sides(v.id - 1) }, frame, scale),
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
        set_obj_pos(id, p.pos[1], p.pos[2], p.pos[3])
        set_obj_sides(id, p.sides[1], p.sides[2], p.sides[3])
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

---Overall size of the selection along the group's axes (what Scale scales along), objects' own
---size and rotation included
---@param selectedObjects FileParserEnvObj[]
---@param scale number[]? size after scaling by these factors (planScale), nil for the current size
---@return number[] extents x y z, 0 when nothing is in the world
local function groupExtents(selectedObjects, scale)
    local axes = frameAxes(pickGroupFrame(selectedObjects))
    local placed = {} -- obj id -> planned pos and sides
    if scale then
        for _, p in ipairs((planScale(selectedObjects, scale))) do placed[p.obj.id] = p end
    end
    local min, max = { math.huge, math.huge, math.huge }, { -math.huge, -math.huge, -math.huge }
    for _, v in ipairs(selectedObjects) do
        local id = v.id - 1
        local x, y, z = get_obj_pos(id)
        local sx, sy, sz = get_obj_sides(id)
        local p = placed[v.id]
        if p then
            x, y, z = p.pos[1], p.pos[2], p.pos[3]
            sx, sy, sz = p.sides[1], p.sides[2], p.sides[3]
        end
        if x then
            local shape = get_obj_shape(id)
            local localAxes = getLocalAxes(id)
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

---Group orientation as angles (radians) in the rotate tool's order. Only rotations MGE applied are
---known (stored per object as #mge_frame), objects never rotated by MGE count as 0 0 0
---@param selectedObjects FileParserEnvObj[]
---@return number[]
function Transforms.groupAngles(selectedObjects)
    return { Mat3.toEulerXYZ(pickGroupFrame(selectedObjects)) }
end

---Angle row: rotates the selection so the group's orientation becomes the typed degrees on the
---entered axis, the other axes keep their current angle
---@param typed (number?)[] x y z degrees, nil axes keep their angle
function Transforms.angleTo(typed)
    local selectedObjects = getSelected()
    if #selectedObjects == 0 then return end
    local frame = pickGroupFrame(selectedObjects)
    local target = { Mat3.toEulerXYZ(frame) }
    local changed = false
    for i = 1, 3 do
        if typed[i] then target[i], changed = math.rad(typed[i]), true end
    end
    if not changed then return end
    rotBy(selectedObjects, rotationTo(frame, target))
end


-- used by the editor rows, the generator and the offline tests
Transforms.writeVector = writeVectorProperty
Transforms.getSelectionPivot = getSelectionPivot
Transforms.groupExtents = groupExtents
Transforms.rotBy = rotBy
Transforms.scaleBy = scaleBy

return Transforms
