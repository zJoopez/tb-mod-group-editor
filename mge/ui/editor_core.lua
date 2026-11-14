-- Core tab: Pos/Move, Rot/Rotate, Scale/Resize (math in utils/transforms.lua), Color, Mass, Shape, Visible.
-- Also the Atmo list's Core tab: the same rows on the selected atmo objects (ModData.getEditSelection),
-- through their lines only (an atmo object's id isn't an object's). Mass and Visible aren't there: the
-- game's atmos have neither
local Rows = MGE.EditorRows
local ModData = MGE.ModData
local History = MGE.History
local SHAPE = MGE.SHAPE
local getSelected = ModData.getEditSelection

---@return boolean the Atmo list shows: its Core tab
local function atmoShown() return MGE.Main ~= nil and MGE.Main.listTab == "atmo" end
local inwuts = Rows.inputs
local readInputs = Rows.readInputs
local sharedChoice = Rows.sharedChoice
local formatHints = Rows.formatHints
local createInputRow = Rows.createInputRow
local createChoiceRow = Rows.createChoiceRow
local function refreshProperties() Rows.refreshProperties() end

local Transforms = MGE.Transforms
local Gizmo = MGE.Gizmo

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
---@type table<string, table<TransformMode, UIElement?>> name buttons of the transform rows, the one of the
---active tool is highlighted (both modes, only one is shown)
local transformLabels = { move = {}, rotate = {}, scale = {} }

---Highlights the transform row names that belong to the active gizmo tool (toolbar toggles, ui/main.lua).
---The rows themselves don't change the tool
local function highlightTransformLabels()
    for key, labels in pairs(transformLabels) do
        for _, label in pairs(labels) do Rows.setHighlighted(label, key == Gizmo.mode) end
    end
end
table.insert(Gizmo.modeListeners, highlightTransformLabels)

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
    transformLabels = { move = {}, rotate = {}, scale = {} }
    local zeros = { "0.00", "0.00", "0.00" }
    local function switch(key) return function() toggleTransformMode(key) end end
    -- Enter applies only the field it's pressed in (index i), the row's other fields are ignored
    inwuts.pos, transformRows.move.offset, transformLabels.move.offset = createInputRow("Move", holder,
        function(_, i) moveSelected(i) end, zeros,
        "Moves the selection by X, Y, Z." ..
        SWITCH_HELP .. "Pos (move to).", switch("move"))
    inwuts.rot, transformRows.rotate.offset, transformLabels.rotate.offset = createInputRow("Rotate", holder,
        function(_, i) rotSelected(i) end, zeros,
        "Turns the selection around its center by degrees." ..
        SWITCH_HELP .. "Rot (turn to).", switch("rotate"))
    inwuts.scale, transformRows.scale.offset, transformLabels.scale.offset = createInputRow("Resize", holder,
        function(_, i) scaleSelected(i) end, zeros,
        "Multiplies the group's size along its axes. 0: no change." ..
        SWITCH_HELP .. "Scale (set size).", switch("scale"))
    highlightTransformLabels()
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
    inwuts.position, transformRows.move.absolute, transformLabels.move.absolute = createInputRow("Pos", holder,
        function(_, i) positionSelected(i) end,
        any and formatHints(shownPosition(selected)) or zeros,
        "Moves selection to given location." ..
        SWITCH_HELP .. "Name click changes mode.", switch("move"))
    local angles = any and groupAngles(selected) or { 0, 0, 0 }
    for i = 1, 3 do angles[i] = math.deg(angles[i]) end
    inwuts.angle, transformRows.rotate.absolute, transformLabels.rotate.absolute = createInputRow("Rot", holder,
        function(_, i) angleSelected(i) end, formatHints(angles),
        "Turns selection to given angles." ..
        SWITCH_HELP .. "Name click changes mode.", switch("rotate"))
    inwuts.size, transformRows.scale.absolute, transformLabels.scale.absolute = createInputRow("Scale", holder,
        function(_, i) sizeSelected(i) end,
        any and formatHints(groupExtents(selected)) or zeros,
        "Sets the selection's size." ..
        SWITCH_HELP .. "Name click changes mode.", switch("scale"))
    highlightTransformLabels() -- rebuilt rows start with the panel look
end

-- an object's color when neither its file line nor the game has one (0-255), and the placeholders
-- without a selection
local COLOR_DEFAULTS = { 0, 0, 0, 255 }

---An object's color as the game takes it, r g b a (1 is 255): its file line (what MGE writes and
---saves), else the game's live color, else COLOR_DEFAULTS
---@param obj FileParserEnvObj
---@return number[]
local function colorUnits(obj)
    local c = {}
    for n in (obj.props.color or ""):gmatch("%S+") do c[#c + 1] = tonumber(n) end
    if #c < 4 and obj.kind ~= "atmo" then -- an atmo object has only its line
        -- a Color (number[] in toriui), or four numbers (pcall: not worth an error in the panel)
        local ok, r, g, b, a = pcall(get_obj_color, obj.id - 1)
        if ok and type(r) == "table" then r, g, b, a = r[1], r[2], r[3], r[4] end
        if ok then c = { tonumber(r), tonumber(g), tonumber(b), tonumber(a) } end
    end
    local out = {}
    for i = 1, 4 do out[i] = c[i] or COLOR_DEFAULTS[i] / 255 end
    return out
end

---An object's color as 0-255 r g b a, what the fields show
---@param obj FileParserEnvObj
---@return integer[]
local function colorOf(obj)
    local out = colorUnits(obj)
    for i = 1, 4 do out[i] = math.floor(out[i] * 255 + 0.5) end
    return out
end

---Gives each selected object a color (r g b a, 1 is 255): set live and written, one undo step
---@param objects FileParserEnvObj[]
---@param colorFor fun(obj: FileParserEnvObj): number[]
local function setColors(objects, colorFor)
    for _, v in ipairs(objects) do
        local color = colorFor(v)
        if v.kind ~= "atmo" then set_obj_color(v.id - 1, color[1], color[2], color[3], color[4]) end
        Transforms.writeVector(v, "color", color)
    end
    History.commit()
    refreshProperties() -- the placeholders show the new color
end

---Sets the channels typed in the color fields (r g b a, 0-255) on the selected objects; an empty field
---keeps each object's own value of that channel
local function adjustColor()
    local selectedObjects = getSelected()
    if #selectedObjects == 0 then return end
    local typed = readInputs(inwuts.color)
    if not (typed[1] or typed[2] or typed[3] or typed[4]) then return end
    setColors(selectedObjects, function(v)
        local current, color = colorOf(v), {}
        for i = 1, 4 do
            -- 255 is the official max, the game accepts up to 500 and draws those brighter
            color[i] = math.max(0, math.min(500, typed[i] or current[i])) / 255
        end
        return color
    end)
end

---@type UIElement? the Color row's name button, lit while picking (rebuilt with the panel)
local colorLabel = nil

---Color picker (the Color row's name): the next object clicked in the world gives the selection its
---exact color, all four channels. The name again or Esc cancels (MGE.closeTopOverlay)
local function pickColor()
    local WorldSelect = MGE.WorldSelect
    if WorldSelect.picking then
        WorldSelect.cancelPick()
        return
    end
    local targets = getSelected()
    if #targets == 0 then
        echo("^04[MGE] select the objects to color first, then pick")
        return
    end
    WorldSelect.startPick(function(source)
        local color = colorUnits(source)
        -- the objects selected now: the selection may have changed in the list meanwhile
        local now = getSelected()
        if #now == 0 then return end
        setColors(now, function() return color end)
        echo(string.format("^04[MGE] %d objects got object %d's color", #now, source.id))
    end, function()
        Rows.setHighlighted(colorLabel, false)
    end)
    Rows.setHighlighted(colorLabel, true)
    echo("^04[MGE] click an object: the selection gets its color (Esc cancels)")
end

---Color and mass rows (core panel). Placeholders show the selection's values per channel, "mixed"
---where the objects differ
---@param holder UIElement
---@param selected FileParserEnvObj[]
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
        "RGBA 0-255 (up to 500 is brighter). Enter applies\nthe typed fields, empty ones keep each object's own.\n" ..
        "\"mixed\": the selected objects differ.\nName click: pick a color from an object in the world.",
        pickColor)
    Rows.setHighlighted(colorLabel, MGE.WorldSelect.picking ~= nil) -- rebuilt while picking
    -- atmo objects have no mass
    inwuts.coreProps = atmoShown() and {} or Rows.buildPropertyRows(holder, selected, { { "Mass", "mass" } })
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
    if shape == "capsule" then shape = "cylinder" end -- the same pill (atmos write either)
    return shape or obj.kind ~= "atmo" and SHAPE_FILE_NAMES[get_obj_shape(obj.id - 1)] or "box"
end

---@param obj FileParserEnvObj
---@return boolean
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
    if atmoShown() then return end -- atmos have no visibility line (the Atmo tab has Graphics levels)
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
