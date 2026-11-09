-- Generate tab: lines, ramps, loops, stairs and pyramids made of default objects (geometry in utils/shape_gen.lua)
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

---Generate button / Enter: adds the shape, made of the default object made static
local function generate()
    local fields = inwuts.generate or {}
    local function typed(i) return fields[i] and tonumber(fields[i].textfieldstr[1]) end
    local amount = math.floor((typed(1) or GENERATE_AMOUNT) + 0.5)
    if amount < 2 or amount > MAX_GENERATE then -- one piece is what the list's New button adds
        print("Generate: amount must be 2-" .. MAX_GENERATE)
        return
    end
    local sides, increment = defaultSides(), {}
    for i = 1, 3 do
        local value = typed(3 + i)
        if value and value > 0 then sides[i] = math.max(value, MGE.MIN_SIDE) end
        increment[i] = typed(6 + i) or 0
    end
    local most = MGE.ShapeGen.maxPieces(sides, increment)
    if most and amount > most then
        print("Generate: the increment shrinks pieces to nothing after " .. most .. " pieces, use fewer or a smaller increment")
        return
    end
    local pieces = MGE.ShapeGen.plan(amount, typed(2) or 0, typed(3) or GENERATE_ANGLE, sides,
        { MGE.POS_ORIGIN[1], MGE.POS_ORIGIN[2] }, { increment = increment, align = align })

    local objects = {}
    for i, piece in ipairs(pieces) do
        local obj = { kind = "env_obj", id = i, props = MGE.Assets.defaultProps(), frame = piece.frame }
        obj.props.flag = tostring(MGE.FLAGS.STATIC) -- a ramp stays in place, and static ids are plenty
        Transforms.writeVector(obj, "pos", piece.pos)
        Transforms.writeVector(obj, "rot", piece.rot)
        Transforms.writeVector(obj, "sides", piece.sides)
        objects[i] = obj
    end
    -- selected and saved like an import, the tab stays so values can be tried again after Undo
    MGE.Assets.addObjects(objects, true)
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

---Generate panel: amount, gap, angle, piece size, increment and the Generate button. Nothing depends
---on the selection, placeholders show the values empty fields use
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

    createToggleButtonRow("", holder, {
        { label = "Generate", active = false, onClick = generate },
    }, "Adds static pieces at the dojo middle and selects them.")
end


---@type EditorPanelModule
return {
    fixed = { { build = buildGenerate, panel = "generate", row = 1, rows = 6 } },
    blocks = { { name = "generateAlign", build = buildAlign, panel = "generate", row = 0, rows = 1 } },
    inputs = { fixed = { "generate" } },
}
