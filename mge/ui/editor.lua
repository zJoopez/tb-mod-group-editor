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

local function vecLength(v)
    return math.sqrt(v[1] * v[1] + v[2] * v[2] + v[3] * v[3])
end

---Linear map that scales along the group frame axes: G * diag(scale) * G^T
---@param frame number[][] 3x3, columns are the group axes in world space
---@param scale number[]
---@return number[][]
local function groupScaleMatrix(frame, scale)
    return Mat3.mul(Mat3.mul(frame, { { scale[1], 0, 0 }, { 0, scale[2], 0 }, { 0, 0, scale[3] } }), Mat3.transpose(frame))
end

---New sides for an object scaled by the group map. Each local axis is scaled by how much the map
---stretches it; exact for objects aligned with the group, closest box fit for tilted ones.
---@param id integer 0-based object id
---@param sides number[]
---@param map number[][]
---@return number[]
local function scaleSides(id, sides, map)
    local axes = getLocalAxes(id)
    local f = {}
    for i = 1, 3 do f[i] = vecLength(Mat3.apply(map, axes[i])) end

    local out
    local shape = get_obj_shape(id)
    if shape == SHAPE.SPHERE then -- x radius
        local r = sides[1] * (f[1] + f[2] + f[3]) / 3
        out = { r, r, r }
    elseif shape == SHAPE.CAPSULE then -- x radius, y length along local z
        out = { sides[1] * (f[1] + f[2]) / 2, sides[2] * f[3], sides[3] }
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

---Scales the objects (sides and spacing) around their center by factors along the group's axes
---@param selectedObjects FileParserEnvObj[]
---@param scale number[] x y z factors
local function scaleBy(selectedObjects, scale)
    local pivot = { getSelectionPivot(selectedObjects) }

    -- scale along the group's own axes (world axes if never rotated by MGE), as if scaled before rotating
    local map = groupScaleMatrix(pickGroupFrame(selectedObjects), scale)
    local function scalePos(x, y, z)
        local rel = Mat3.apply(map, { x - pivot[1], y - pivot[2], z - pivot[3] })
        return pivot[1] + rel[1], pivot[2] + rel[2], pivot[3] + rel[3]
    end

    for _, v in ipairs(selectedObjects) do
        local outPos = { scalePos(get_obj_pos(v.id - 1)) }
        local outSides = scaleSides(v.id - 1, { get_obj_sides(v.id - 1) }, map)

        set_obj_pos(v.id - 1, outPos[1], outPos[2], outPos[3])
        set_obj_sides(v.id - 1, outSides[1], outSides[2], outSides[3])

        writeVectorProperty(v, "pos", outPos)
        writeVectorProperty(v, "sides", outSides)
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
---@return number[] extents x y z, 0 when nothing is in the world
local function groupExtents(selectedObjects)
    local axes = frameAxes(pickGroupFrame(selectedObjects))
    local min, max = { math.huge, math.huge, math.huge }, { -math.huge, -math.huge, -math.huge }
    for _, v in ipairs(selectedObjects) do
        local id = v.id - 1
        local x, y, z = get_obj_pos(id)
        if x then
            local sx, sy, sz = get_obj_sides(id)
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

---Size row: scales the selection so its overall size along the group's X, Y or Z becomes the typed
---value. Axes left empty (or 0 and below) don't change
---@param only integer? axis input Enter was pressed in, nil applies all
local function sizeSelected(only)
    local selectedObjects = getSelected()
    if #selectedObjects == 0 then return end
    local typed = readInputs(inwuts.size, only)
    local extents = groupExtents(selectedObjects)
    local scale, changed = {}, false
    for i = 1, 3 do
        if typed[i] and typed[i] > 0 and extents[i] > 1e-9 then
            scale[i], changed = typed[i] / extents[i], true
        else
            scale[i] = 1
        end
    end
    if changed then scaleBy(selectedObjects, scale) end
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
local PROPERTIES = {
    mass = { min = 0.0001, setter = function(id, v) set_obj_mass(id, v) end, getter = function(id) return get_obj_mass(id) end }, -- zero mass breaks physics
    friction = { min = 0 },
    bounce = { min = 0, setter = function(id, v) set_obj_bounce(id, v) end, getter = function(id) return get_obj_bounce(id) end },
}

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
        v.props[key] = FileHandler.formatNumber(value)
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

---Number shared by the objects as text, "-" for objects without it, "mixed" when they differ
---@param objects FileParserEnvObj[]
---@param read fun(obj: FileParserEnvObj): number?
---@return string?
local function sharedValue(objects, read)
    return sharedChoice(objects, function(obj)
        local v = read(obj)
        return v and FileHandler.formatNumber(v) or "-"
    end)
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
---@return UIElement row, number contentX, number contentW
local function createRow(label, parent, help)
    local row = parent:addChild({
        pos = { 0, totalHeight },
        size = { parent.size.w, 30 },
        interactive = true,
    }, true)

    local labelW = 80
    local helpSize = 22
    local helpW = help and helpSize + 8 or 0 -- space reserved at the end of the row for the "?" icon
    local labelContainer = row:addChild({
        pos = { 0, 0 },
        size = { labelW, row.size.h },
    }, true)
    labelContainer:addAdaptedText(label, nil, nil, nil, CENTERMID, 0.7, nil, nil)

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
---@return UIElement[]
local function createInputRow(label, parent, func, placeholders, help)
    local row, contentX, contentW = createRow(label, parent, help)
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
    return inputs
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
    -- pick each copy's id pool and count them first, so it either copies everything or nothing
    local pools = {}
    local need = { static = 0, nonStatic = 0 }
    for i, obj in ipairs(selected) do
        pools[i] = ModData.idPool(obj, true)
        need[pools[i]] = need[pools[i]] + 1
    end
    if not Joints.haveRoom(Joints.countLinked(ModData.parsed.env_obj_joint, Joints.idSet(selected))) then return end
    -- static objects on dynamic ids are moved up only if the copies need their ids
    if need.static > #ModData.freeIds.static
        or not ModData.freeDynamicIds(need.nonStatic, { reserveStatic = need.static }) then
        print("Not enough objects available")
        return
    end

    local idMap = {} -- original id -> copy id, used to copy joints between duplicated objects
    for i, obj in ipairs(selected) do
        local copy = ModData.copy(obj)
        copy.id = table.remove(ModData.freeIds[pools[i]], 1)
        copy.props = ModData.copy(obj.props) -- don't share props with the original
        -- the game flag is read by id, a copy without a flag line could get a different default
        -- (objects moved by freeDynamicIds already have their flag written)
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
            table.insert(ModData.freeIds[ModData.idPool(obj, true)], obj.id)
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

-- Shape, static/dynamic and visibility. The game reads them when the mod loads, so they're saved
-- instead of set live (undo restores them the same way).

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
---next save. Not for the static bit, that one can move ids (setStatic)
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

---Makes selected objects static or dynamic. Dynamic objects need ids 1-48: objects above that get a
---free low id, static objects are moved off low ids if there aren't enough (ModData.freeDynamicIds).
---New static objects move above 48 when a free id exists, so they don't hold a dynamic id.
---Joints follow the new ids. Nothing changes if there aren't enough ids.
---@param static boolean
local function setStatic(static)
    local freeIds = ModData.freeIds
    local MAX = MGE.MAX_NONSTATIC_OBJECTS
    local toChange = {}
    local keep = {} -- objects being changed must not be moved by freeDynamicIds
    local needIds = 0
    for _, v in ipairs(getSelected()) do
        if ModData.isStatic(v, true) ~= static then
            table.insert(toChange, v)
            keep[v.id] = true
            if not static and v.id > MAX then needIds = needIds + 1 end
        end
    end
    if #toChange == 0 then return end
    if not static and not ModData.freeDynamicIds(needIds, { keep = keep }) then
        print("Not enough dynamic object ids: " .. needIds .. " needed, " .. #freeIds.nonStatic .. " free")
        return
    end

    local idMap = {} -- old id -> new id
    local function moveTo(v, pool, releaseTo)
        local newId = table.remove(pool, 1)
        table.insert(releaseTo, v.id)
        idMap[v.id] = newId
        v.id = newId
    end
    for _, v in ipairs(toChange) do
        v.props.flag = tostring(withBits(getFlag(v), MGE.FLAGS.STATIC, static)) -- other flags are kept
        if not static and v.id > MAX then
            moveTo(v, freeIds.nonStatic, freeIds.static)
        elseif static and v.id <= MAX and #freeIds.static > 0 and not ModData.jointIds[v.id] then
            moveTo(v, freeIds.static, freeIds.nonStatic)
        end
    end
    table.sort(freeIds.static)
    table.sort(freeIds.nonStatic)
    for _, joint in ipairs(ModData.parsed.env_obj_joint) do
        joint.obj1 = idMap[joint.obj1] or joint.obj1
        joint.obj2 = idMap[joint.obj2] or joint.obj2
    end
    ModData.sortObjects()
    History.commit()
    MGE.save()
end

-- Two panels sharing the editor area, picked by the window's tab row (Main.applyTab -> editor.applyPanel):
--   core:     whole group and look: Pos, Angle, Size, Color, Mass, Shape, Visible
--   advanced: offsets and physics: Move, Rotate, Scale, Friction, Bounce, Flags
-- Both have input fields, the reset button is shown under either.
-- Every block of rows has its own holder. Move/Rotate/Scale are built once (typed values stay), the
-- other blocks are rebuilt when the selection or the objects change, so their placeholders /
-- highlights show current values (typed text is carried over the rebuild).
local ROW_H = 30
local PANELS = {
    core = { rows = 7 },
    advanced = { rows = 6 },
}
---@type table<string, UIElement>
local panels = {}
---@type table<string, UIElement> rebuilt blocks: measured, coreProps, looks, advancedProps, flags
local blocks = {}
---@type UIElement? reset button, shown under the shown panel
local inputFooter = nil

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
    if inputFooter and not inputFooter.destroyed then
        inputFooter:show(true)
        inputFooter:moveTo(nil, panel.rows * ROW_H + 8)
    end
end

---Rebuilt children are visible by default, let the window re-apply which tab/panel is shown
local function reapplyTabs()
    if MGE.Main and MGE.Main.applyTab then MGE.Main.applyTab() end
end

---Move/Rotate/Scale rows (offsets, advanced panel), built once so typed values stay when the selection changes
---@param holder UIElement
local function buildTransformRows(holder)
    totalHeight = 0
    local zeros = { "0.00", "0.00", "0.00" }
    -- Enter applies only the field it's pressed in (index i), the row's other fields are ignored
    inwuts.pos = createInputRow("Move", holder, function(_, i) moveSelected(i) end, zeros,
        "Moves selected objects along X, Y or Z.\nEnter applies the field you typed in.")
    inwuts.rot = createInputRow("Rotate", holder, function(_, i) rotSelected(i) end, zeros,
        "Rotates selected objects around their center\nby X, Y or Z degrees. Enter applies the field you typed in.")
    inwuts.scale = createInputRow("Scale", holder, function(_, i) scaleSelected(i) end, zeros,
        "Multiplies size and spacing of selected objects\nalong the group's X, Y or Z. 0 means no change.\nEnter applies the field you typed in.")
end

---@param values number[]
---@return string[]
local function formatHints(values)
    local hints = {}
    for i = 1, 3 do hints[i] = string.format("%.2f", values[i]) end
    return hints
end

---Pos / Angle / Size rows, the whole-group versions of Move / Rotate / Scale. Placeholders show the
---selection's current center, orientation (degrees) and size ("0.00" without a selection)
---@param holder UIElement
---@param selected FileParserEnvObj[]
local function buildMeasuredRows(holder, selected)
    totalHeight = 0
    local zeros = { "0.00", "0.00", "0.00" }
    local any = #selected > 0
    inwuts.position = createInputRow("Pos", holder, function(_, i) positionSelected(i) end,
        any and formatHints({ getSelectionPivot(selected) }) or zeros,
        "Moves selected objects so their center is at X, Y or Z.\nShows the current center. Enter applies the field you typed in.")
    local angles = any and groupAngles(selected) or { 0, 0, 0 }
    for i = 1, 3 do angles[i] = math.deg(angles[i]) end
    inwuts.angle = createInputRow("Angle", holder, function(_, i) angleSelected(i) end, formatHints(angles),
        "Turns selected objects as a group to X, Y or Z degrees.\nShows the group's current angles. Only rotations done\nin MGE are known, others count as 0. Enter applies the field you typed in.")
    inwuts.size = createInputRow("Size", holder, function(_, i) sizeSelected(i) end,
        any and formatHints(groupExtents(selected)) or zeros,
        "Scales selected objects so the group is X, Y or Z long\n(along the group's axes, like Scale). Shows the current size.\nEnter applies the field you typed in.")
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
        local property = PROPERTIES[key]
        local hint = sharedValue(selected, function(obj)
            if property.getter then return property.getter(obj.id - 1) end
            return tonumber(obj.props[key])
        end) or "0.00"
        if hint == "-" then hint = "0.00" end -- selected objects without the property in the file
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
        { label = "Cylinder", value = "cylinder" },
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
        "Static: stays in place, otherwise the object is dynamic. Dynamic objects\nneed ids 1-" ..
        MGE.MAX_NONSTATIC_OBJECTS .. ", higher ids get a free low id.\nWeapon: the object acts as a weapon.\n" ..
        "Nogrip: players can't grab the object.")
end

-- rebuilt blocks: builder and where they sit { panel, first row, rows }
local BLOCKS = {
    measured = { build = buildMeasuredRows, panel = "core", row = 0, rows = 3 },
    coreProps = { build = buildCoreProps, panel = "core", row = 3, rows = 2 },
    looks = { build = buildLooks, panel = "core", row = 5, rows = 2 },
    advancedProps = { build = buildAdvancedProps, panel = "advanced", row = 3, rows = 2 },
    flags = { build = buildFlags, panel = "advanced", row = 5, rows = 1 },
}
-- fixed build order (pairs() order isn't defined)
local BLOCK_ORDER = { "measured", "coreProps", "looks", "advancedProps", "flags" }

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

---Rebuilds the named blocks with the current selection, typed text is kept
---@param names string[]
local function rebuildBlocks(names)
    if not blocks.measured or blocks.measured.destroyed then return end
    local selected = getSelected() -- read once, every row shows values of the same objects
    local typed = saveTypedProperties()
    for _, name in ipairs(names) do
        Widgets.clearChildren(blocks[name])
        BLOCKS[name].build(blocks[name], selected)
    end
    restoreTypedProperties(typed)
    reapplyTabs()
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
    buildTransformRows(panels.advanced:addChild({
        pos = { 0, 0 },
        size = { parent.size.w, 3 * ROW_H },
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
