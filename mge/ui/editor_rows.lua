-- Shared pieces of the editor panels (ui/editor_*.lua): the row widgets (label column, inputs or buttons,
-- "?" help icon), the input lists, value helpers and the single value property rows.
-- Builders call Rows.begin() first, rows then stack from the top of the holder.

---@class EditorRows
local Rows = {}
MGE.EditorRows = Rows

local Widgets = MGE.Widgets
local History = MGE.History
local getSelected = MGE.ModData.getSelected

---@type table<string, UIElement[]> input fields by list name (pos, color, thrust...), filled by the builders
Rows.inputs = {}
local inwuts = Rows.inputs

-- set by ui/editor.lua: rebuild the rows that show current values
Rows.refreshProperties = function() end
Rows.refreshMeasured = function() end
---@type fun(names: string[]) rebuilds the named blocks (EditorBlock.name)
Rows.refreshBlocks = function() end
local function refreshProperties() Rows.refreshProperties() end

local totalHeight = 0

---Starts a block of rows at the top of its holder
function Rows.begin()
    totalHeight = 0
end

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


---Value as a placeholder shows it, two decimals. Values that round to zero show "0.00", not "-0.00"
---(-0 and tiny negatives like -0.000001 left over from rotation math)
---@param value number
---@return string
local function formatHint(value)
    local s = string.format("%.2f", value)
    if s == "-0.00" then s = "0.00" end
    return s
end

---@param values number[]
---@return string[]
local function formatHints(values)
    local hints = {}
    for i = 1, 3 do hints[i] = formatHint(values[i]) end
    return hints
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
---@param onLabelClick function? makes the label a button (switches a transform row's mode)
---@return UIElement row, number contentX, number contentW, UIElement? labelButton only with onLabelClick
local function createRow(label, parent, help, onLabelClick)
    local row = parent:addChild({
        pos = { 0, totalHeight },
        size = { parent.size.w, 30 },
        interactive = true,
    }, true)

    local labelW = 80
    local helpSize = 22
    local helpW = help and helpSize + 8 or 0 -- space reserved at the end of the row for the "?" icon
    local labelButton
    if onLabelClick then
        labelButton = Widgets.button(row, { x = 2, y = 2, w = labelW - 4, h = row.size.h - 4 }, label, onLabelClick,
            nil, Widgets.PANEL_STYLE)
    else
        local labelContainer = row:addChild({
            pos = { 0, 0 },
            size = { labelW, row.size.h },
        }, true)
        labelContainer:addAdaptedText(label, nil, nil, nil, CENTERMID, 0.7, nil, nil)
    end

    if help then
        -- "?" at the row's end, the explanation opens right of it, outside the window
        Widgets.helpIcon(row, -helpSize - 2, (row.size.h - helpSize) / 2, helpSize, help, nil, Widgets.PANEL_STYLE)
    end

    updateContentHeight(row.size.h)
    return row, labelW, row.size.w - labelW - helpW, labelButton
end

---Label column followed by equally sized inputs and an optional "?" help icon at the end
---@param label string
---@param parent UIElement
---@param func fun(inputs: UIElement[], index: integer) called on enter
---@param placeholders string[] one per input
---@param help string? explanation shown when hovering the "?" icon
---@param onLabelClick function? see createRow
---@return UIElement[] inputs, UIElement row, UIElement? labelButton see createRow
local function createInputRow(label, parent, func, placeholders, help, onLabelClick)
    local row, contentX, contentW, labelButton = createRow(label, parent, help, onLabelClick)
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
    return inputs, row, labelButton
end

---Highlights a button like the current choice in createChoiceRow, or gives it the panel look back
---@param btn UIElement? nil and destroyed buttons are skipped
---@param on boolean
local function setHighlighted(btn, on)
    if btn and not btn.destroyed then
        btn.bgColor = on and TB_MENU_DEFAULT_LIGHTER_COLOR or Widgets.PANEL_STYLE.bg
    end
end

---Label column followed by buttons for a fixed set of values, the current one is highlighted
---@param label string
---@param parent UIElement
---@param choices { label: string, value: any }[]
---@param current any value shared by the selection, nil or "mixed" highlights nothing
---@param onPick fun(value: any)
---@param help string?
---@return UIElement[] buttons in choice order, highlight a new current one with setHighlighted
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
    local buttons = Widgets.buttonRow(holder, 0, holder.size.h, items, 4, nil, Widgets.PANEL_STYLE)
    for i, btn in ipairs(buttons) do
        if choices[i].value == current then setHighlighted(btn, true) end
    end
    return buttons
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

-- Simple per-object properties edited with absolute values. Friction and hardness have no live
-- setter, they're stored in props and applied by saving (the mod reloads with the new value).
-- default: the game's value for objects without the line. decimals: what the game's modmaker writes
-- (friction 10000.00, bounce 0.100000, hardness 0.000000, mass 0.1000), used for the file and the
-- placeholders.
---@class EditorProperty
---@field min number
---@field default number
---@field decimals integer
---@field setter (fun(id: integer, value: number))?
---@field getter (fun(id: integer): number?)?

---@type table<string, EditorProperty>
local PROPERTIES = {
    mass = { min = 0.0001, default = 0.1, decimals = 4, -- zero mass breaks physics
        setter = function(id, v) set_obj_mass(id, v) end, getter = function(id) return get_obj_mass(id) end },
    friction = { min = 0, default = 10000, decimals = 2 },
    bounce = { min = 0, default = 0.1, decimals = 6,
        setter = function(id, v) set_obj_bounce(id, v) end, getter = function(id) return get_obj_bounce(id) end },
    -- points multiplier on contact with a player, no get_obj / set_obj for it. Without the line the
    -- game uses 0 (older docs say 1)
    hardness = { min = 0, default = 0, decimals = 6 },
}

---Value as the game writes it for the property, e.g. 0.1 -> "0.1000" for mass
---@param property EditorProperty
---@param value number
---@return string
local function formatProperty(property, value)
    return string.format("%." .. property.decimals .. "f", value)
end

---Sets a property on all selected objects from an input field, empty input does nothing
---@param key "mass"|"friction"|"bounce"|"hardness"
---@param input UIElement
local function setProperty(key, input)
    local value = tonumber(input.textfieldstr[1])
    if not value then return end
    local selectedObjects = getSelected()
    if #selectedObjects == 0 then return end

    local property = PROPERTIES[key]
    value = math.max(value, property.min)
    for _, v in ipairs(selectedObjects) do
        v.props[key] = formatProperty(property, value)
        if property.setter then property.setter(v.id - 1, value) end
    end
    History.commit()
    if property.setter then
        refreshProperties()
    else
        MGE.apply() -- reload rebuilds the editor with the new value
    end
end

local PROPERTY_HELP = {
    mass = "Applies mass\n\"mixed\": the selected objects differ.",
    friction = "Applied by saving, the game can't change it live.",
    bounce = "Bounciness. \"mixed\": the selected objects differ.",
    hardness = "Points multiplier when it touches a player.\n0 (default): no points, still damages. 0.5: half,\n1: full, 2: double. Applied by saving.",
}

---Single value rows (mass, friction, bounce, hardness), placeholders show the selection's current value
---@param holder UIElement
---@param selected FileParserEnvObj[]
---@param entries string[][] { label, key } pairs
---@return UIElement[] inputs
local function buildPropertyRows(holder, selected, entries)
    local inputs = {}
    for _, entry in ipairs(entries) do
        local label, key = entry[1], entry[2]
        local property = PROPERTIES[key] ---@type EditorProperty
        -- value shared by the selection ("mixed" when they differ): the file's line (what MGE writes,
        -- undoes and saves), else the live value, else the game default
        local hint = sharedChoice(selected, function(obj)
            local value = tonumber(obj.props[key]) or (property.getter and property.getter(obj.id - 1))
            return formatProperty(property, value or property.default)
        end) or formatProperty(property, property.default)
        local row = createInputRow(label, holder, function(rowInputs) setProperty(key, rowInputs[1]) end,
            { hint }, PROPERTY_HELP[key])
        table.insert(inputs, row[1])
    end
    return inputs
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
    MGE.apply()
end


Rows.readInputs = readInputs
Rows.sharedChoice = sharedChoice
Rows.formatHints = formatHints
Rows.formatHint = formatHint
Rows.createInput = createInput
Rows.createRow = createRow
Rows.createInputRow = createInputRow
Rows.createChoiceRow = createChoiceRow
Rows.setHighlighted = setHighlighted
Rows.createToggleButtonRow = createToggleButtonRow
Rows.buildPropertyRows = buildPropertyRows
Rows.setSelectedProp = setSelectedProp

return Rows
