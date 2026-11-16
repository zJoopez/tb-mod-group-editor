




local Rows = MGE.EditorRows
local ModData = MGE.ModData
local History = MGE.History
local SHAPE = MGE.SHAPE
local getSelected = ModData.getEditSelection


local function atmoShown() return MGE.Main ~= nil and MGE.Main.listTab == "atmo" end
local inwuts = Rows.inputs
local readInputs = Rows.readInputs
local sharedChoice = Rows.sharedChoice
local createInputRow = Rows.createInputRow
local createChoiceRow = Rows.createChoiceRow
local function refreshProperties() Rows.refreshProperties() end

local Transforms = MGE.Transforms


local function positionSelected(only) Transforms.positionTo(readInputs(inwuts.position, only)) end
local function angleSelected(only) Transforms.angleTo(readInputs(inwuts.angle, only)) end
local function sizeSelected(only) Transforms.sizeTo(readInputs(inwuts.size, only)) end
local shownPosition, groupAngles, groupExtents = Transforms.shownPosition, Transforms.groupAngles, Transforms.groupExtents


local transformLabels, highlightTransformLabels = Rows.gizmoLabels()






local function buildMeasuredRows(holder, selected)
    Rows.begin()
    local zeros = { 0, 0, 0 }
    local any = #selected > 0
    local _

    inwuts.position, _, transformLabels.move = createInputRow("Pos", holder, function(_, i) positionSelected(i) end,
        any and shownPosition(selected) or zeros,
        "Moves the selection's center to X, Y, Z.")
    local angles = any and groupAngles(selected) or { 0, 0, 0 }
    for i = 1, 3 do angles[i] = math.deg(angles[i]) end
    inwuts.angle, _, transformLabels.rotate = createInputRow("Rot", holder, function(_, i) angleSelected(i) end,
        angles, "Turns the selection to the angles (degrees).", nil, { angle = true })
    inwuts.size, _, transformLabels.scale = createInputRow("Scale", holder, function(_, i) sizeSelected(i) end,
        any and groupExtents(selected) or zeros,
        "Sets the selection's size along its axes.")
    highlightTransformLabels()
end



local COLOR_DEFAULTS = { 0, 0, 0, 255 }





local function colorUnits(obj)
    local c = {}
    for n in (obj.props.color or ""):gmatch("%S+") do c[#c + 1] = tonumber(n) end
    if #c < 4 and obj.kind ~= "atmo" then

        local ok, r, g, b, a = pcall(get_obj_color, obj.id - 1)
        if ok and type(r) == "table" then r, g, b, a = r[1], r[2], r[3], r[4] end
        if ok then c = { tonumber(r), tonumber(g), tonumber(b), tonumber(a) } end
    end
    local out = {}
    for i = 1, 4 do out[i] = c[i] or COLOR_DEFAULTS[i] / 255 end
    return out
end




local function colorOf(obj)
    local out = colorUnits(obj)
    for i = 1, 4 do out[i] = math.floor(out[i] * 255 + 0.5) end
    return out
end




local function setColors(objects, colorFor)
    for _, v in ipairs(objects) do
        local color = colorFor(v)
        if v.kind ~= "atmo" then set_obj_color(v.id - 1, color[1], color[2], color[3], color[4]) end
        Transforms.writeVector(v, "color", color)
    end
    History.commit()
    refreshProperties()
end



local function adjustColor()
    local selectedObjects = getSelected()
    if #selectedObjects == 0 then return end
    local typed = readInputs(inwuts.color)
    if not (typed[1] or typed[2] or typed[3] or typed[4]) then return end
    setColors(selectedObjects, function(v)
        local current, color = colorOf(v), {}
        for i = 1, 4 do

            color[i] = math.max(0, math.min(500, typed[i] or current[i])) / 255
        end
        return color
    end)
end


local colorLabel = nil



local function pickFromWorld()
    MGE.WorldSelect.startPick(function(source)
        local color = colorUnits(source)

        local now = getSelected()
        if #now == 0 then return end
        setColors(now, function() return color end)
        MGE.say(string.format("%d objects got object %d's color", #now, source.id))
    end, function()
        Rows.setHighlighted(colorLabel, false)
    end)
    Rows.setHighlighted(colorLabel, true)
    MGE.say("click an object: the selection gets its color (Esc cancels)")
end



local function pickColor()
    local WorldSelect = MGE.WorldSelect
    if WorldSelect.picking then
        WorldSelect.cancelPick()
        return
    end
    local targets = getSelected()
    if #targets == 0 then
        MGE.say("select the objects to color first")
        return
    end
    MGE.ColorPicker.open({
        color = colorUnits(targets[1]),
        onApply = function(color)
            local now = getSelected()
            if #now == 0 then return end
            setColors(now, function() return color end)
        end,
        onPickWorld = pickFromWorld,
    })
end





local function buildCoreProps(holder, selected)
    Rows.begin()
    local colors = {}
    for _, obj in ipairs(selected) do colors[obj] = colorOf(obj) end
    local colorHints = {}
    for i = 1, 4 do
        colorHints[i] = sharedChoice(selected, function(obj) return tostring(colors[obj][i]) end)
            or tostring(COLOR_DEFAULTS[i])
    end
    local _
    inwuts.color, _, colorLabel = createInputRow("Color", holder, function() adjustColor() end, colorHints,
        "RGBA 0-255 (up to 500: brighter), empty fields\nkeep each object's own. Click the name: color picker.",
        pickColor)
    Rows.setHighlighted(colorLabel, MGE.WorldSelect.picking ~= nil)

    inwuts.coreProps = atmoShown() and {} or Rows.buildPropertyRows(holder, selected, { { "Mass", "mass" } })
end






local SHAPE_FILE_NAMES = { [SHAPE.SPHERE] = "sphere", [SHAPE.BOX] = "box", [SHAPE.CAPSULE] = "cylinder" }



local function getShape(obj)
    local shape = obj.props.shape and obj.props.shape:lower()
    if shape == "capsule" then shape = "cylinder" end
    return shape or obj.kind ~= "atmo" and SHAPE_FILE_NAMES[get_obj_shape(obj.id - 1)] or "box"
end



local function isVisible(obj)
    local vis = tonumber(obj.props.visible)
    if vis == nil and obj.kind == "atmo" then return true end
    if vis == nil then
        local live = get_obj_vis(obj.id - 1)
        if type(live) == "boolean" then return live end
        vis = tonumber(live) or 1
    end
    return vis ~= 0
end



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




local function buildLooks(holder, selected)
    createChoiceRow("Shape", holder, {
        { label = "Box", value = "box" },
        { label = "Sphere", value = "sphere" },
        { label = "Pill", value = "cylinder" },
    }, sharedChoice(selected, getShape), function(shape) Rows.setSelectedProp("shape", shape) end,
        "Sides are kept, so the size may look different.")
    if atmoShown() then return end
    createChoiceRow("Visible", holder, {
        { label = "Shown", value = true },
        { label = "Hidden", value = false },
    }, sharedChoice(selected, isVisible), setVisible,
        "Hidden objects still collide.")
end






local function buildLayerRow(holder)
    if atmoShown() then
        Rows.createToggleButtonRow("Atmo", holder, {
            { label = "To objects", active = false, onClick = function() MGE.AtmoLayer.toObjects() end },
            { label = "Save atmo", active = false, onClick = function() MGE.AtmoLayer.exportAtmo() end },
        }, "To objects: back into the game (as many as ids are free).\n" ..
            "Save atmo: writes the atmo now, without the mod.")
    else
        Rows.createToggleButtonRow("Atmo", holder, {
            { label = "To atmo", active = false, onClick = function() MGE.AtmoLayer.toAtmo() end },
        }, "Moves the selection to the atmo: drawn only, no\ncollisions, ids freed. Objects with joints stay.")
    end
end





local function buildCoreRest(holder, selected)
    buildCoreProps(holder, selected)
    buildLooks(holder, selected)
    buildLayerRow(holder)
end


return {
    blocks = {
        { name = "measured", build = buildMeasuredRows, panel = "core", row = 0, rows = 3 },
        { name = "coreProps", build = buildCoreRest, panel = "core", row = 3, rows = 5 },
    },
    inputs = { rebuilt = { "position", "angle", "size", "color", "coreProps" } },
}
