require("toriui.uielement3d") -- Utils3D.MatrixToMatrixTB

local container = {}
local RotatingOld = dofile(MGE.scriptPath .. "utils/rotating.lua")
local ModData = MGE.ModData
local History = MGE.History
local Joints = MGE.Joints
local Mat3 = MGE.Mat3
local Widgets = MGE.Widgets

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
    local selectedObjects = getSelectedObjects()
    if #selectedObjects == 0 then return end

    local property = PROPERTIES[key]
    value = math.max(value, property.min)
    for _, v in ipairs(selectedObjects) do
        v.props[key] = MGE.FileHandler.formatNumber(value)
        if property.setter then property.setter(v.id - 1, value) end
    end
    History.commit()
    if property.setter then
        refreshProperties()
    else
        MGE.save() -- reload rebuilds the editor with the new value
    end
end

---Sets color on selected objects, empty fields keep each object's current component (values 0-255)
local function adjustColor()
    local selectedObjects = getSelectedObjects()
    if #selectedObjects == 0 then return end

    local typed = {}
    for i, input in ipairs(inwuts.color) do
        local n = tonumber(input.textfieldstr[1])
        typed[i] = n and math.max(0, math.min(500, n)) / 255 or nil
    end
    for _, v in ipairs(selectedObjects) do
        local current = get_obj_color(v.id - 1) or { 1, 1, 1, 1 }
        local color = {}
        for i = 1, 4 do color[i] = typed[i] or current[i] or 1 end
        set_obj_color(v.id - 1, color[1], color[2], color[3], color[4])
        writeVectorProperty(v, "color", color)
    end
    History.commit()
    refreshProperties()
end

---Value shared by all selected objects as text, "mixed" when they differ, nil when nothing is selected
---@param read fun(obj: FileParserEnvObj): number?
---@return string?
local function sharedValue(read)
    local value
    for _, obj in ipairs(getSelectedObjects()) do
        local v = read(obj)
        local text = v and MGE.FileHandler.formatNumber(v) or "-"
        if value == nil then
            value = text
        elseif value ~= text then
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
            textScale = 0.65, -- smaller than the default, matches the labels
        })
    input:addKeyboardHandlers(nil, function(key)
        if key ~= 13 then return end --enter
        onInputFunc()
    end)
    return input
end

---Label column followed by equally sized inputs and an optional "?" help icon at the end
---@param label string
---@param parent UIElement
---@param func fun(inputs: UIElement[], index: integer) called on enter
---@param placeholders string[] one per input
---@param help string? explanation shown when hovering the "?" icon
---@return UIElement[]
local function createInputRow(label, parent, func, placeholders, help)
    local row = parent:addChild({
        pos = { 0, totalHeight },
        size = { parent.size.w, 30 },
        interactive = true,
    }, true)

    local labelW = 80
    local helpSize = 22
    local helpW = help and helpSize + 8 or 0 -- space reserved at the end of the row for the "?" icon
    local columnSize = (row.size.w - labelW - helpW) / #placeholders
    local labelContainer = row:addChild({
        pos = { 0, 0 },
        size = { labelW, row.size.h },
    }, true)
    labelContainer:addAdaptedText(label, nil, nil, nil, CENTERMID, 0.7, nil, nil)

    local inputs = {}
    for i, placeholder in ipairs(placeholders) do
        local inputContainer = row:addChild({
            pos = { labelW + (i - 1) * columnSize, 0 },
            size = { columnSize, row.size.h },
            interactive = true,
        }, true)
        inputs[i] = createInput(inputContainer, function() func(inputs, i) end, placeholder)
    end

    if help then
        -- round "?" that shows a short explanation on hover, same style as the game's mods menu
        local helpHolder = row:addChild({
            pos = { -helpSize - 2, (row.size.h - helpSize) / 2 },
            size = { helpSize, helpSize },
            bgColor = TB_MENU_DEFAULT_DARKER_COLOR,
            hoverColor = TB_MENU_DEFAULT_DARKEST_COLOR,
            pressedColor = TB_MENU_DEFAULT_DARKEST_COLOR,
            interactive = true,
            shapeType = ROUNDED,
            rounded = helpSize,
        })
        local popup = TBMenu:displayHelpPopup(helpHolder, help)
        if popup then
            popup:moveTo(helpSize + 5, (helpSize - popup.size.h) / 2, true) -- right of the icon, outside the window
        end
    end

    updateContentHeight(row.size.h)
    return inputs
end

---Full width row of equal buttons at the current height
---@param parent UIElement
---@param buttons { label: string|fun(): string, onClick: function }[]
local function createButtonRow(parent, buttons)
    Widgets.buttonRow(parent, totalHeight, 30, buttons, margin)
    updateContentHeight(30 + margin)
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

---Asks for confirmation with Toribash's own popup (TBMenu:showConfirmationWindow) before deleting
local function onDeleteClick()
    local count = #getSelectedObjects()
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

-- Two panels sharing the editor area: Transform (move/rotate/scale) and Properties (color, mass,
-- friction, bounce). The window's tab row picks one through Main.applyTab -> container.applyPanel.
---@type table<string, UIElement>
local panels = {}
---@type UIElement
local propertiesPanel = nil

---Shows one editor panel, called by Main.applyTab
---@param id string "transform"|"properties"
function container.applyPanel(id)
    for panelId, panel in pairs(panels) do
        if not panel.destroyed then
            if panelId == id then panel:show(true) else panel:hide(true) end
        end
    end
end

---Rebuilt children are visible by default, let the window re-apply which tab/panel is shown
local function reapplyTabs()
    if MGE.Main and MGE.Main.applyTab then MGE.Main.applyTab() end
end

local function buildTransformPanel(panel)
    totalHeight = 0
    local zeros = { "0.00", "0.00", "0.00" }
    inwuts.pos = createInputRow("Move", panel, function() moveSelected() end, zeros,
        "Moves selected objects by X Y Z.\nEmpty fields count as 0.")
    inwuts.rot = createInputRow("Rotate", panel, function() rotSelected() end, zeros,
        "Rotates selected objects around their center\nby X Y Z degrees.")
    inwuts.scale = createInputRow("Scale", panel, function() scaleSelected() end, zeros,
        "Multiplies size and spacing of selected objects\nalong the group's X Y Z. Empty or 0 means no change.")
end

local function buildPropertiesPanel(panel)
    totalHeight = 0
    -- placeholders show the selection's current value ("mixed" if objects differ),
    -- or the expected input type without a selection
    local colorHints = {}
    for i = 1, 4 do
        colorHints[i] = sharedValue(function(obj)
            local c = get_obj_color(obj.id - 1)
            return c and c[i] and math.floor(c[i] * 255 + 0.5)
        end) or "0"
        if colorHints[i] == "mixed" or colorHints[i] == "-" then colorHints[i] = "0" end -- 4 narrow fields, "mixed" doesn't fit
    end
    inwuts.color = createInputRow("Color", panel, function() adjustColor() end, colorHints,
        "Red, green, blue and alpha (0-255).\nEmpty fields keep each object's current value.")

    local helpTexts = {
        mass = "Sets mass of selected objects.\nShows the current value, \"mixed\" if they differ.",
        friction = "Sets friction of selected objects.\nApplied by saving, the game can't change it live.",
        bounce = "Sets bounciness of selected objects.\nShows the current value, \"mixed\" if they differ.",
    }
    inwuts.properties = {} -- mass, friction, bounce inputs, cleared by "Reset inputs"
    for _, entry in ipairs({ { "Mass", "mass" }, { "Friction", "friction" }, { "Bounce", "bounce" } }) do
        local label, key = entry[1], entry[2]
        local property = PROPERTIES[key]
        local hint = sharedValue(function(obj)
            if property.getter then return property.getter(obj.id - 1) end
            return tonumber(obj.props[key])
        end) or "0.00"
        if hint == "-" then hint = "0.00" end -- selected objects without the property in the file
        local inputs = createInputRow(label, panel, function(inputs) setProperty(key, inputs[1]) end, { hint }, helpTexts[key])
        table.insert(inwuts.properties, inputs[1])
    end
end

---Empties all transform and property fields, placeholders show again
local function clearInputs()
    for _, key in ipairs({ "pos", "rot", "scale", "color", "properties" }) do
        for _, input in ipairs(inwuts[key] or {}) do
            if not input.destroyed then input:clearTextfield() end
        end
    end
end

refreshProperties = function()
    if not propertiesPanel or propertiesPanel.destroyed then return end
    propertiesPanel:kill(true)
    buildPropertiesPanel(propertiesPanel)
    reapplyTabs()
end

---Called when the selection changes: refresh current values
function container.onSelectionChanged()
    refreshProperties()
end

---@param parent UIElement editor container from ui/main.lua
function container.create(parent)
    -- both panels share the top of the editor area, Properties has 4 rows so it sets the height
    local panelY = 0
    local panelH = 30 * 4
    panels = {}
    for _, id in ipairs({ "transform", "properties" }) do
        panels[id] = parent:addChild({
            pos = { 0, panelY },
            size = { parent.size.w, panelH },
        })
    end
    buildTransformPanel(panels.transform)
    propertiesPanel = panels.properties
    buildPropertiesPanel(propertiesPanel)

    -- bottom of the input panels: hint on the left, reset button on the right (it only affects these fields)
    totalHeight = panelY + panelH + 4
    local footerH = 22
    local resetW = 110
    local hint = parent:addChild({
        pos = { 0, totalHeight },
        size = { parent.size.w - resetW - margin, footerH },
    })
    hint:addAdaptedText(true, "Enter applies the value to selected objects", nil, nil, FONTS.SMALL, LEFTMID, 0.6)
    Widgets.button(parent, { x = parent.size.w - resetW, y = totalHeight, w = resetW, h = footerH },
        "Reset inputs", clearInputs, 0.6)
    updateContentHeight(footerH + 8)

    createButtonRow(parent, {
        { label = "Duplicate", onClick = duplicate },
        { label = "Delete", onClick = onDeleteClick },
    })
    -- Save/Export live in the main window below the tab area so every tab has them (ui/main.lua)
    -- visibility is applied by Main.applyTab after create (initial build and Main.resetEditor)
end

return container
