-- Joints list's Properties tab. Enter in a field applies it to every selected joint as one undo step,
-- like the object rows. Joints have no live setter, so each change saves and reloads. Which objects a
-- joint links is set on the Link tab (ui/editor_link.lua)
--   Pos:      the anchor, where the game joins them. Mid puts it halfway between the two objects, the
--             Move gizmo drags it (Joints.target, utils/joints.lua)
--   Axis:     the hinge axis, X / Y / Z set a world axis
--   Range, Strength, Velocity, Type (jointtype), Visible: the env_obj_joint lines of those names, a row each
-- Placeholders show the selection's value: "mixed" when the joints differ, "-" when the line is missing
-- (the game's default). Selected empty slots are left out

local Rows = MGE.EditorRows
local Widgets = MGE.Widgets
local Joints = MGE.Joints
local inwuts = Rows.inputs

local ROWS = 8 -- the panel's height in rows (PANELS in ui/editor.lua)
local BUTTON_W = 34
local GAP = 4

local INPUT_LISTS = { "jointPos", "jointAxis", "jointRange", "jointStrength", "jointVelocity", "jointType" }

---@return FileParserEnvObjJoint[] read when a value is applied: a reload replaces the joint tables
local function selectedJoints()
    return MGE.Main.selectedJointList()
end

---Full width text line, for the hints without a selection
---@param holder UIElement
---@param text string
---@param row integer 0-based
local function addLine(holder, text, row)
    local line = holder:addChild({
        pos = { 8, row * (holder.size.h / ROWS) },
        size = { holder.size.w - 16, holder.size.h / ROWS },
    })
    line:addAdaptedText(text, nil, nil, nil, LEFTMID, 0.7, nil, nil)
end

---Text in a row's content space
---@param row UIElement
---@param x number
---@param w number
---@param text string
local function addRowText(row, x, w, text)
    local holder = row:addChild({ pos = { x + 4, 0 }, size = { w - 8, row.size.h } })
    holder:addAdaptedText(text, nil, nil, nil, LEFTMID, 0.65, nil, nil)
end

---Placeholder for number `index` of a prop that has `count` numbers
---@param joints FileParserEnvObjJoint[]
---@param key string
---@param index integer
---@param count integer
---@return string
local function hintOf(joints, key, index, count)
    return Rows.sharedChoice(joints, function(joint)
        local value = joint.props[key]
        if value == nil then return "-" end
        return Rows.formatHint(Joints.parseNumbers(value, count)[index])
    end) or "-"
end

---@class JointRowSegment
---@field hint string? an input with this placeholder
---@field button string? a button with this label
---@field w number? button width, defaults to BUTTON_W
---@field lit boolean? button highlighted like a current choice
---@field popup string? button hover text
---@field onClick function?

---Inputs and buttons side by side in a row's content space, the inputs share the width the buttons leave
---@param row UIElement
---@param x number
---@param w number
---@param segments JointRowSegment[]
---@param onEnter fun(inputs: UIElement[], index: integer) index counts inputs only
---@return UIElement[] inputs in order
local function layoutRow(row, x, w, segments, onEnter)
    local buttonsW, inputCount = 0, 0
    for _, segment in ipairs(segments) do
        if segment.button then buttonsW = buttonsW + (segment.w or BUTTON_W) else inputCount = inputCount + 1 end
    end
    local inputW = inputCount > 0 and (w - buttonsW - GAP * (#segments - 1)) / inputCount or 0
    local inputs = {}
    local cx = x
    for _, segment in ipairs(segments) do
        if segment.button then
            local bw = segment.w or BUTTON_W
            local btn = Widgets.button(row, { x = cx, y = 2, w = bw, h = row.size.h - 4 }, segment.button,
                segment.onClick, nil, Widgets.PANEL_STYLE)
            if segment.lit then Rows.setHighlighted(btn, true) end
            if segment.popup then TBMenu:displayPopup(btn, segment.popup) end
            cx = cx + bw + GAP
        else
            local container = row:addChild({ pos = { cx, 0 }, size = { inputW, row.size.h }, interactive = true }, true)
            local index = #inputs + 1
            inputs[index] = Rows.createInput(container, function() onEnter(inputs, index) end, segment.hint)
            cx = cx + inputW + GAP
        end
    end
    return inputs
end

---Row of one prop's numbers (pos x y z, range high low, strength), Enter sets that number on every
---selected joint, their other numbers stay
---@param holder UIElement
---@param joints FileParserEnvObjJoint[]
---@param label string
---@param name string inwuts list
---@param key string prop
---@param count integer numbers in the prop
---@param help string
---@param buttons JointRowSegment[]? after the inputs
local function numberRow(holder, joints, label, name, key, count, help, buttons)
    local row, x, w = Rows.createRow(label, holder, help)
    local segments = {}
    for i = 1, count do segments[i] = { hint = hintOf(joints, key, i, count) } end
    for _, button in ipairs(buttons or {}) do table.insert(segments, button) end
    inwuts[name] = layoutRow(row, x, w, segments, function(inputs, index)
        local value = tonumber(inputs[index].textfieldstr[1])
        if value then Joints.setComponent(selectedJoints(), key, index, count, value) end
    end)
end

---Sets a whole prop to one value on the selected joints
---@param key string
---@param value string
local function setAll(key, value)
    Joints.setProps(selectedJoints(), key, function() return value end)
end

---First row: which joints the panel edits
---@param holder UIElement
---@param joints FileParserEnvObjJoint[]
local function buildHeading(holder, joints)
    local single = #joints == 1 and joints[1] or nil
    local row, x, w = Rows.createRow(single and "Joint " .. single.id or #joints .. " joints", holder)
    local text
    if single then
        local max = MGE.MAX_NONSTATIC_OBJECTS
        if single.obj1 > max or single.obj2 > max then
            text = "Ignored by the game: objects above id " .. max .. " (Reindex)"
        else
            text = "Links objects " .. single.obj1 .. " and " .. single.obj2 .. " (Link tab)"
        end
    else
        text = "A value typed here applies to all of them"
    end
    addRowText(row, x, w, text)
end

---Type row: the jointtype line, a whole number
---@param holder UIElement
---@param joints FileParserEnvObjJoint[]
local function buildType(holder, joints)
    local hint = Rows.sharedChoice(joints, function(joint) return joint.props.jointtype or "-" end) or "-"
    inwuts.jointType = Rows.createInputRow("Type", holder, function(inputs)
        local value = tonumber(inputs[1].textfieldstr[1])
        if value then setAll("jointtype", tostring(math.floor(value))) end
    end, { hint }, "The jointtype line, a number (most mods write 0).")
end

---Visible row: the visible line, the selected joints' shared value lit
---@param holder UIElement
---@param joints FileParserEnvObjJoint[]
local function buildVisible(holder, joints)
    local visible = Rows.sharedChoice(joints, function(joint) return joint.props.visible or "-" end)
    Rows.createChoiceRow("Visible", holder, {
        { label = "Visible", value = "1" },
        { label = "Hidden", value = "0" },
    }, visible, function(value) setAll("visible", value) end,
        "The visible line, lit when all selected joints\nhave it. Without the line the game decides.")
end

---@param holder UIElement
local function buildJoints(holder)
    Rows.begin()
    for _, name in ipairs(INPUT_LISTS) do inwuts[name] = {} end -- rows not built this time have no inputs
    local joints = selectedJoints()
    if #joints == 0 then -- a slot is always selected, but it can be empty
        addLine(holder, "The selected slot is empty: link two objects on the", 0)
        addLine(holder, "Link tab first, then set the values here.", 1)
        return
    end

    buildHeading(holder, joints)
    numberRow(holder, joints, "Pos", "jointPos", "pos", 3,
        "Anchor: where the game joins the two objects, in\n" ..
        "world coordinates. Mid: halfway between them.\n" ..
        "The Move gizmo (Shift + Q) drags it in the world.",
        { { button = "Mid", w = 38, onClick = function() Joints.centerPos(selectedJoints()) end } })
    local function axisButton(label, value)
        return { button = label, w = 24, onClick = function() setAll("axis", value) end }
    end
    numberRow(holder, joints, "Axis", "jointAxis", "axis", 3,
        "Hinge axis direction. X / Y / Z set a world axis.",
        { axisButton("X", "1 0 0"), axisButton("Y", "0 1 0"), axisButton("Z", "0 0 1") })
    numberRow(holder, joints, "Range", "jointRange", "range", 2,
        "Rotation limits, high then low as the file writes\n" ..
        "them (e.g. 3.6 -3.6).")
    numberRow(holder, joints, "Strength", "jointStrength", "strength", 1,
        "The joint's strength (its motor force).")
    numberRow(holder, joints, "Velocity", "jointVelocity", "velocity", 1,
        "The joint's motor velocity.")
    buildType(holder, joints)
    buildVisible(holder, joints)
end

---@type EditorPanelModule
return {
    blocks = { { name = "joint", build = buildJoints, panel = "joint", row = 0, rows = ROWS } },
    inputs = { rebuilt = INPUT_LISTS },
}
