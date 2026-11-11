-- Joints list's Properties tab. Enter in a field applies it to every selected joint as one undo step,
-- like the object rows. Joints have no live setter, so each change saves and reloads. Which objects a
-- joint links is set on the Link tab (ui/editor_link.lua)
--   Pos:      the anchor, where the game joins them. Like the Core tab's Pos: the selected joints'
--             center, a typed axis moves them together so the center gets there (as the Move gizmo
--             does, Joints.target in utils/joints.lua). Recenter (the last row) puts each halfway between its two objects
--   Axis:     the axis line, typed as the file writes it
--   Range, Strength, Velocity, Type (jointtype), Visible: the env_obj_joint lines of those names, a row each
-- Placeholders show the current values: "mixed" when the joints differ, DEFAULTS for a missing line.
-- Selected empty slots are left out

local Rows = MGE.EditorRows
local Joints = MGE.Joints
local inwuts = Rows.inputs

local ROWS = 8 -- the panel's height in rows (PANELS in ui/editor.lua)

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

-- a joint's value when its line is missing: what the game's modmaker writes for a new joint, the values
-- nearly every mod's joints have (a scan of data/mod: axis 0 0 0, range 0 0, strength / velocity 0,
-- visible 0, jointtype 0). There's no getter for env joints to read the live value from
local DEFAULTS = { axis = "0 0 0", range = "0 0", strength = "0", velocity = "0", visible = "0", jointtype = "0" }

---@param joint FileParserEnvObjJoint|FileParserEnvObj Rows.sharedChoice's callbacks are typed for objects
---@param key string
---@return string? the line's value, or its default (nil for pos: no default anchor)
local function valueOf(joint, key)
    return joint.props[key] or DEFAULTS[key]
end

---Placeholder for number `index` of a prop that has `count` numbers
---@param joints FileParserEnvObjJoint[]
---@param key string
---@param index integer
---@param count integer
---@return string
local function hintOf(joints, key, index, count)
    return Rows.sharedChoice(joints, function(joint)
        local value = valueOf(joint, key)
        if value == nil then return "-" end
        return Rows.formatHint(Joints.parseNumbers(value, count)[index])
    end) or "-"
end

---Row of one prop's numbers (axis x y z, range high low, strength), the same input row as the other
---tabs (Rows.createInputRow). Enter sets that number on every selected joint, their other numbers stay
---@param holder UIElement
---@param joints FileParserEnvObjJoint[]
---@param label string
---@param name string inwuts list
---@param key string prop
---@param count integer numbers in the prop
---@param help string
local function numberRow(holder, joints, label, name, key, count, help)
    local hints = {}
    for i = 1, count do hints[i] = hintOf(joints, key, i, count) end
    inwuts[name] = Rows.createInputRow(label, holder, function(inputs, index)
        local value = tonumber(inputs[index].textfieldstr[1])
        if value then Joints.setComponent(selectedJoints(), key, index, count, value) end
    end, hints, help)
end

---Sets a whole prop to one value on the selected joints
---@param key string
---@param value string
local function setAll(key, value)
    Joints.setProps(selectedJoints(), key, function() return value end)
end

---Pos row: the selected joints' center (the gizmo's pivot), a typed axis moves them together so the
---center gets there. Joints without a pos line get the typed value (nothing to move from)
---@param holder UIElement
---@param joints FileParserEnvObjJoint[]
local function buildPos(holder, joints)
    local target = Joints.target(joints)
    local hints = target and Rows.formatHints(target.pivot()) or { "-", "-", "-" }
    inwuts.jointPos = Rows.createInputRow("Pos", holder, function(inputs, index)
        local value = tonumber(inputs[index].textfieldstr[1])
        if not value then return end
        local list = selectedJoints()
        local now = Joints.target(list) -- read again: a reload replaces the joint tables
        if not now then
            Joints.setComponent(list, "pos", index, 3, value)
            return
        end
        local offset = { 0, 0, 0 }
        offset[index] = value - now.pivot()[index]
        now.moveBy(offset)
    end, hints,
        "Anchor: where the game joins the two objects, in\n" ..
        "world coordinates. Several joints: their center,\n" ..
        "they move together. The Move gizmo (Shift + Q)\n" ..
        "drags them, Recenter puts each between its objects.")
end

---Type row: the jointtype line, a whole number
---@param holder UIElement
---@param joints FileParserEnvObjJoint[]
local function buildType(holder, joints)
    local hint = Rows.sharedChoice(joints, function(joint) return valueOf(joint, "jointtype") end) or "-"
    inwuts.jointType = Rows.createInputRow("Type", holder, function(inputs)
        local value = tonumber(inputs[1].textfieldstr[1])
        if value then setAll("jointtype", tostring(math.floor(value))) end
    end, { hint }, "The jointtype line, a number (most mods write 0).")
end

---Visible row: the visible line, the selected joints' shared value lit
---@param holder UIElement
---@param joints FileParserEnvObjJoint[]
local function buildVisible(holder, joints)
    local visible = Rows.sharedChoice(joints, function(joint) return valueOf(joint, "visible") end)
    Rows.createChoiceRow("Visible", holder, {
        { label = "Visible", value = "1" },
        { label = "Hidden", value = "0" },
    }, visible, function(value) setAll("visible", value) end,
        "The visible line, lit when all selected joints\nhave it. Without the line: hidden.")
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

    buildPos(holder, joints)
    numberRow(holder, joints, "Axis", "jointAxis", "axis", 3,
        "The axis line, three numbers as the file writes\n" ..
        "them (mods use both directions like 0 1 0 and\n" ..
        "angles like 0 -90 0).")
    numberRow(holder, joints, "Range", "jointRange", "range", 2,
        "Rotation limits, high then low as the file writes\n" ..
        "them (e.g. 3.6 -3.6).")
    numberRow(holder, joints, "Strength", "jointStrength", "strength", 1,
        "The joint's strength (its motor force).")
    numberRow(holder, joints, "Velocity", "jointVelocity", "velocity", 1,
        "The joint's motor velocity.")
    buildType(holder, joints)
    buildVisible(holder, joints)
    Rows.createToggleButtonRow("", holder, {
        { label = "Recenter", active = false, onClick = function() Joints.centerPos(selectedJoints()) end },
    }, "Moves each selected joint's anchor halfway\nbetween the two objects it links.")
end

---@type EditorPanelModule
return {
    blocks = { { name = "joint", build = buildJoints, panel = "joint", row = 0, rows = ROWS } },
    inputs = { rebuilt = INPUT_LISTS },
}
