-- Generate tab: lines, ramps, loops, stairs and pyramids made of default objects (geometry in utils/shape_gen.lua),
-- placed in front of the camera, or where the Position row says
local Rows = MGE.EditorRows
local inwuts = Rows.inputs
local formatHints = Rows.formatHints
local createInputRow = Rows.createInputRow
local createChoiceRow = Rows.createChoiceRow
local createToggleButtonRow = Rows.createToggleButtonRow

local Transforms = MGE.Transforms

-- used for empty Generate fields, shown as their placeholders
local GENERATE_AMOUNT = 8
local GENERATE_ANGLE = 90
local MAX_GENERATE = 200 -- more than any mod has room for, stops a typo from planning thousands

---@type GenerateAlign kept while the script runs
local align = "out"

---@return number[] sides of the default object (ui/assets.lua), what empty Size fields use
local function defaultSides()
    local sides = {}
    for v in MGE.Assets.defaultProps().sides:gmatch("%S+") do table.insert(sides, tonumber(v) or 0.5) end
    return sides
end

-- Where the shape goes: in front of the camera (Camera.spawnPoint), along the view line taken
-- when the tab opens or To view is clicked. Kept fixed in between so the camera can orbit around the
-- preview. A bigger shape moves further along the line, so it still fits on screen
---@type { origin: number[], dir: number[] }?
local anchor = nil
local anchorVersion = 0 -- part of the preview's key: a new view line plans the preview again

---Takes the camera's current view line as the place for the shape
local function anchorToView()
    local origin, dir = MGE.Camera.viewRay()
    anchor = { origin = origin, dir = dir }
    anchorVersion = anchorVersion + 1
end

---To view button: back to the automatic place, typed Position values are cleared too
local function toView()
    for _, input in ipairs(inwuts.generatePos or {}) do
        if not input.destroyed then input:clearTextfield() end
    end
    anchorToView()
end

---Center of the pieces, the way the Core tab's Pos row shows a selection: average of the positions
---@param pieces GeneratePiece[]
---@return number[]
local function piecesCenter(pieces)
    local c = { 0, 0, 0 }
    for _, piece in ipairs(pieces) do
        for k = 1, 3 do c[k] = c[k] + piece.pos[k] / #pieces end
    end
    return c
end

---Pieces for the typed values (empty fields use their placeholders), same for the preview and Generate.
---Placed in front of the camera, then moved on the axes typed in the Position row: those are the
---center the Pos row would show for the generated pieces, counted from the dojo center (MGE.POS_ORIGIN)
---@return GeneratePiece[]? pieces
---@return string? error why nothing can be generated
---@return number[]? center where the shape is, Pos-row style
local function planFromFields()
    local fields = inwuts.generate or {}
    local function typed(i) return fields[i] and not fields[i].destroyed and tonumber(fields[i].textfieldstr[1]) end
    local amount = math.floor((typed(1) or GENERATE_AMOUNT) + 0.5)
    if amount < 2 or amount > MAX_GENERATE then -- one piece is what the list's New button adds
        return nil, "amount must be 2-" .. MAX_GENERATE
    end
    local sides, increment = defaultSides(), {}
    for i = 1, 3 do
        local value = typed(3 + i)
        if value and value > 0 then sides[i] = math.max(value, MGE.MIN_SIDE) end
        increment[i] = typed(6 + i) or 0
    end
    local most = MGE.ShapeGen.maxPieces(sides, increment)
    if most and amount > most then
        return nil, "the increment shrinks pieces to nothing after " .. most .. " pieces, use fewer or a smaller increment"
    end
    local ShapeGen = MGE.ShapeGen
    local pieces, bounds = ShapeGen.plan(amount, typed(2) or 0, typed(3) or GENERATE_ANGLE, sides,
        { 0, 0 }, { increment = increment, align = align })
    if not anchor then anchorToView() end
    ---@cast anchor -nil
    ShapeGen.moveTo(pieces, bounds, MGE.Camera.spawnPoint(bounds, anchor.origin, anchor.dir))

    local center = piecesCenter(pieces)
    local shift, origin = { 0, 0, 0 }, MGE.POS_ORIGIN
    for k, input in ipairs(inwuts.generatePos or {}) do
        local value = not input.destroyed and tonumber(input.textfieldstr[1])
        if value then shift[k] = value + origin[k] - center[k] end
    end
    for _, piece in ipairs(pieces) do
        for k = 1, 3 do piece.pos[k] = piece.pos[k] + shift[k] end
    end
    local shown = {}
    for k = 1, 3 do shown[k] = center[k] + shift[k] - origin[k] end
    return pieces, nil, shown
end

-- Preview: the pieces Generate would add, drawn by utils/highlight.lua while the Generate tab is open.
-- Planned again only when a field's text, Align or the view line changes, the draw hook asks every frame
local previewKey, previewPieces
local previewShown = false -- false while the tab is closed, opening it takes the view line again
---@type string[] placeholders of the Position row: where the shape is, empty fields keep it there
local positionHints = { "0.00", "0.00", "0.00" }

---@return string everything the plan depends on
local function fieldsKey()
    ---@type string[]
    local parts = { align .. "#" .. anchorVersion }
    for _, list in ipairs({ inwuts.generate or {}, inwuts.generatePos or {} }) do
        for _, field in ipairs(list) do
            table.insert(parts, field.destroyed and "" or field.textfieldstr[1])
        end
    end
    return table.concat(parts, "|")
end

---Position row placeholders follow the planned shape (rebuilt block, typed text is kept over it)
---@param center number[]? Pos-row style center from planFromFields
local function showPosition(center)
    if not center then return end
    local hints = formatHints(center)
    if hints[1] == positionHints[1] and hints[2] == positionHints[2] and hints[3] == positionHints[3] then return end
    positionHints = hints
    Rows.refreshBlocks({ "generatePos" })
end

MGE.Highlight.preview = function()
    local Main = MGE.Main
    if Main.activeTab ~= "generate" or Main.listTab == "players" or not inwuts.generate then
        previewShown = false
        return nil
    end
    if not previewShown then -- the tab just opened: the shape goes where the camera looks now
        previewShown = true
        anchorToView()
    end
    local key = fieldsKey()
    if key ~= previewKey then
        previewKey = key
        local center
        previewPieces, _, center = planFromFields() -- nil when the values can't be generated, nothing is drawn
        showPosition(center)
    end
    return previewPieces
end

---Generate button / Enter: adds the shape, made of the default object made static
local function generate()
    local pieces, err = planFromFields()
    if not pieces then
        print("Generate: " .. err)
        return
    end

    local objects = {}
    for i, piece in ipairs(pieces) do
        local obj = { kind = "env_obj", id = i, props = MGE.Assets.defaultProps() }
        obj.props.flag = tostring(MGE.FLAGS.STATIC) -- a ramp stays in place, and static ids are plenty
        Transforms.writeVector(obj, "pos", piece.pos)
        Transforms.writeVector(obj, "rot", piece.rot)
        Transforms.writeVector(obj, "sides", piece.sides)
        objects[i] = obj
    end
    -- selected and saved like an import, the tab stays so values can be tried again after Undo
    MGE.Assets.addObjects(objects, true)
    -- the shape is there now (highlighted as the selection), the preview comes back when a value changes
    previewKey, previewPieces = fieldsKey(), nil
end

---Align row (generate panel), rebuilt on a click so the current choice is highlighted
---@param holder UIElement
local function buildAlign(holder)
    Rows.begin()
    createChoiceRow("Align", holder, {
        { label = "In", value = "in" },
        { label = "Out", value = "out" },
        { label = "Center", value = "center" },
    }, align, function(value)
        align = value
        Rows.refreshBlocks({ "generateAlign" })
    end,
        "Edge the pieces line up on. In: inside of the bend (top).\n" ..
        "Out: outside (bottom), Increment Z 0.3: stairs.\n" ..
        "Center: middles, Increment Y, Z 0.3: pyramid.")
end

---Generate panel: amount, gap, angle, piece size and increment. Nothing depends on the selection,
---placeholders show the values empty fields use
---@param holder UIElement
local function buildGenerate(holder)
    Rows.begin()
    local function apply() generate() end
    local inputs = {}
    local function add(row)
        for _, input in ipairs(row) do table.insert(inputs, input) end
    end
    add(createInputRow("Amount", holder, apply, { tostring(GENERATE_AMOUNT) }, "Pieces in the shape. Enter in any field generates."))
    add(createInputRow("Gap", holder, apply, { "0.00" }, "Space between pieces, negative overlaps."))
    add(createInputRow("Angle", holder, apply, { tostring(GENERATE_ANGLE) },
        "Total bend: 0 line, 90 quarter pipe, 360 loop."))
    add(createInputRow("Size", holder, apply, formatHints(defaultSides()),
        "First piece's size, empty: the default object's."))
    add(createInputRow("Increment", holder, apply, { "0.00", "0.00", "0.00" },
        "Added to each next piece's size, negative shrinks."))
    inwuts.generate = inputs
end

---Position row (rebuilt when the shape moves): placeholders show where the shape is now
---@param holder UIElement
local function buildPosition(holder)
    Rows.begin()
    inwuts.generatePos = createInputRow("Position", holder, function() generate() end, positionHints,
        "Shape's center like Pos shows it (from the dojo center).\n" ..
        "Empty: in front of the camera, typed axes stay put.\n" ..
        "To view clears it.")
end

---Generate and To view buttons
---@param holder UIElement
local function buildButtons(holder)
    Rows.begin()
    createToggleButtonRow("", holder, {
        { label = "Generate", active = false, onClick = generate },
        { label = "To view", active = false, onClick = toView },
    }, "Generate: adds the orange preview as static pieces\nand selects them.\n" ..
        "To view: moves the preview in front of the camera\n(also done when this tab opens), clears Position.")
end


---@type EditorPanelModule
return {
    fixed = {
        { build = buildGenerate, panel = "generate", row = 1, rows = 5 },
        { build = buildButtons, panel = "generate", row = 7, rows = 1 },
    },
    blocks = {
        { name = "generateAlign", build = buildAlign, panel = "generate", row = 0, rows = 1 },
        { name = "generatePos", build = buildPosition, panel = "generate", row = 6, rows = 1 },
    },
    inputs = { fixed = { "generate" }, rebuilt = { "generatePos" } },
}
