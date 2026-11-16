




local Rows = {}
MGE.EditorRows = Rows

local Widgets = MGE.Widgets
local History = MGE.History
local ModData = MGE.ModData
local getSelected = ModData.getSelected


Rows.inputs = {}
local inwuts = Rows.inputs


Rows.refreshProperties = function() end
Rows.refreshMeasured = function() end

Rows.refreshBlocks = function() end
local function refreshProperties() Rows.refreshProperties() end

local totalHeight = 0


function Rows.begin()
    totalHeight = 0
end

local function updateContentHeight(height)
    totalHeight = totalHeight + height
end






local function readInputs(inputs, only)
    local values = {}
    for i, input in ipairs(inputs) do
        if not only or i == only then values[i] = tonumber(input.textfieldstr[1]) end
    end
    return values
end




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






local function formatHint(value)
    local s = string.format("%.2f", value)
    if s == "-0.00" then s = "0.00" end
    return s
end



local function formatHints(values)
    local hints = {}
    for i = 1, 3 do hints[i] = formatHint(values[i]) end
    return hints
end





local function formatStep(value, decimals)
    local s = string.format("%." .. (decimals or 4) .. "f", value):gsub("0+$", ""):gsub("%.$", "")
    if s == "-0" then s = "0" end
    return s
end
Rows.formatWheelValue = formatStep
Rows.formatNumberText = formatStep






function Rows.wheelBase(text, placeholder)

    return tonumber(text) or tonumber(tostring(placeholder or ""):match("^%s*(-?%d*%.?%d+)")) or 0
end








Rows.applying = nil






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
        if not ok then MGE.say(tostring(err)) end
    end

    if not input.destroyed then input:clearTextfield() end
end













local function addWheelStep(input, placeholder, exact, apply, opts)
    local whole, angle = opts.whole, opts.angle
    local press = input.btnDown
    input.scrollEnabled = true
    input.btnDown = function(btn, x, y)
        if btn ~= 4 and btn ~= 5 then return press(btn, x, y) end
        local mx, my = MOUSE_X or x, MOUSE_Y or y
        if not input:isDisplayed() or mx < input.pos.x or mx > input.pos.x + input.size.w
            or my < input.pos.y or my > input.pos.y + input.size.h then
            return false
        end
        local typed = input.textfieldstr[1]
        local value = (tonumber(typed) == nil and exact) or Rows.wheelBase(typed, placeholder)
        local Config, shift = MGE.Config, get_keyboard_shift() ~= 0
        local step
        if angle then
            step = shift and 1 or Config.rotateStep
        elseif whole then
            step = 1
        else
            step = shift and Config.wheelFineStep or Config.wheelStep
        end
        local after = value + (btn == 4 and step or -step)
        if whole then after = math.floor(after + 0.5) end
        local text = formatStep(after)
        input.textfieldstr[1] = text
        input.textfieldindex = #text
        if apply then apply(Rows.fieldKey(input)) end
        return true
    end
end





function Rows.fieldKey(input)
    return "field " .. math.floor(input.pos.x) .. "," .. math.floor(input.pos.y)
end







local leftFields = {}
local LEAVE_HOOK = MGE.hookname .. "_rows"
add_hook("draw3d", LEAVE_HOOK, function()
    if #leftFields == 0 then return end
    local queue = leftFields
    leftFields = {}
    for _, apply in ipairs(queue) do
        local ok, err = pcall(apply)
        if not ok then MGE.say(tostring(err)) end
    end
end)
table.insert(MGE.onQuit, function() remove_hooks(LEAVE_HOOK) end)






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












local function resolvePlaceholder(placeholder)
    if type(placeholder) == "number" then return formatHint(placeholder), placeholder end
    if type(placeholder) == "table" then return placeholder.text, placeholder.value end
    return placeholder or "0", nil
end



local function createInput(container, onInputFunc, placeholder, opts)
    opts = opts or {}
    local mode = opts.mode or "live"
    local text, exact = resolvePlaceholder(placeholder)
    local input = TBMenu:spawnTextField2(container, nil, "",
        text,
        {
            inputType = 2,
            textfield = true,
            returnKeyType = KEYBOARD_RETURN.SEND,
            isNumeric = true,
            allowDecimal = true,
            allowNegative = true,
            textAlign = CENTER,
            fontId = MGE.Widgets.FONT,
            darkerMode = true,
            textScale = MGE.Widgets.TEXT_SCALE_SMALL,
        })

    local function apply(mergeKey) applyField(input, onInputFunc, mode, mergeKey) end
    input:addKeyboardHandlers(mode == "live" and function(key)
        if key == 27 then input:clearTextfield() end
    end or nil, function(key)
        if key ~= 13 then return end
        apply()
    end)
    if mode ~= "form" then applyOnLeave(input, apply) end
    addWheelStep(input, text, exact, mode ~= "form" and apply or nil, opts)
    return input
end









local function createRow(label, parent, help, onLabelClick)
    local row = parent:addChild({
        pos = { 0, totalHeight },
        size = { parent.size.w, MGE.Widgets.ROW_H },
        interactive = true,
    }, true)

    local labelW = MGE.Widgets.px(66)
    local helpSize = MGE.Widgets.ROW_H - 6
    local helpW = help and helpSize + 8 or 0
    local labelButton
    if onLabelClick then
        local inset = Widgets.INSET
        labelButton = Widgets.button(row, { x = inset, y = inset, w = labelW - inset * 2, h = row.size.h - inset * 2 }, label, onLabelClick,
            Widgets.TEXT_SCALE, Widgets.PANEL_STYLE)
    else

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

        Widgets.helpIcon(row, -helpSize - 2, (row.size.h - helpSize) / 2, helpSize, help, nil, Widgets.PANEL_STYLE)
    end

    updateContentHeight(row.size.h)
    return row, labelW, row.size.w - labelW - helpW, labelButton
end










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
        inputs[i] = createInput(inputContainer, function() func(inputs, i) end, placeholder, opts)
    end
    return inputs, row, labelButton
end





local function setHighlighted(btn, on)
    if btn and not btn.destroyed then
        btn.bgColor = on and Widgets.ACTIVE_COLOR or (btn.plainLabel and { 0, 0, 0, 0 } or Widgets.PANEL_STYLE.bg)
    end
end









local function createChoiceRow(label, parent, choices, current, onPick, help)
    local row, contentX, contentW = createRow(label, parent, help)
    local holder = row:addChild({
        pos = { contentX + Widgets.INSET, Widgets.INSET },
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







local function createToggleButtonRow(label, parent, toggles, help)
    local row, contentX, contentW = createRow(label, parent, help)
    local holder = row:addChild({
        pos = { contentX + Widgets.INSET, Widgets.INSET },
        size = { contentW - Widgets.INSET * 2, row.size.h - Widgets.INSET * 2 },
    }, true)
    for i, btn in ipairs(Widgets.buttonRow(holder, 0, holder.size.h, toggles, Widgets.GAP, nil, Widgets.PANEL_STYLE)) do
        if toggles[i].active then btn.bgColor = Widgets.ACTIVE_COLOR end
    end
end














local PROPERTIES = {
    mass = { min = 0.0001, default = 0.1, decimals = 4,
        setter = function(id, v) set_obj_mass(id, v) end, getter = function(id) return get_obj_mass(id) end },
    friction = { min = 0, default = 10000, decimals = 2 },
    bounce = { min = 0, default = 0.1, decimals = 6,
        setter = function(id, v) set_obj_bounce(id, v) end, getter = function(id) return get_obj_bounce(id) end },


    hardness = { min = 0, default = 0, decimals = 6 },
}





local function formatProperty(property, value)
    return string.format("%." .. property.decimals .. "f", value)
end




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
        MGE.apply()
    end
end

local PROPERTY_HELP = {
    mass = "Applies mass\n\"mixed\": the selected objects differ.",
    friction = "Applied by saving, the game can't change it live.",
    bounce = "Bounciness. \"mixed\": the selected objects differ.",
    hardness = "Points multiplier when it touches a player.\n0 (default): no points, still damages. 0.5: half,\n1: full, 2: double. Applied by saving.",
}






local function buildPropertyRows(holder, selected, entries)
    local inputs = {}
    for _, entry in ipairs(entries) do
        local label, key = entry[1], entry[2]
        local property = PROPERTIES[key]


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






function Rows.gizmoLabels()
    local labels = {}
    local function highlight()
        for mode, label in pairs(labels) do setHighlighted(label, mode == MGE.Gizmo.mode) end
    end
    table.insert(MGE.Gizmo.modeListeners, highlight)
    return labels, highlight
end
Rows.createToggleButtonRow = createToggleButtonRow
Rows.buildPropertyRows = buildPropertyRows
Rows.setSelectedProp = setSelectedProp

return Rows
