-- Core tab: Pos/Move, Rot/Rotate, Scale/Resize (math in utils/transforms.lua), Color, Mass, Shape, Visible
local Rows = MGE.EditorRows
local ModData = MGE.ModData
local History = MGE.History
local SHAPE = MGE.SHAPE
local getSelected = ModData.getSelected
local inwuts = Rows.inputs
local readInputs = Rows.readInputs
local sharedChoice = Rows.sharedChoice
local formatHints = Rows.formatHints
local createInputRow = Rows.createInputRow
local createChoiceRow = Rows.createChoiceRow
local function refreshProperties() Rows.refreshProperties() end

local Transforms = MGE.Transforms

-- Enter in a transform field applies that field only (only = its index)
local function moveSelected(only) Transforms.move(readInputs(inwuts.pos, only)) end
local function rotSelected(only) Transforms.rotate(readInputs(inwuts.rot, only)) end
local function scaleSelected(only) Transforms.scale(readInputs(inwuts.scale, only)) end
local function positionSelected(only) Transforms.positionTo(readInputs(inwuts.position, only)) end
local function angleSelected(only) Transforms.angleTo(readInputs(inwuts.angle, only)) end
local function sizeSelected(only) Transforms.sizeTo(readInputs(inwuts.size, only)) end
local shownPosition, groupAngles, groupExtents = Transforms.shownPosition, Transforms.groupAngles, Transforms.groupExtents

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
---@param coreShown boolean the core panel is visible
local function applyTransformModes(coreShown)
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
    applyTransformModes(true) -- the label clicked is on the shown core panel
end

local SWITCH_HELP = "\nClick the name: "

---Move/Rotate/Resize rows (offset mode, core panel), built once so typed values stay when the selection changes
---@param holder UIElement
local function buildTransformRows(holder)
    Rows.begin()
    transformRows = { move = {}, rotate = {}, scale = {} } -- built before the measured rows
    local zeros = { "0.00", "0.00", "0.00" }
    local function switch(key) return function() toggleTransformMode(key) end end
    -- Enter applies only the field it's pressed in (index i), the row's other fields are ignored
    inwuts.pos, transformRows.move.offset = createInputRow("Move", holder, function(_, i) moveSelected(i) end, zeros,
        "Moves the selection by X, Y, Z." ..
        SWITCH_HELP .. "Pos (move to).", switch("move"))
    inwuts.rot, transformRows.rotate.offset = createInputRow("Rotate", holder, function(_, i) rotSelected(i) end, zeros,
        "Turns the selection around its center by degrees." ..
        SWITCH_HELP .. "Rot (turn to).", switch("rotate"))
    inwuts.scale, transformRows.scale.offset = createInputRow("Resize", holder, function(_, i) scaleSelected(i) end, zeros,
        "Multiplies the group's size along its axes. 0: no change." ..
        SWITCH_HELP .. "Scale (set size).", switch("scale"))
end

---Pos / Rot / Scale rows (absolute), the whole-group versions of Move / Rotate / Resize. Placeholders show the
---selection's current center, orientation (degrees) and size ("0.00" without a selection)
---@param holder UIElement
---@param selected FileParserEnvObj[]
local function buildMeasuredRows(holder, selected)
    Rows.begin()
    local zeros = { "0.00", "0.00", "0.00" }
    local any = #selected > 0
    local function switch(key) return function() toggleTransformMode(key) end end
    inwuts.position, transformRows.move.absolute = createInputRow("Pos", holder, function(_, i) positionSelected(i) end,
        any and formatHints(shownPosition(selected)) or zeros,
        "Moves selection to given location." ..
        SWITCH_HELP .. "Name click changes mode.", switch("move"))
    local angles = any and groupAngles(selected) or { 0, 0, 0 }
    for i = 1, 3 do angles[i] = math.deg(angles[i]) end
    inwuts.angle, transformRows.rotate.absolute = createInputRow("Rot", holder, function(_, i) angleSelected(i) end, formatHints(angles),
        "Turns selection to given angles." ..
        SWITCH_HELP .. "Name click changes mode.", switch("rotate"))
    inwuts.size, transformRows.scale.absolute = createInputRow("Scale", holder, function(_, i) sizeSelected(i) end,
        any and formatHints(groupExtents(selected)) or zeros,
        "Sets the selection's size." ..
        SWITCH_HELP .. "Name click changes mode.", switch("scale"))
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
        Transforms.writeVector(v, "color", { color[1], color[2], color[3], color[4] })
    end
    History.commit() -- no panel refresh needed, color placeholders don't depend on the selection
end

---Color and mass rows (core panel). Color placeholders show the defaults empty fields use
---@param holder UIElement
---@param selected FileParserEnvObj[]
local function buildCoreProps(holder, selected)
    Rows.begin()
    local colorHints = {}
    for i = 1, 4 do colorHints[i] = tostring(COLOR_DEFAULTS[i]) end
    inwuts.color = createInputRow("Color", holder, function() adjustColor() end, colorHints,
        "RGBA 0-255 (up to 500 is brighter).\nEnter applies all four, empty fields: 0 0 0 255.")
    inwuts.coreProps = Rows.buildPropertyRows(holder, selected, { { "Mass", "mass" } })
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

---Shape and visibility rows (core panel), the selection's current values are highlighted
---@param holder UIElement
---@param selected FileParserEnvObj[]
local function buildLooks(holder, selected)
    Rows.begin()
    createChoiceRow("Shape", holder, {
        { label = "Box", value = "box" },
        { label = "Sphere", value = "sphere" },
        { label = "Pill", value = "cylinder" }, -- "cylinder" in mod files, round ends in game
    }, sharedChoice(selected, getShape), function(shape) Rows.setSelectedProp("shape", shape) end,
        "Sides are kept, so the size may look different.")
    createChoiceRow("Visible", holder, {
        { label = "Shown", value = true },
        { label = "Hidden", value = false },
    }, sharedChoice(selected, isVisible), setVisible,
        "Hidden objects still collide.")
end


---@type EditorPanelModule
return {
    fixed = { { build = buildTransformRows, panel = "core", row = 0, rows = 3 } },
    blocks = {
        { name = "measured", build = buildMeasuredRows, panel = "core", row = 0, rows = 3 },
        { name = "coreProps", build = buildCoreProps, panel = "core", row = 3, rows = 2 },
        { name = "looks", build = buildLooks, panel = "core", row = 5, rows = 2 },
    },
    inputs = { fixed = { "pos", "rot", "scale" }, rebuilt = { "position", "angle", "size", "color", "coreProps" } },
    applyTransformModes = applyTransformModes,
}
