-- Generate tab: lines, ramps and loops made of default objects (geometry in utils/shape_gen.lua)
local Rows = MGE.EditorRows
local inwuts = Rows.inputs
local formatHints = Rows.formatHints
local createInputRow = Rows.createInputRow
local createToggleButtonRow = Rows.createToggleButtonRow

local Transforms = MGE.Transforms

-- used for empty Generate fields, shown as their placeholders
local GENERATE_AMOUNT = 8
local GENERATE_ANGLE = 90
local MAX_GENERATE = 200 -- more than any mod has room for, stops a typo from planning thousands

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
    local sides = defaultSides()
    for i = 1, 3 do
        local value = typed(3 + i)
        if value and value > 0 then sides[i] = math.max(value, MGE.MIN_SIDE) end
    end
    local pieces = MGE.ShapeGen.plan(amount, typed(2) or 0, typed(3) or GENERATE_ANGLE, sides, { MGE.POS_ORIGIN[1], MGE.POS_ORIGIN[2] })

    local objects = {}
    for i, piece in ipairs(pieces) do
        local obj = { kind = "env_obj", id = i, props = MGE.Assets.defaultProps(), frame = piece.frame }
        obj.props.flag = tostring(MGE.FLAGS.STATIC) -- a ramp stays in place, and static ids are plenty
        Transforms.writeVector(obj, "pos", piece.pos)
        Transforms.writeVector(obj, "rot", piece.rot)
        Transforms.writeVector(obj, "sides", sides)
        objects[i] = obj
    end
    -- selected and saved like an import, the tab stays so values can be tried again after Undo
    MGE.Assets.addObjects(objects, true)
end

---Generate panel: amount, gap, angle, piece size and the Generate button. Nothing depends on the
---selection, placeholders show the values empty fields use
---@param holder UIElement
local function buildGenerate(holder)
    Rows.begin()
    local function apply() generate() end
    local inputs = {}
    local function single(label, hint, help)
        table.insert(inputs, createInputRow(label, holder, apply, { hint }, help)[1])
    end
    single("Amount", tostring(GENERATE_AMOUNT), "Pieces in the shape. Enter in any field generates.")
    single("Gap", "0.00", "Space between pieces, negative overlaps them.")
    single("Angle", tostring(GENERATE_ANGLE), "Degrees the shape bends up in total:\n0 is a line, 90 a quarter pipe, 360 a closed loop.\n" ..
        "Rotate the result for other directions (e.g. X 90 for a flat ring).")
    for _, input in ipairs(createInputRow("Size", holder, apply, formatHints(defaultSides()),
        "Piece length (X), width (Y) and thickness (Z),\nempty fields use the default object's.")) do
        table.insert(inputs, input)
    end
    inwuts.generate = inputs

    createToggleButtonRow("", holder, {
        { label = "Generate", active = false, onClick = generate },
    }, "Adds the shape at the middle of the dojo, made of static\ndefault objects, and selects it. Undo removes it again.")
end


---@type EditorPanelModule
return {
    fixed = { { build = buildGenerate, panel = "generate", row = 0, rows = 5 } },
    inputs = { fixed = { "generate" } },
}
