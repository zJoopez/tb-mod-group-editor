-- Core tab: Pos, Rot, Scale (math in utils/transforms.lua), Color, Mass, Shape, Visible, and
-- Atmo: To atmo (Objects list) / To objects and Save atmo (Atmo list).
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

-- a transform field applies only itself (only = its index): the row's other fields are left as they are
local function positionSelected(only) Transforms.positionTo(readInputs(inwuts.position, only)) end
local function angleSelected(only) Transforms.angleTo(readInputs(inwuts.angle, only)) end
local function sizeSelected(only) Transforms.sizeTo(readInputs(inwuts.size, only)) end
local shownPosition, groupAngles, groupExtents = Transforms.shownPosition, Transforms.groupAngles, Transforms.groupExtents

---@type table<string, UIElement> the Pos / Rot / Scale names by gizmo tool, rebuilt with the rows
local transformLabels = {}

---Lights the name of the row that belongs to the active gizmo tool (toolbar, Alt + Q / W / E)
local function highlightTransformLabels()
    for mode, label in pairs(transformLabels) do Rows.setHighlighted(label, mode == MGE.Gizmo.mode) end
end
table.insert(MGE.Gizmo.modeListeners, highlightTransformLabels)

---Pos / Rot / Scale rows: the group ends up at the typed values. Placeholders show the selection's current
---center, orientation (degrees) and size ("0.00" without a selection). Small steps: the mouse wheel. The name
---of the active gizmo tool's row is lit
---@param holder UIElement
---@param selected FileParserEnvObj[]
local function buildMeasuredRows(holder, selected)
    Rows.begin()
    local zeros = { "0.00", "0.00", "0.00" }
    local any = #selected > 0
    local _
    inwuts.position, _, transformLabels.move = createInputRow("Pos", holder, function(_, i) positionSelected(i) end,
        any and formatHints(shownPosition(selected)) or zeros,
        "Moves the selection's center to X, Y, Z.")
    local angles = any and groupAngles(selected) or { 0, 0, 0 }
    for i = 1, 3 do angles[i] = math.deg(angles[i]) end
    inwuts.angle, _, transformLabels.rotate = createInputRow("Rot", holder, function(_, i) angleSelected(i) end,
        formatHints(angles),
        "Turns the selection to the angles (degrees).")
    inwuts.size, _, transformLabels.scale = createInputRow("Scale", holder, function(_, i) sizeSelected(i) end,
        any and formatHints(groupExtents(selected)) or zeros,
        "Sets the selection's size along its axes.")
    highlightTransformLabels()
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

---Pick from world (the color picker's button): the next object clicked in the world gives the selection
---its exact color, all four channels. The Color name or Esc cancels (MGE.closeTopOverlay)
local function pickFromWorld()
    MGE.WorldSelect.startPick(function(source)
        local color = colorUnits(source)
        -- the objects selected now: the selection may have changed in the list meanwhile
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

---The Color row's name: the color picker (ui/color_picker.lua), starting from the first selected object's
---color. Apply gives every selected object that color. While a pick from the world runs: cancels it
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
            local now = getSelected() -- the objects selected now
            if #now == 0 then return end
            setColors(now, function() return color end)
        end,
        onPickWorld = pickFromWorld,
    })
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
        "RGBA 0-255 (up to 500 is brighter). A typed field\napplies when you leave it, empty ones keep each own.\n" ..
        "\"mixed\": the selected objects differ.\nName click: color picker, or pick from an object in the world.",
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


---Atmo row (the Core tab's last): moving between the lists. On the Objects list To atmo (the selected objects
---into the atmo), on the Atmo list To objects and Save atmo (the mod's .atmo now, without saving the mod).
---Rebuilt with the list it's on (utils/atmo_layer.lua)
---@param holder UIElement
local function buildLayerRow(holder)
    if atmoShown() then
        Rows.createToggleButtonRow("Atmo", holder, {
            { label = "To objects", active = false, onClick = function() MGE.AtmoLayer.toObjects() end },
            { label = "Save atmo", active = false, onClick = function() MGE.AtmoLayer.exportAtmo() end },
        }, "To objects: the selected ones back into the game as\nobjects, as many as there are free ids.\n" ..
            "Save atmo: writes data/atmospheres/MGE - <mod>.atmo\nnow, without saving the mod (Save does both).")
    else
        Rows.createToggleButtonRow("Atmo", holder, {
            { label = "To atmo", active = false, onClick = function() MGE.AtmoLayer.toAtmo() end },
        }, "The selected objects leave the game (ids freed) and\n" ..
            "join the atmo (the Atmo list): drawn only, no collisions.\n" ..
            "Save keeps them in data/atmospheres/MGE - <mod>.atmo,\n" ..
            "players load it in Shaders & Atmos > Atmos.\n" ..
            "Objects joined by joints stay.")
    end
end

---Color, Mass, Shape, Visible and the Atmo row as one block: rows stack, so the ones atmos don't have
---(Mass, Visible) leave no gap on the Atmo list
---@param holder UIElement
---@param selected FileParserEnvObj[]
local function buildCoreRest(holder, selected)
    buildCoreProps(holder, selected) -- starts the rows (Rows.begin)
    buildLooks(holder, selected)
    buildLayerRow(holder)
end

---@type EditorPanelModule
return {
    blocks = {
        { name = "measured", build = buildMeasuredRows, panel = "core", row = 0, rows = 3 },
        { name = "coreProps", build = buildCoreRest, panel = "core", row = 3, rows = 5 },
    },
    inputs = { rebuilt = { "position", "angle", "size", "color", "coreProps" } },
}
