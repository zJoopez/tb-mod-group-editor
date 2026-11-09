require("toriui.uielement3d") -- Utils3D.MatrixToMatrixTB

local editor = {}
local RotatingOld = dofile(MGE.scriptPath .. "utils/rotating.lua")
local ModData = MGE.ModData
local History = MGE.History
local Joints = MGE.Joints
local Mat3 = MGE.Mat3
local Widgets = MGE.Widgets
local FileHandler = MGE.FileHandler
local SHAPE = MGE.SHAPE
local getSelected = ModData.getSelected

local totalHeight = 0

---@type table<string, UIElement[]>
local inwuts = {}

local function updateContentHeight(height)
    totalHeight = totalHeight + height
end

---Numbers typed in a row's inputs, nil for empty fields. With `only`, just that input is read
---(Enter applies the field it was pressed in, the row's other fields count as empty)
---@param inputs UIElement[]
---@param only integer?
---@return (number?)[]
local function readInputs(inputs, only)
    local values = {}
    for i, input in ipairs(inputs) do
        if not only or i == only then values[i] = tonumber(input.textfieldstr[1]) end
    end
    return values
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

-- Rebuilds the Pos/Angle/Size rows so their placeholders show the selection's current center,
-- orientation and size (defined with the panels)
local refreshMeasured

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
    refreshMeasured()
end

---Move row: moves selected objects by the typed offsets
---@param only integer? axis input Enter was pressed in, nil applies all
local function moveSelected(only)
    local selectedObjects = getSelected()
    if #selectedObjects == 0 then return end
    local typed = readInputs(inwuts.pos, only)
    moveBy(selectedObjects, { typed[1] or 0, typed[2] or 0, typed[3] or 0 })
end

---Pos row: moves selected objects so their center (same pivot as rotate) lands on the typed
---coordinates. Axes left empty don't move
---@param only integer? axis input Enter was pressed in, nil applies all
local function positionSelected(only)
    local selectedObjects = getSelected()
    if #selectedObjects == 0 then return end
    local typed = readInputs(inwuts.position, only)
    local pivot = { getSelectionPivot(selectedObjects) }
    local offsets = {}
    for i = 1, 3 do offsets[i] = typed[i] and typed[i] - pivot[i] or 0 end
    moveBy(selectedObjects, offsets)
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
    refreshMeasured()
end

---Rotate row: rotates selected objects by the typed degrees
---@param only integer? axis input Enter was pressed in, nil applies all
local function rotSelected(only)
    local selectedObjects = getSelected()
    if #selectedObjects == 0 then return end
    local typed = readInputs(inwuts.rot, only)
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
local function pickGroupFrame(objects)
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
    finishTransform(selectedObjects, scalePos)
    refreshMeasured()
end

---Scale row: multiplies size and spacing of selected objects by the typed factors
---@param only integer? axis input Enter was pressed in, nil applies all
local function scaleSelected(only)
    local selectedObjects = getSelected()
    if #selectedObjects == 0 then return end
    local typed = readInputs(inwuts.scale, only)
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
---So the factors are found by predicting the result (planScale) and correcting until it matches
---@param only integer? axis input Enter was pressed in, nil applies all
local function sizeSelected(only)
    local selectedObjects = getSelected()
    if #selectedObjects == 0 then return end
    local typed = readInputs(inwuts.size, only)
    local current = groupExtents(selectedObjects)
    local targets, changed = {}, false
    for i = 1, 3 do
        if typed[i] and typed[i] > 0 and current[i] > 1e-9 then
            targets[i], changed = typed[i], true
        end
    end
    if not changed then return end

    local scale = { 1, 1, 1 }
    for _ = 1, 100 do
        local extents = groupExtents(selectedObjects, scale)
        local done = true
        for i = 1, 3 do
            if targets[i] and extents[i] > 1e-9 then
                local ratio = targets[i] / extents[i]
                if math.abs(ratio - 1) > 1e-10 then
                    done = false
                    scale[i] = math.min(math.max(scale[i] * ratio, 1e-4), 1e4)
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
local function groupAngles(selectedObjects)
    return { Mat3.toEulerXYZ(pickGroupFrame(selectedObjects)) }
end

---Angle row: rotates the selection so the group's orientation becomes the typed degrees on the
---entered axis, the other axes keep their current angle
---@param only integer? axis input Enter was pressed in, nil applies all
local function angleSelected(only)
    local selectedObjects = getSelected()
    if #selectedObjects == 0 then return end
    local typed = readInputs(inwuts.angle, only)
    local frame = pickGroupFrame(selectedObjects)
    local target = { Mat3.toEulerXYZ(frame) }
    local changed = false
    for i = 1, 3 do
        if typed[i] then target[i], changed = math.rad(typed[i]), true end
    end
    if not changed then return end
    local wanted = Mat3.mul(Mat3.rotX(target[1]), Mat3.mul(Mat3.rotY(target[2]), Mat3.rotZ(target[3])))
    -- rotation that turns the current orientation into the wanted one, applied like a Rotate
    local delta = Mat3.mul(wanted, Mat3.transpose(frame))
    rotBy(selectedObjects, { Mat3.toEulerXYZ(delta) })
end

-- Rebuilds the Properties tab so its placeholders show the selection's current values
local refreshProperties

-- Simple per-object properties edited with absolute values. Friction has no live setter,
-- it's stored in props and applied by saving (the mod reloads with the new value).
-- default: the game's value for objects without the line. decimals: what the game's modmaker writes
-- (friction 10000.00, bounce 0.100000, mass 0.1000), used for the file and the placeholders.
---@class EditorProperty
---@field min number
---@field default number
---@field decimals integer
---@field setter (fun(id: integer, value: number))?
---@field getter (fun(id: integer): number?)?

---@type table<string, EditorProperty>
local PROPERTIES = {
    mass = { min = 0.0001, default = 0.1, decimals = 4, -- zero mass breaks physics
        setter = function(id, v) set_obj_mass(id, v) end, getter = function(id) return get_obj_mass(id) end },
    friction = { min = 0, default = 10000, decimals = 2 },
    bounce = { min = 0, default = 0.1, decimals = 6,
        setter = function(id, v) set_obj_bounce(id, v) end, getter = function(id) return get_obj_bounce(id) end },
}

---Value as the game writes it for the property, e.g. 0.1 -> "0.1000" for mass
---@param property EditorProperty
---@param value number
---@return string
local function formatProperty(property, value)
    return string.format("%." .. property.decimals .. "f", value)
end

---Sets a property on all selected objects from an input field, empty input does nothing
---@param key "mass"|"friction"|"bounce"
---@param input UIElement
local function setProperty(key, input)
    local value = tonumber(input.textfieldstr[1])
    if not value then return end
    local selectedObjects = getSelected()
    if #selectedObjects == 0 then return end

    local property = PROPERTIES[key]
    value = math.max(value, property.min)
    for _, v in ipairs(selectedObjects) do
        v.props[key] = formatProperty(property, value)
        if property.setter then property.setter(v.id - 1, value) end
    end
    History.commit()
    if property.setter then
        refreshProperties()
    else
        MGE.save() -- reload rebuilds the editor with the new value
    end
end

-- empty color fields count as these (0-255), shown as the fields' placeholders
local COLOR_DEFAULTS = { 0, 0, 0, 255 }

---Sets the color typed in all four fields (r g b a, 0-255) on selected objects. Empty fields use
---COLOR_DEFAULTS, so what the fields show is exactly what's applied
local function adjustColor()
    local selectedObjects = getSelected()
    if #selectedObjects == 0 then return end

    local typed = readInputs(inwuts.color)
    local color = {}
    for i = 1, 4 do
        -- 255 is the official max, the game accepts up to 500 and draws those brighter
        color[i] = math.max(0, math.min(500, typed[i] or COLOR_DEFAULTS[i])) / 255
    end
    for _, v in ipairs(selectedObjects) do
        set_obj_color(v.id - 1, color[1], color[2], color[3], color[4])
        writeVectorProperty(v, "color", { color[1], color[2], color[3], color[4] })
    end
    History.commit() -- no panel refresh needed, color placeholders don't depend on the selection
end

---Value shared by the objects, "mixed" when they differ, nil for no objects
---@param objects FileParserEnvObj[]
---@param read fun(obj: FileParserEnvObj): any never nil
local function sharedChoice(objects, read)
    local value
    for _, obj in ipairs(objects) do
        local v = read(obj)
        if value == nil then
            value = v
        elseif value ~= v then
            return "mixed"
        end
    end
    return value
end


---@param placeholder string? text shown while empty, defaults to "0"
local function createInput(container, onInputFunc, placeholder)
    local input = TBMenu:spawnTextField2(container, nil, "",
        placeholder or "0",
        {
            inputType = 2,
            textfield = true,
            returnKeyType = KEYBOARD_RETURN.SEND,
            isNumeric = true,
            allowDecimal = true,
            allowNegative = true,
            textAlign = CENTER,
            fontId = FONTS.LMEDIUM,
            darkerMode = true, -- base window color, matches the panel buttons (Widgets.PANEL_STYLE)
            textScale = 0.65, -- smaller than the default, matches the labels
        })
    input:addKeyboardHandlers(nil, function(key)
        if key ~= 13 then return end --enter
        onInputFunc()
    end)
    return input
end

---Row with the label column on the left and an optional "?" help icon at the end.
---Returns the row and the x and width of the space between them, for inputs or buttons
---@param label string
---@param parent UIElement
---@param help string? explanation shown when hovering the "?" icon
---@param onLabelClick function? makes the label a button (switches a transform row's mode)
---@return UIElement row, number contentX, number contentW
local function createRow(label, parent, help, onLabelClick)
    local row = parent:addChild({
        pos = { 0, totalHeight },
        size = { parent.size.w, 30 },
        interactive = true,
    }, true)

    local labelW = 80
    local helpSize = 22
    local helpW = help and helpSize + 8 or 0 -- space reserved at the end of the row for the "?" icon
    if onLabelClick then
        Widgets.button(row, { x = 2, y = 2, w = labelW - 4, h = row.size.h - 4 }, label, onLabelClick, nil,
            Widgets.PANEL_STYLE)
    else
        local labelContainer = row:addChild({
            pos = { 0, 0 },
            size = { labelW, row.size.h },
        }, true)
        labelContainer:addAdaptedText(label, nil, nil, nil, CENTERMID, 0.7, nil, nil)
    end

    if help then
        -- "?" at the row's end, the explanation opens right of it, outside the window
        Widgets.helpIcon(row, -helpSize - 2, (row.size.h - helpSize) / 2, helpSize, help, nil, Widgets.PANEL_STYLE)
    end

    updateContentHeight(row.size.h)
    return row, labelW, row.size.w - labelW - helpW
end

---Label column followed by equally sized inputs and an optional "?" help icon at the end
---@param label string
---@param parent UIElement
---@param func fun(inputs: UIElement[], index: integer) called on enter
---@param placeholders string[] one per input
---@param help string? explanation shown when hovering the "?" icon
---@param onLabelClick function? see createRow
---@return UIElement[] inputs, UIElement row
local function createInputRow(label, parent, func, placeholders, help, onLabelClick)
    local row, contentX, contentW = createRow(label, parent, help, onLabelClick)
    local columnSize = contentW / #placeholders
    local inputs = {}
    for i, placeholder in ipairs(placeholders) do
        local inputContainer = row:addChild({
            pos = { contentX + (i - 1) * columnSize, 0 },
            size = { columnSize, row.size.h },
            interactive = true,
        }, true)
        inputs[i] = createInput(inputContainer, function() func(inputs, i) end, placeholder)
    end
    return inputs, row
end

---Label column followed by buttons for a fixed set of values, the current one is highlighted
---@param label string
---@param parent UIElement
---@param choices { label: string, value: any }[]
---@param current any value shared by the selection, nil or "mixed" highlights nothing
---@param onPick fun(value: any)
---@param help string?
local function createChoiceRow(label, parent, choices, current, onPick, help)
    local row, contentX, contentW = createRow(label, parent, help)
    local holder = row:addChild({
        pos = { contentX + 2, 2 },
        size = { contentW - 4, row.size.h - 4 },
    }, true)
    local items = {}
    for i, choice in ipairs(choices) do
        items[i] = { label = choice.label, onClick = function() onPick(choice.value) end }
    end
    for i, btn in ipairs(Widgets.buttonRow(holder, 0, holder.size.h, items, 4, nil, Widgets.PANEL_STYLE)) do
        if choices[i].value == current then btn.bgColor = TB_MENU_DEFAULT_LIGHTER_COLOR end
    end
end

---Label column followed by on/off buttons (any number can be on), active ones are highlighted
---like the current choice in createChoiceRow
---@param label string
---@param parent UIElement
---@param toggles { label: string, active: boolean, onClick: function }[]
---@param help string?
local function createToggleButtonRow(label, parent, toggles, help)
    local row, contentX, contentW = createRow(label, parent, help)
    local holder = row:addChild({
        pos = { contentX + 2, 2 },
        size = { contentW - 4, row.size.h - 4 },
    }, true)
    for i, btn in ipairs(Widgets.buttonRow(holder, 0, holder.size.h, toggles, 4, nil, Widgets.PANEL_STYLE)) do
        if toggles[i].active then btn.bgColor = TB_MENU_DEFAULT_LIGHTER_COLOR end
    end
end

local function duplicate()
    local selected = getSelected()
    if #selected == 0 then return end
    -- only joints between selected objects are copied, so only those copies need low ids
    local linkedJoints = Joints.getLinked(Joints.idSet(selected))
    if not Joints.haveRoom(#linkedJoints) then return end
    local linkedIds = Joints.getObjectIds(linkedJoints)
    local plans = {}
    for i, obj in ipairs(selected) do
        plans[i] = { pool = ModData.isStatic(obj, true) and "static" or "nonStatic", linked = linkedIds[obj.id] or false }
    end
    local ids = ModData.allocateIds(plans) -- all or nothing
    if not ids then return end

    local idMap = {} -- original id -> copy id, used to copy joints between duplicated objects
    for i, obj in ipairs(selected) do
        local copy = ModData.copy(obj)
        copy.id = ids[i]
        copy.props = ModData.copy(obj.props) -- don't share props with the original
        -- the game flag is read by id, a copy without a flag line could get a different default
        -- (objects moved by allocateIds already have their flag written)
        copy.props.flag = copy.props.flag or tostring(get_obj_flag(obj.id - 1) or 0)
        table.insert(ModData.parsed.env_obj, copy)
        idMap[obj.id] = copy.id
        obj.selected = false -- selection moves to the copies (copy keeps selected = true)
    end
    Joints.copyLinked(Joints.getLinked(idMap), idMap)
    ModData.sortObjects()
    History.commit()
    MGE.save()
end

local function delete()
    local deleted = {}
    for i = #ModData.parsed.env_obj, 1, -1 do -- iterating backwards to prevent index issues when removing
        local obj = ModData.parsed.env_obj[i]
        if obj.selected then
            deleted[obj.id] = true
            table.remove(ModData.parsed.env_obj, i)
            ModData.releaseId(obj.id)
        end
    end
    Joints.removeLinkedToAny(deleted) -- a joint can't point to a missing object
    History.commit()
    MGE.save()
end

---Asks for confirmation with Toribash's own popup (TBMenu:showConfirmationWindow) before deleting
local function onDeleteClick()
    local count = #getSelected()
    if count == 0 or (MGE.confirmOverlay and not MGE.confirmOverlay.destroyed) then return end
    local message = "Delete " .. count .. " selected object" .. (count == 1 and "" or "s") .. "?\nUndo can bring them back."
    -- stored so MGE.quit can close it, cleared by either button
    MGE.confirmOverlay = TBMenu:showConfirmationWindow(message, function()
        MGE.confirmOverlay = nil
        delete()
    end, function()
        MGE.confirmOverlay = nil
    end)
end

-- Shape, flags and visibility. Shape and the static flag are read when the mod loads, so they're
-- saved (undo restores them the same way). Other flags and visibility are set live and saved with
-- the next save.

-- names used in mod files, indexed by get_obj_shape
local SHAPE_FILE_NAMES = { [SHAPE.SPHERE] = "sphere", [SHAPE.BOX] = "box", [SHAPE.CAPSULE] = "cylinder" }

---@param obj FileParserEnvObj
---@return string
local function getShape(obj)
    local shape = obj.props.shape and obj.props.shape:lower()
    return shape or SHAPE_FILE_NAMES[get_obj_shape(obj.id - 1)] or "box"
end

---@param obj FileParserEnvObj
---@return boolean
local function isVisible(obj)
    local vis = tonumber(obj.props.visible)
    if vis == nil then
        local live = get_obj_vis(obj.id - 1)
        if type(live) == "boolean" then return live end
        vis = tonumber(live) or 1
    end
    return vis ~= 0
end

---Writes a prop on all selected objects and saves if any of them changed
---@param key string
---@param value string
local function setSelectedProp(key, value)
    local changed = false
    for _, v in ipairs(getSelected()) do
        if v.props[key] ~= value then
            v.props[key] = value
            changed = true
        end
    end
    if not changed then return end
    History.commit()
    MGE.save()
end

-- flag is a bit mask (MGE.FLAGS), objects without a flag line use the game's value
---@param obj FileParserEnvObj loaded object
---@return integer
local function getFlag(obj)
    return tonumber(obj.props.flag) or get_obj_flag(obj.id - 1) or 0
end

---@param flag integer
---@param bits integer
---@return boolean all bits set
local function hasBits(flag, bits)
    return bit.band(flag, bits) == bits
end

---@param flag integer
---@param bits integer
---@param on boolean
---@return integer flag with bits set or cleared, other bits kept
local function withBits(flag, bits, on)
    return on and bit.bor(flag, bits) or flag - bit.band(flag, bits)
end

---Sets or clears flag bits on selected objects, applied live (set_obj_flag) and saved with the
---next save. Not for the static bit, the game only reads that when the mod loads (setStatic)
---@param bits integer
---@param on boolean
local function setFlagBits(bits, on)
    local changed = false
    for _, v in ipairs(getSelected()) do
        local flag = getFlag(v)
        local newFlag = withBits(flag, bits, on)
        if newFlag ~= flag or v.props.flag == nil then
            v.props.flag = tostring(newFlag)
            set_obj_flag(v.id - 1, newFlag)
            changed = true
        end
    end
    if not changed then return end
    History.commit()
    refreshProperties()
end

---Makes selected objects static or dynamic. Ids don't change: dynamic objects above id 48 are
---treated partly as static by the game, the window warns about them until Reindex moves them down.
---Saved instead of set live: tested in game, set_obj_flag doesn't switch static/dynamic, the game
---only reads it when the mod loads. The reload also refreshes the dynamic count and warning.
---@param static boolean
local function setStatic(static)
    local changed = false
    for _, v in ipairs(getSelected()) do
        if ModData.isStatic(v, true) ~= static then
            v.props.flag = tostring(withBits(getFlag(v), MGE.FLAGS.STATIC, static)) -- other flags are kept
            changed = true
        end
    end
    if not changed then return end
    History.commit()
    MGE.save()
end

---Shows or hides selected objects, applied live (set_obj_vis) and saved with the next save
---@param visible boolean
local function setVisible(visible)
    local value = visible and "1" or "0"
    local changed = false
    for _, v in ipairs(getSelected()) do
        if v.props.visible ~= value then
            v.props.visible = value
            set_obj_vis(v.id - 1, visible and 1 or 0)
            changed = true
        end
    end
    if not changed then return end
    History.commit()
    refreshProperties()
end

-- Two panels sharing the editor area, picked by the window's tab row (Main.applyTab -> editor.applyPanel):
--   core:     transforms and look: Pos/Move, Angle/Rotate, Size/Scale, Color, Mass, Shape, Visible
--   advanced: physics: Friction, Bounce, Flags, Model, then Ids (Reindex)
-- Both have input fields, the reset button is shown under either.
-- Every block of rows has its own holder. Move/Rotate/Resize are built once (typed values stay), the
-- other blocks are rebuilt when the selection or the objects change, so their placeholders /
-- highlights show current values (typed text is carried over the rebuild).
local ROW_H = 30
local PANELS = {
    core = { rows = 7 },
    advanced = { rows = 5 },
}
---@type table<string, UIElement>
local panels = {}
---@type table<string, UIElement> rebuilt blocks: measured, coreProps, looks, advancedProps, flags
local blocks = {}
---@type UIElement? reset button, shown under the shown panel
local inputFooter = nil

-- Each transform row has two modes, switched by clicking the row's name. Both rows exist in the same
-- slot (offset rows built once, absolute rows rebuilt with the measured values), one is hidden:
--   absolute: Pos / Rot / Scale, the group ends up at the typed values
--   offset:   Move / Rotate / Resize, the typed values are added (Resize multiplies)
---@alias TransformMode "absolute"|"offset"
local TRANSFORMS = { "move", "rotate", "scale" }
---@type table<string, TransformMode> kept while the script runs, also over editor rebuilds
local transformModes = { move = "absolute", rotate = "absolute", scale = "absolute" }
---@type table<string, table<TransformMode, UIElement>>
local transformRows = { move = {}, rotate = {}, scale = {} }

---Shows each transform row in its current mode and hides the other one. hide(true) keeps the hidden
---row hidden when the panel is shown again (tab switch, F1). The shown row only needs showing while
---the core panel is visible, otherwise the panel shows it when it comes back
local function applyTransformModes()
    local coreShown = panels.core and not panels.core.destroyed and panels.core.displayed
    for _, key in ipairs(TRANSFORMS) do
        for mode, row in pairs(transformRows[key]) do
            if not row.destroyed then
                if mode ~= transformModes[key] then
                    row:hide(true)
                elseif coreShown then
                    row:show(true)
                else
                    row.noreload = nil -- hidden with the panel, comes back with it
                end
            end
        end
    end
end

---@param key "move"|"rotate"|"scale"
local function toggleTransformMode(key)
    transformModes[key] = transformModes[key] == "absolute" and "offset" or "absolute"
    applyTransformModes()
end

---Shows one editor panel, called by Main.applyTab
---@param id string "core"|"advanced"
function editor.applyPanel(id)
    local panel = PANELS[id]
    if not panel then return end
    for panelId, element in pairs(panels) do
        if not element.destroyed then
            if panelId == id then element:show(true) else element:hide(true) end
        end
    end
    applyTransformModes() -- after the panel, rebuilt rows start visible
    if inputFooter and not inputFooter.destroyed then
        inputFooter:show(true)
        inputFooter:moveTo(nil, panel.rows * ROW_H + 8)
    end
end

---Rebuilt children are visible by default, let the window re-apply which tab/panel is shown
local function reapplyTabs()
    if MGE.Main and MGE.Main.applyTab then MGE.Main.applyTab() end
end

local SWITCH_HELP = "\nClick the name to switch to "

---Move/Rotate/Resize rows (offset mode, core panel), built once so typed values stay when the selection changes
---@param holder UIElement
local function buildTransformRows(holder)
    totalHeight = 0
    local zeros = { "0.00", "0.00", "0.00" }
    local function switch(key) return function() toggleTransformMode(key) end end
    -- Enter applies only the field it's pressed in (index i), the row's other fields are ignored
    inwuts.pos, transformRows.move.offset = createInputRow("Move", holder, function(_, i) moveSelected(i) end, zeros,
        "Moves selected objects by X, Y or Z.\nEnter applies the field you typed in." ..
        SWITCH_HELP .. "Pos (move to a position).", switch("move"))
    inwuts.rot, transformRows.rotate.offset = createInputRow("Rotate", holder, function(_, i) rotSelected(i) end, zeros,
        "Rotates selected objects around their center\nby X, Y or Z degrees. Enter applies the field you typed in." ..
        SWITCH_HELP .. "Rot (turn to an angle).", switch("rotate"))
    inwuts.scale, transformRows.scale.offset = createInputRow("Resize", holder, function(_, i) scaleSelected(i) end, zeros,
        "Multiplies size and spacing of selected objects\nalong the group's X, Y or Z. 0 means no change.\nEnter applies the field you typed in." ..
        SWITCH_HELP .. "Scale (set the overall size).", switch("scale"))
end

---@param values number[]
---@return string[]
local function formatHints(values)
    local hints = {}
    for i = 1, 3 do hints[i] = string.format("%.2f", values[i]) end
    return hints
end

---Pos / Rot / Scale rows (absolute), the whole-group versions of Move / Rotate / Resize. Placeholders show the
---selection's current center, orientation (degrees) and size ("0.00" without a selection)
---@param holder UIElement
---@param selected FileParserEnvObj[]
local function buildMeasuredRows(holder, selected)
    totalHeight = 0
    local zeros = { "0.00", "0.00", "0.00" }
    local any = #selected > 0
    local function switch(key) return function() toggleTransformMode(key) end end
    inwuts.position, transformRows.move.absolute = createInputRow("Pos", holder, function(_, i) positionSelected(i) end,
        any and formatHints({ getSelectionPivot(selected) }) or zeros,
        "Moves selected objects so their center is at X, Y or Z.\nShows the current center. Enter applies the field you typed in." ..
        SWITCH_HELP .. "Move (move by an offset).", switch("move"))
    local angles = any and groupAngles(selected) or { 0, 0, 0 }
    for i = 1, 3 do angles[i] = math.deg(angles[i]) end
    inwuts.angle, transformRows.rotate.absolute = createInputRow("Rot", holder, function(_, i) angleSelected(i) end, formatHints(angles),
        "Turns selected objects as a group to X, Y or Z degrees.\nShows the group's current angles. Only rotations done\nin MGE are known, others count as 0. Enter applies the field you typed in." ..
        SWITCH_HELP .. "Rotate (turn by degrees).", switch("rotate"))
    inwuts.size, transformRows.scale.absolute = createInputRow("Scale", holder, function(_, i) sizeSelected(i) end,
        any and formatHints(groupExtents(selected)) or zeros,
        "Scales selected objects so the group is X, Y or Z long\n(along the group's axes, like Resize). Shows the current size.\nEnter applies the field you typed in." ..
        SWITCH_HELP .. "Resize (multiply the size).", switch("scale"))
end

local PROPERTY_HELP = {
    mass = "Sets mass of selected objects.\nShows the current value, \"mixed\" if they differ.",
    friction = "Sets friction of selected objects.\nApplied by saving, the game can't change it live.",
    bounce = "Sets bounciness of selected objects.\nShows the current value, \"mixed\" if they differ.",
}

---Single value rows (mass, friction, bounce), placeholders show the selection's current value
---@param holder UIElement
---@param selected FileParserEnvObj[]
---@param entries string[][] { label, key } pairs
---@return UIElement[] inputs
local function buildPropertyRows(holder, selected, entries)
    local inputs = {}
    for _, entry in ipairs(entries) do
        local label, key = entry[1], entry[2]
        local property = PROPERTIES[key] ---@type EditorProperty
        -- value shared by the selection ("mixed" when they differ), the game default without a
        -- selection or for objects without the line in the file
        local hint = sharedChoice(selected, function(obj)
            local value = property.getter and property.getter(obj.id - 1) or tonumber(obj.props[key])
            return formatProperty(property, value or property.default)
        end) or formatProperty(property, property.default)
        local row = createInputRow(label, holder, function(rowInputs) setProperty(key, rowInputs[1]) end,
            { hint }, PROPERTY_HELP[key])
        table.insert(inputs, row[1])
    end
    return inputs
end

---Color and mass rows (core panel). Color placeholders show the defaults empty fields use
---@param holder UIElement
---@param selected FileParserEnvObj[]
local function buildCoreProps(holder, selected)
    totalHeight = 0
    local colorHints = {}
    for i = 1, 4 do colorHints[i] = tostring(COLOR_DEFAULTS[i]) end
    inwuts.color = createInputRow("Color", holder, function() adjustColor() end, colorHints,
        "Red, green, blue and alpha (0-255, up to 500 for brighter colors).\nEnter in any field applies all four,\nempty fields count as 0 0 0 255.")
    inwuts.coreProps = buildPropertyRows(holder, selected, { { "Mass", "mass" } })
end

---Friction and bounce rows (advanced panel)
---@param holder UIElement
---@param selected FileParserEnvObj[]
local function buildAdvancedProps(holder, selected)
    totalHeight = 0
    inwuts.advancedProps = buildPropertyRows(holder, selected, { { "Friction", "friction" }, { "Bounce", "bounce" } })
end

---Shape and visibility rows (core panel), the selection's current values are highlighted
---@param holder UIElement
---@param selected FileParserEnvObj[]
local function buildLooks(holder, selected)
    totalHeight = 0
    createChoiceRow("Shape", holder, {
        { label = "Box", value = "box" },
        { label = "Sphere", value = "sphere" },
        { label = "Pill", value = "cylinder" }, -- "cylinder" in mod files, round ends in game
    }, sharedChoice(selected, getShape), function(shape) setSelectedProp("shape", shape) end,
        "Shape of selected objects.\nSides are kept, so the size may look different.")
    createChoiceRow("Visible", holder, {
        { label = "Shown", value = true },
        { label = "Hidden", value = false },
    }, sharedChoice(selected, isVisible), setVisible,
        "Hidden objects aren't drawn but still collide.")
end

---Flags row (advanced panel)
---@param holder UIElement
---@param selected FileParserEnvObj[]
local function buildFlags(holder, selected)
    totalHeight = 0
    -- highlighted when every selected object has the flag. A click clears it if they all have it,
    -- otherwise sets it on all of them (decided on click, from the selection at that moment)
    local FLAGS = MGE.FLAGS
    local function allHave(objects, bits)
        return sharedChoice(objects, function(obj) return hasBits(getFlag(obj), bits) end) == true
    end
    local function flagButton(label, bits, apply)
        return {
            label = label,
            active = allHave(selected, bits),
            onClick = function()
                local current = getSelected()
                if #current > 0 then apply(not allHave(current, bits)) end
            end,
        }
    end
    createToggleButtonRow("Flags", holder, {
        flagButton("Static", FLAGS.STATIC, setStatic),
        flagButton("Weapon", FLAGS.WEAPON, function(on) setFlagBits(FLAGS.WEAPON, on) end),
        flagButton("Nogrip", FLAGS.UNGRIPPABLE, function(on) setFlagBits(FLAGS.UNGRIPPABLE, on) end),
    }, "Click to turn a flag on or off for selected objects,\nhighlighted when all of them have it.\n" ..
        "Static: stays in place, otherwise the object is dynamic. Dynamic objects\nonly work fully on ids 1-" ..
        MGE.MAX_NONSTATIC_OBJECTS .. ", Reindex moves them there.\nWeapon: the object acts as a weapon.\n" ..
        "Nogrip: players can't grab the object.")
end

---3d model shown instead of the object's shape (model_name + use_model), nil for no model
---@param obj FileParserEnvObj
---@return string|false model path in mod_assets, false when the object uses no model
local function getModel(obj)
    if obj.props.use_model ~= "1" then return false end
    return ModData.fromModelName(obj.props.model_name, MGE.modPath) or obj.props.model_name or false
end

---Sets model_name / use_model on the selected objects, needs a reload
---@param model string? model path in mod_assets without .obj, nil turns the model off
local function setModel(model)
    local changed = false
    for _, v in ipairs(getSelected()) do
        local useModel = model and "1" or "0"
        local modelName = model and ModData.toModelName(model) or v.props.model_name
        if v.props.use_model ~= useModel or v.props.model_name ~= modelName then
            v.props.use_model = useModel
            v.props.model_name = modelName -- kept when turning the model off, the game ignores it then
            changed = true
        end
    end
    if not changed then return end
    History.commit()
    MGE.save()
end

---Model row (advanced panel): the model button opens the picker, None turns the model off
---@param holder UIElement
---@param selected FileParserEnvObj[]
local function buildModel(holder, selected)
    totalHeight = 0
    local current = sharedChoice(selected, getModel)
    local row, contentX, contentW = createRow("Model", holder,
        "3d model drawn for selected objects instead of their shape, the shape\n" ..
        "still collides. Click the model to pick a .obj from data/mod_assets,\n" ..
        "a texture with the same name next to it is used too. None: no model.")
    local labels = { [false] = "Pick model", mixed = "Mixed" }
    local label = current == nil and "-" or labels[current] or tostring(current)
    local gap = 4
    local noneW = (contentW - 4 - gap) * 0.3
    local modelW = contentW - 4 - gap - noneW
    Widgets.button(row, { x = contentX + 2, y = 2, w = modelW, h = row.size.h - 4 }, label, function()
        if #getSelected() == 0 then return end
        MGE.ModelPicker.open(type(current) == "string" and current or nil, setModel)
    end, nil, Widgets.PANEL_STYLE)
    local none = Widgets.button(row, { x = contentX + 2 + modelW + gap, y = 2, w = noneW, h = row.size.h - 4 }, "None",
        function() setModel(nil) end, nil, Widgets.PANEL_STYLE)
    if current == false then none.bgColor = TB_MENU_DEFAULT_LIGHTER_COLOR end -- like the current choice
end

---Dynamic objects can end up above id 48 (the footer warns), this moves them down and static
---objects up, as far as ids allow. Acts on all objects, not the selection
local function reindex()
    local moved, left = ModData.reindex()
    if left > 0 then
        print("reindex: " .. left .. " dynamic objects still above id " .. MGE.MAX_NONSTATIC_OBJECTS ..
            ", make some static")
    end
    if moved == 0 then
        print("reindex: nothing to move")
        return
    end
    History.commit()
    MGE.save()
    print("reindex moved " .. moved .. " objects")
end

---Ids row (advanced panel), built once: its buttons act on all objects, nothing to refresh
---@param holder UIElement
local function buildIdRows(holder)
    totalHeight = 0
    createToggleButtonRow("Ids", holder, {
        { label = "Reindex", active = false, onClick = reindex },
    }, "Reindex: moves dynamic objects to ids 1-" .. MGE.MAX_NONSTATIC_OBJECTS ..
        " and static objects above them,\nas far as free ids allow. Acts on all objects, " ..
        "joints follow their objects.")
end

-- rebuilt blocks: builder and where they sit { panel, first row, rows }
local BLOCKS = {
    measured = { build = buildMeasuredRows, panel = "core", row = 0, rows = 3 },
    coreProps = { build = buildCoreProps, panel = "core", row = 3, rows = 2 },
    looks = { build = buildLooks, panel = "core", row = 5, rows = 2 },
    advancedProps = { build = buildAdvancedProps, panel = "advanced", row = 0, rows = 2 },
    flags = { build = buildFlags, panel = "advanced", row = 2, rows = 1 },
    model = { build = buildModel, panel = "advanced", row = 3, rows = 1 },
}
-- fixed build order (pairs() order isn't defined)
local BLOCK_ORDER = { "measured", "coreProps", "looks", "advancedProps", "flags", "model" }

-- input lists in inwuts: all of them are cleared by "Reset inputs", the rebuilt ones keep typed text
local ALL_INPUTS = { "pos", "rot", "scale", "position", "angle", "size", "color", "coreProps", "advancedProps" }
local REBUILT_INPUTS = { "position", "angle", "size", "color", "coreProps", "advancedProps" }

---Empties all input fields, placeholders show again
local function clearInputs()
    for _, key in ipairs(ALL_INPUTS) do
        for _, input in ipairs(inwuts[key] or {}) do
            if not input.destroyed then input:clearTextfield() end
        end
    end
end

---Text typed in the rebuilt input rows, kept over a rebuild
---@return table<string, string[]>
local function saveTypedProperties()
    local saved = {}
    for _, key in ipairs(REBUILT_INPUTS) do
        saved[key] = {}
        for i, input in ipairs(inwuts[key] or {}) do saved[key][i] = input.textfieldstr[1] end
    end
    return saved
end

---@param saved table<string, string[]>
local function restoreTypedProperties(saved)
    for key, texts in pairs(saved) do
        for i, input in ipairs(inwuts[key] or {}) do
            local text = texts[i]
            if text and text ~= "" then
                input.textfieldstr[1] = text
                input.textfieldindex = #text -- cursor at the end
            end
        end
    end
end

---Rebuilt input that has keyboard focus, as its inwuts key and index
---@return string? key, integer? index
local function findFocusedInput()
    for _, key in ipairs(REBUILT_INPUTS) do
        for i, input in ipairs(inwuts[key] or {}) do
            -- hide() doesn't clear keyboard, a field on a hidden tab isn't focused
            if input.keyboard and input.displayed and not input.destroyed then return key, i end
        end
    end
    return nil, nil
end

---Gives a text field keyboard focus, same as clicking it (UIElement.handleMouseDn)
---@param input UIElement
local function focusInput(input)
    for _, v in ipairs(UIKeyboardHandler) do v.keyboard = v.permanentListener end
    input.keyboard = true
    input:enableMenuKeyboard()
    disable_camera_movement()
end

---Rebuilds the named blocks with the current selection, typed text is kept and the field that had
---focus gets it back (applying a value with Enter rebuilds the rows, you can keep trying values)
---@param names string[]
local function rebuildBlocks(names)
    if not blocks.measured or blocks.measured.destroyed then return end
    local selected = getSelected() -- read once, every row shows values of the same objects
    local typed = saveTypedProperties()
    local focusKey, focusIndex = findFocusedInput()
    for _, name in ipairs(names) do
        Widgets.clearChildren(blocks[name])
        BLOCKS[name].build(blocks[name], selected)
    end
    restoreTypedProperties(typed)
    reapplyTabs()
    applyTransformModes() -- also when the editor isn't the shown tab (applyPanel isn't called then)

    ---@type UIElement?
    local refocus = focusKey and focusIndex and (inwuts[focusKey] or {})[focusIndex] or nil
    if refocus and not refocus.destroyed and refocus.displayed then focusInput(refocus) end
end

-- after a move / rotate / scale only the measured values change
refreshMeasured = function()
    rebuildBlocks({ "measured" })
end

refreshProperties = function()
    rebuildBlocks(BLOCK_ORDER)
end

---Called when the selection changes: refresh current values
function editor.onSelectionChanged()
    refreshProperties()
end

---@param parent UIElement editor container from ui/main.lua
function editor.create(parent)
    -- both panels start at the top of the editor area, each as tall as its rows
    panels = {}
    for id, panel in pairs(PANELS) do
        panels[id] = parent:addChild({
            pos = { 0, 0 },
            size = { parent.size.w, panel.rows * ROW_H },
        })
    end
    -- offset rows sit in the same slot as the measured (absolute) rows, applyTransformModes shows one
    transformRows = { move = {}, rotate = {}, scale = {} }
    buildTransformRows(panels.core:addChild({
        pos = { 0, 0 },
        size = { parent.size.w, 3 * ROW_H },
    }))
    buildIdRows(panels.advanced:addChild({
        pos = { 0, 4 * ROW_H },
        size = { parent.size.w, ROW_H },
    }))
    blocks = {}
    local selected = getSelected()
    for _, name in ipairs(BLOCK_ORDER) do
        local block = BLOCKS[name]
        blocks[name] = panels[block.panel]:addChild({
            pos = { 0, block.row * ROW_H },
            size = { parent.size.w, block.rows * ROW_H },
        })
        block.build(blocks[name], selected)
    end

    -- full width reset button under the input fields (it only clears inputs), same size as the
    -- window's Save as row. The Enter shortcut is explained in the window's shortcut help (ui/main.lua)
    inputFooter = parent:addChild({
        pos = { 0, 0 },
        size = { parent.size.w, ROW_H },
    })
    Widgets.buttonRow(inputFooter, 0, ROW_H, { { label = "Reset inputs", onClick = clearInputs } }, 0, nil, Widgets.PANEL_STYLE)
    -- Duplicate/Delete are in the object list's bottom bar (ui/obj_selector.lua), Save as in the
    -- bottom row (ui/main.lua). Positions and visibility are applied by Main.applyTab after create
end

-- used by the object list's Duplicate/Delete buttons
editor.duplicate = duplicate
editor.deleteSelected = onDeleteClick -- asks for confirmation first

MGE.Editor = editor
return editor
