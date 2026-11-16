-- Shared pieces of the editor panels (ui/editor_*.lua): the row widgets (label column, inputs or buttons,
-- "?" help icon), the input lists, value helpers and the single value property rows.
-- Builders call Rows.begin() first, rows then stack from the top of the holder.

---@class EditorRows
local Rows = {}
MGE.EditorRows = Rows

local Widgets = MGE.Widgets
local History = MGE.History
local ModData = MGE.ModData
local getSelected = ModData.getSelected

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

---A number as a field shows it after a wheel step: no trailing zeros, "-0" as "0"
---@param value number
---@return string
local function formatStep(value)
    local s = string.format("%.4f", value):gsub("0+$", ""):gsub("%.$", "")
    if s == "-0" then s = "0" end
    return s
end
Rows.formatWheelValue = formatStep -- for the tests

---The value a wheel step starts from: the typed number, else the placeholder's (the selection's current
---value), else 0 ("mixed", or nothing to read)
---@param text string?
---@param placeholder string?
---@return number
function Rows.wheelBase(text, placeholder)
    -- the placeholder's leading number: "8 obj" (Generate's Amount) is 8
    return tonumber(text) or tonumber(tostring(placeholder or ""):match("^%s*(-?%d*%.?%d+)")) or 0
end

---The value after a wheel step. Whole-number fields step by 1 (Shift too) and round first
---@param base number
---@param up boolean
---@param step number the wheel's step for decimal fields (Config.wheelStep or .wheelFineStep)
---@param whole boolean?
---@return number
function Rows.wheelValue(base, up, step, whole)
    if whole then
        base, step = math.floor(base + 0.5), 1
    end
    return base + (up and step or -step)
end

---@alias InputMode
---| "live" # the editor's rows: the wheel and leaving the field apply it, then the field empties (its placeholder
---          shows the value now): what you see is what the selection has, no Enter needed. Esc drops the typing
---| "keep" # Settings: the wheel and leaving apply it, the value stays in the field
---| "form" # Generate, Convert Map: fields an action reads (Enter runs it), the wheel only changes the text

---@type UIElement? the field being applied: a rebuild (ui/editor.lua) doesn't put its text back in the new field
Rows.applying = nil

---Applies a field the way its mode says
---@param input UIElement
---@param onInputFunc fun()
---@param mode InputMode
---@param mergeKey string? History.mergeKey for its commit: wheel steps on one field are one undo step
local function applyField(input, onInputFunc, mode, mergeKey)
    if mode ~= "live" then
        onInputFunc()
        return
    end
    local text = input.textfieldstr[1]
    if text == "" then return end
    if tonumber(text) then
        Rows.applying = input
        History.mergeKey = mergeKey
        local ok, err = pcall(onInputFunc)
        History.mergeKey = nil
        Rows.applying = nil
        if not ok then MGE.say("" .. tostring(err)) end
    end
    -- empty again (also "-" or "." alone): the placeholder shows the selection's value now
    if not input.destroyed then input:clearTextfield() end
end

---Mouse wheel over a number field: up adds the step (Config.wheelStep, with Shift Config.wheelFineStep; a Rot
---field Config.rotateStep, with Shift 1), down
---takes it away, from the typed number or the
---placeholder's (the selection's value). Live and keep fields apply it right away, form fields only get the
---text. toriui sends the wheel to every scrollEnabled element, wherever the mouse is, so the field checks the
---cursor itself (MOUSE_X / Y: the wheel's own x, y aren't the cursor)
---@param input UIElement
---@param placeholder string? the field's placeholder (toriui's text field doesn't keep it)
---@param apply fun(mergeKey: string?) applies the field (applyField with its mode), nil for form fields
---@param whole boolean? a whole-number field: steps of 1 (an angle field: the rotate step, rounded)
---@param angle boolean? a Rot field: steps of Config.rotateStep degrees, with Shift 1
---@param exact number? the value the placeholder rounds (2 decimals): an empty field steps from this
local function addWheelStep(input, placeholder, apply, whole, angle, exact)
    local press = input.btnDown
    input.scrollEnabled = true
    input.btnDown = function(btn, x, y)
        if btn ~= 4 and btn ~= 5 then return press(btn, x, y) end
        local mx, my = MOUSE_X or x, MOUSE_Y or y
        if not input:isDisplayed() or mx < input.pos.x or mx > input.pos.x + input.size.w
            or my < input.pos.y or my > input.pos.y + input.size.h then
            return false -- not this field: the wheel goes on to the next element (a list, the camera)
        end
        local typed = input.textfieldstr[1]
        local value = (tonumber(typed) == nil and exact) or Rows.wheelBase(typed, placeholder)
        local Config, shift = MGE.Config, get_keyboard_shift() ~= 0
        local step ---@type number
        if angle then
            step = shift and 1 or Config.rotateStep
        else
            step = shift and Config.wheelFineStep or Config.wheelStep
        end
        local after = Rows.wheelValue(value, btn == 4, step, whole and not angle)
        if whole and angle then after = math.floor(after + 0.5) end -- whole degrees (engageplayerrot)
        local text = formatStep(after)
        input.textfieldstr[1] = text
        input.textfieldindex = #text
        if apply then apply(Rows.fieldKey(input)) end -- one undo step while the mouse stays on the field
        return true
    end
end

---A field's key for merged wheel steps (History.mergeKey): its place on screen, the same for the field a
---rebuild puts there
---@param input UIElement
---@return string
function Rows.fieldKey(input)
    return "field " .. math.floor(input.pos.x) .. "," .. math.floor(input.pos.y)
end

-- Fields left by a click elsewhere, applied in MGE's draw3d hook, before toriui draws the next frame.
-- The leaving is seen while the field draws (applyOnLeave), and applying there reloaded the mod and rebuilt
-- the panel in the middle of toriui drawing it: the old rows were destroyed mid-draw and every tab's rows
-- flashed on top of each other for a moment (a joint's Range, then a click on another field). Enter
-- applies from the key handler, outside the drawing, which never did it
---@type fun()[]
local leftFields = {}
local LEAVE_HOOK = MGE.hookname .. "_rows"
add_hook("draw3d", LEAVE_HOOK, function()
    if #leftFields == 0 then return end
    local queue = leftFields
    leftFields = {}
    for _, apply in ipairs(queue) do
        local ok, err = pcall(apply)
        if not ok then MGE.say("" .. tostring(err)) end
    end
end)
table.insert(MGE.onQuit, function() remove_hooks(LEAVE_HOOK) end)

---Leaving a field (a click elsewhere: toriui takes its keyboard focus away) applies what's typed, on the
---next frame outside the UI's drawing (leftFields). The mouse leaving it ends its wheel steps' undo step
---(History.endMerge). Checked each frame it's drawn: toriui has no focus-lost callback
---@param input UIElement
---@param apply fun()
local function applyOnLeave(input, apply)
    local focused = false
    Widgets.addDrawBefore(input, function()
        local now = input.keyboard == true
        if focused and not now and input.textfieldstr[1] ~= "" then leftFields[#leftFields + 1] = apply end
        focused = now
        if History.lastMerge and (MOUSE_X < input.pos.x or MOUSE_X > input.pos.x + input.size.w
            or MOUSE_Y < input.pos.y or MOUSE_Y > input.pos.y + input.size.h) then
            History.endMerge(Rows.fieldKey(input))
        end
    end)
end

---@param placeholder string? text shown while empty, defaults to "0"
---@param mode InputMode? defaults to "live"
---@param whole boolean? a whole-number field (a count, a level): the wheel steps by 1
---@param angle boolean? a Rot field in degrees: the wheel steps by the rotate step (addWheelStep)
---@param exact number? the value the placeholder shows rounded: the wheel steps from it (addWheelStep)
local function createInput(container, onInputFunc, placeholder, mode, whole, angle, exact)
    mode = mode or "live"
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
            fontId = MGE.Widgets.FONT, -- the window's font (Widgets.FONT)
            darkerMode = true, -- base window color, matches the panel buttons (Widgets.PANEL_STYLE)
            textScale = MGE.Widgets.TEXT_SCALE_SMALL, -- smaller than the labels
        })
    ---@param mergeKey string?
    local function apply(mergeKey) applyField(input, onInputFunc, mode, mergeKey) end
    input:addKeyboardHandlers(mode == "live" and function(key)
        if key == 27 then input:clearTextfield() end -- Esc: the typing is dropped, leaving applies nothing
    end or nil, function(key)
        if key ~= 13 then return end --enter
        apply()
    end)
    if mode ~= "form" then applyOnLeave(input, apply) end
    addWheelStep(input, placeholder, mode ~= "form" and apply or nil, whole, angle, exact)
    return input
end

---Row with the label column on the left and an optional "?" help icon at the end.
---Returns the row and the x and width of the space between them, for inputs or buttons
---@param label string
---@param parent UIElement
---@param help string? explanation shown when hovering the "?" icon
---@param onLabelClick function? makes the label a button (switches a transform row's mode)
---@return UIElement row, number contentX, number contentW, UIElement labelElement the name's button with
---onLabelClick, else its label (Rows.setHighlighted lights either)
local function createRow(label, parent, help, onLabelClick)
    local row = parent:addChild({
        pos = { 0, totalHeight },
        size = { parent.size.w, MGE.Widgets.ROW_H },
        interactive = true,
    }, true)

    local labelW = MGE.Widgets.px(66)
    local helpSize = MGE.Widgets.ROW_H - 6
    local helpW = help and helpSize + 8 or 0 -- space reserved at the end of the row for the "?" icon
    local labelButton
    if onLabelClick then
        local inset = Widgets.INSET -- like the number fields
        labelButton = Widgets.button(row, { x = inset, y = inset, w = labelW - inset * 2, h = row.size.h - inset * 2 }, label, onLabelClick,
            Widgets.TEXT_SCALE, Widgets.PANEL_STYLE) -- label size, like the plain labels under it
    else
        -- inset like the name buttons, see-through until highlighted (Rows.setHighlighted)
        local inset = Widgets.INSET
        labelButton = row:addChild({
            pos = { inset, inset },
            size = { labelW - inset * 2, row.size.h - inset * 2 },
            bgColor = { 0, 0, 0, 0 },
        }, true)
        labelButton.plainLabel = true
        labelButton:addAdaptedText(label, nil, nil, MGE.Widgets.FONT, CENTERMID, MGE.Widgets.TEXT_SCALE, nil, nil)
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
---@param opts { mode: InputMode?, whole: boolean?, angle: boolean?, exact: number[]? }? see createInput, default:
---live decimal fields. exact: the values the placeholders round, one per input (the wheel steps from them)
---@return UIElement[] inputs, UIElement row, UIElement? labelButton see createRow
local function createInputRow(label, parent, func, placeholders, help, onLabelClick, opts)
    local row, contentX, contentW, labelButton = createRow(label, parent, help, onLabelClick)
    local columnSize = contentW / #placeholders
    local inputs = {}
    for i, placeholder in ipairs(placeholders) do
        local inputContainer = row:addChild({
            pos = { contentX + (i - 1) * columnSize, 0 },
            size = { columnSize, row.size.h },
            interactive = true,
        }, true)
        inputs[i] = createInput(inputContainer, function() func(inputs, i) end, placeholder, opts and opts.mode,
            opts and opts.whole, opts and opts.angle, opts and opts.exact and opts.exact[i])
    end
    return inputs, row, labelButton
end

---Highlights a button like the current choice in createChoiceRow, or gives it the panel look back. A row's
---plain label (createRow) goes back to see-through
---@param btn UIElement? nil and destroyed buttons are skipped
---@param on boolean
local function setHighlighted(btn, on)
    if btn and not btn.destroyed then
        btn.bgColor = on and Widgets.ACTIVE_COLOR or (btn.plainLabel and { 0, 0, 0, 0 } or Widgets.PANEL_STYLE.bg)
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
        pos = { contentX + Widgets.INSET, Widgets.INSET }, -- lines up with the number fields
        size = { contentW - Widgets.INSET * 2, row.size.h - Widgets.INSET * 2 },
    }, true)
    local items = {}
    for i, choice in ipairs(choices) do
        items[i] = { label = choice.label, onClick = function() onPick(choice.value) end }
    end
    local buttons = Widgets.buttonRow(holder, 0, holder.size.h, items, Widgets.GAP, nil, Widgets.PANEL_STYLE)
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
        pos = { contentX + Widgets.INSET, Widgets.INSET }, -- lines up with the number fields
        size = { contentW - Widgets.INSET * 2, row.size.h - Widgets.INSET * 2 },
    }, true)
    for i, btn in ipairs(Widgets.buttonRow(holder, 0, holder.size.h, toggles, Widgets.GAP, nil, Widgets.PANEL_STYLE)) do
        if toggles[i].active then btn.bgColor = Widgets.ACTIVE_COLOR end
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

---Writes a prop on all selected objects (on the Atmo list the atmo objects) and saves if any of them
---changed. Atmo objects aren't in the .tbm: no reload, the rows show the new value
---@param key string
---@param value string
local function setSelectedProp(key, value)
    local changed = false
    local atmo = MGE.Main and MGE.Main.listTab == "atmo"
    for _, v in ipairs(ModData.getEditSelection()) do
        if v.props[key] ~= value then
            v.props[key] = value
            changed = true
        end
    end
    if not changed then return end
    History.commit()
    if atmo then refreshProperties() else MGE.apply() end
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
