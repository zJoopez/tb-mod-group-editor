require("toriui.uielement3d") -- Utils3D.MatrixToMatrixTB

local container = {}
local RotatingOld = dofile(MGE.scriptPath .. "utils/rotating.lua")
local ModData = MGE.ModData
local History = MGE.History
local Joints = MGE.Joints
local Mat3 = MGE.Mat3

local totalHeight = 0
local margin = 10

---@type table<string, UIElement[]>
local inwuts = {}

local function getSelectedObjects()
    local selected = {}
    for _, obj in ipairs(ModData.parsed.env_obj) do
        if obj.selected then
            table.insert(selected, obj)
        end
    end
    return selected
end
local function updateContentHeight(height)
    totalHeight = totalHeight + height
end

local function formatStrArr(arr)
    for index, value in ipairs(arr) do
        arr[index] = MGE.FileHandler.formatNumber(value)
    end
    return arr
end

local function readNumberInputs(inputs)
    local values = {}
    for i, input in ipairs(inputs) do
        values[i] = tonumber(input.textfieldstr[1]) or 0
    end
    return values
end

local function writeVectorProperty(obj, key, values)
    local formatted = formatStrArr(values)
    obj.props[key] = table.concat(formatted, " ")
    return formatted
end

---@param selectedObjects EnvObject[]
---@return number, number, number
local function getSelectionPivot(selectedObjects)
    local total = #selectedObjects
    if total == 0 then return 0, 0, 0 end

    local sumX, sumY, sumZ = 0, 0, 0
    for _, obj in ipairs(selectedObjects) do
        local pos = { get_obj_pos(obj.id - 1) }
        sumX = sumX + pos[1]
        sumY = sumY + pos[2]
        sumZ = sumZ + pos[3]
    end

    return sumX / total, sumY / total, sumZ / total
end

local function moveSelected()
    local offsets = readNumberInputs(inwuts.pos)

    local selectedObjects = getSelectedObjects()
    if #selectedObjects == 0 then return end

    for _, v in ipairs(selectedObjects) do
        local x, y, z = get_obj_pos(v.id - 1)
        local pos = { x + offsets[1], y + offsets[2], z + offsets[3] }
        set_obj_pos(v.id - 1, pos[1], pos[2], pos[3])
        writeVectorProperty(v, "pos", pos)
    end
    local linked = Joints.getLinked(Joints.idSet(selectedObjects))
    for _, joint in ipairs(linked) do
        Joints.transformPos(joint, function(x, y, z)
            return x + offsets[1], y + offsets[2], z + offsets[3]
        end)
    end

    set_camera_mode(4)
    MGE.cameraChanged = true -- restored on quit
    set_camera_lookat(getSelectionPivot(selectedObjects))
    History.commit()
    -- joints can't be moved live, save so they match the objects right away
    if #linked > 0 then MGE.save() end
end

local function rotSelected()
    local selectedObjects = getSelectedObjects()
    if #selectedObjects == 0 then return end

    local pivot = { getSelectionPivot(selectedObjects) }
    local offsets = {}
    for i, input in ipairs(inwuts.rot) do
        offsets[i] = math.rad(tonumber(input.textfieldstr[1]) or 0)
    end

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
    local linked = Joints.getLinked(Joints.idSet(selectedObjects))
    for _, joint in ipairs(linked) do
        Joints.transformPos(joint, function(x, y, z)
            local p = RotatingOld.SetRotPos(x, y, z, pivot[1], pivot[2], pivot[3], offsets[1], offsets[2], offsets[3])
            return p[1], p[2], p[3]
        end)
        Joints.transformAxis(joint, function(x, y, z)
            local a = RotatingOld.SetRotPos(x, y, z, 0, 0, 0, offsets[1], offsets[2], offsets[3])
            return a[1], a[2], a[3]
        end)
    end
    History.commit()
    -- joints can't be moved live, save so they match the objects right away
    if #linked > 0 then MGE.save() end
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
    if shape == MGE.SHAPE.SPHERE - 1 then -- x radius
        local r = sides[1] * (f[1] + f[2] + f[3]) / 3
        out = { r, r, r }
    elseif shape == MGE.SHAPE.CAPSULE - 1 then -- x radius, y length along local z
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

local function scaleSelected()
    local selectedObjects = getSelectedObjects()
    if #selectedObjects == 0 then return end

    local pivot = { getSelectionPivot(selectedObjects) }
    local scale = {}
    for i, input in ipairs(inwuts.scale) do
        local value = tonumber(input.textfieldstr[1]) or 0
        if value == 0 or value == -1 then
            scale[i] = 1
        else
            scale[i] = value
        end
    end

    -- scale along the group's own axes (world axes if never rotated by MGE), as if scaled before rotating
    local map = groupScaleMatrix(pickGroupFrame(selectedObjects), scale)

    for _, v in ipairs(selectedObjects) do
        local sides = { get_obj_sides(v.id - 1) }
        local pos = { get_obj_pos(v.id - 1) }

        local rel = Mat3.apply(map, { pos[1] - pivot[1], pos[2] - pivot[2], pos[3] - pivot[3] })
        local outPos = { pivot[1] + rel[1], pivot[2] + rel[2], pivot[3] + rel[3] }
        local outSides = scaleSides(v.id - 1, sides, map)

        set_obj_pos(v.id - 1, outPos[1], outPos[2], outPos[3])
        set_obj_sides(v.id - 1, outSides[1], outSides[2], outSides[3])

        writeVectorProperty(v, "pos", outPos)
        writeVectorProperty(v, "sides", outSides)
    end
    local linked = Joints.getLinked(Joints.idSet(selectedObjects))
    for _, joint in ipairs(linked) do
        Joints.transformPos(joint, function(x, y, z)
            local rel = Mat3.apply(map, { x - pivot[1], y - pivot[2], z - pivot[3] })
            return pivot[1] + rel[1], pivot[2] + rel[2], pivot[3] + rel[3]
        end)
    end
    History.commit()
    -- joints can't be moved live, save so they match the objects right away
    if #linked > 0 then MGE.save() end
end

local function adjustColor()
    local selectedObjects = getSelectedObjects()
    if #selectedObjects == 0 then return end

    local color = {}
    for i, input in ipairs(inwuts.color) do
        local n = tonumber(input.textfieldstr[1]) or 0
        n = math.max(0, math.min(500, n))
        color[i] = n / 255
    end
    for _, v in ipairs(selectedObjects) do
        set_obj_color(v.id - 1, color[1], color[2], color[3], color[4])
        writeVectorProperty(v, "color", color)
    end
    History.commit()
end

local function createInput(container, onInputFunc)
    local input = TBMenu:spawnTextField2(container, nil, "",
        "0.00",
        {
            inputType = 2,
            textfield = true,
            returnKeyType = KEYBOARD_RETURN.SEND,
            isNumeric = true,
            allowDecimal = true,
            allowNegative = true,
            textAlign = CENTER,
        })
    input:addKeyboardHandlers(nil, function(key)
        if key ~= 13 then return end --enter
        onInputFunc()
    end)
    return input
end

---@param container UIElement
---@param inputCount integer
---@param defaultValue string[]?
local function createInputRow(label, container, inputCount, func, defaultValue) --todo margin as param?
    local width = 0
    local row = container:addChild({
        pos = { 0, totalHeight },
        size = { container.size.w, 30 },
        interactive = true,
    }, true)

    local columnCount = inputCount
    if label then columnCount = columnCount + 1 end
    local columnSize = row.size.w / columnCount
    local inputs = {}

    if label then
        local labelContainer = row:addChild({
            pos = { width, 0 },
            size = { columnSize, row.size.h },
        }, true)
        labelContainer:addAdaptedText(label, nil, nil, nil, CENTERMID, 0.8, nil, nil)
        width = width + columnSize
    end

    for i = 1, inputCount, 1 do
        local inputContainer = row:addChild({
            pos = { width, 0 },
            size = { columnSize, row.size.h },
            interactive = true,
        }, true)
        inputs[i] = createInput(inputContainer, func)
        if defaultValue then inputs[i].textfieldstr[1] = defaultValue[i] end
        width = width + columnSize
    end
    updateContentHeight(row.size.h)
    return inputs
end

---comment
---@param container UIElement
---@param funcs function[]
---@param names string[]
---@return table
local function createButtonRow(container, funcs, names)
    local row = container:addChild({
        pos = { 0, totalHeight },
        size = { container.size.w, 30 },
        interactive = true,
    }, true)

    local columnSize = row.size.w / #funcs
    local width = 0
    local btns = {}

    for i, value in ipairs(funcs) do
        local btn = row:addChild({
            pos = { width, 0 },
            size = { columnSize - margin, row.size.h },
            interactive = true,
            bgColor = TB_MENU_DEFAULT_DARKER_COLOR,
            hoverColor = TB_MENU_DEFAULT_LIGHTER_COLOR,
            pressedColor = TB_MENU_DEFAULT_DARKEST_COLOR
        }, true)
        btn:addMouseUpHandler(value)
        btn:addAdaptedText(names[i] or "")
        btns[i] = btn
        width = width + columnSize
    end

    updateContentHeight(row.size.h + margin)
    return btns
end

local function shallowCopy(t)
    local copy = {}
    for k, v in pairs(t) do copy[k] = v end
    return copy
end

local function duplicate()
    local taberu = ModData.parsed.env_obj
    local idMap = {} -- original id -> copy id, used to copy joints between duplicated objects
    for i = 1, #taberu do
        local obj = taberu[i]
        if obj and obj.selected then
            local freeIds
            if obj.props.flag ~= "0" and not ModData.jointIds[obj.id] then
                freeIds = ModData.freeIds.static
            else
                freeIds = ModData.freeIds.nonStatic
            end

            local newId = freeIds[1]
            if not newId then
                print("Not enough objects available")
                return
            end

            local copy = shallowCopy(obj)
            copy.id = newId
            copy.props = shallowCopy(obj.props) -- don't share props with the original
            table.insert(ModData.parsed.env_obj, copy)
            table.remove(freeIds, 1)
            idMap[obj.id] = newId
            obj.selected = false -- selection moves to the copies (copy keeps selected = true)
        end
    end
    Joints.copyLinked(Joints.getLinked(idMap), idMap)
    table.sort(taberu, function(a, b)
        return a.id < b.id
    end)
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
            if obj.props.flag ~= "0" and not ModData.jointIds[obj.id] then
                table.insert(ModData.freeIds.static, obj.id)
            else
                table.insert(ModData.freeIds.nonStatic, obj.id)
            end
        end
    end
    Joints.removeLinkedToAny(deleted) -- a joint can't point to a missing object
    History.commit()
    MGE.save()
end

local function export()
    dofile(MGE.scriptPath .. "ui/save_overlay.lua")
end

function container.create(container)
    totalHeight = 0
    inwuts.pos = createInputRow("Pos", container, 3, moveSelected)
    inwuts.rot = createInputRow("Rot", container, 3, rotSelected)
    inwuts.scale = createInputRow("Scale", container, 3, scaleSelected)
    updateContentHeight(margin)

    createInputRow("Color", container, 0, nil)
    inwuts.color = createInputRow(nil, container, 4, adjustColor, { "", "", "", "255" })
    updateContentHeight(margin)

    createButtonRow(container, { duplicate, delete }, { "Duplicate", "Delete" })
    createButtonRow(container, { MGE.save, export }, { "Save", "Export" })
end

return container
