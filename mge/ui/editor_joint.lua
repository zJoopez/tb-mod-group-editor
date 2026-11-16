-- Joints list's Properties tab. Enter in a field applies it to every selected joint as one undo step,
-- like the object rows. Joints have no live setter, so each change saves and reloads. Which objects a
-- joint links is set on the Link tab (ui/editor_link.lua)
--   Pos:      the anchor, the point it turns around. Like the Core tab's Pos: the selected joints'
--             center, a typed axis moves them together so the center gets there (as the Move gizmo
--             does, Joints.target in utils/joints.lua). Recenter (the last row) puts each halfway
--             between its two objects. Without a pos line ("none") the game locks the two objects
--             together (mge_tests/joint_nopos.tbm): MGE leaves it so, a typed value or Recenter
--             makes it a hinge (Joints.setPosAxis starts from the midpoint)
--   Axis:     the axis line, a world-space direction (mge_tests/joint_axis.tbm: rotating an object
--             doesn't turn it, so MGE turns it with rotated objects, utils/transforms.lua). Its length
--             matters: 0 0 90 throws the object around
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
    line:addAdaptedText(text, nil, nil, MGE.Widgets.FONT, LEFTMID, MGE.Widgets.TEXT_SCALE, nil, nil)
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
    local hints, exact = {}, {}
    for i = 1, count do
        hints[i] = hintOf(joints, key, i, count)
        -- shared value: the wheel steps from it exactly (an axis like 0.6084998164 shows 0.61)
        local shared = Rows.sharedChoice(joints, function(joint)
            local value = valueOf(joint, key)
            return value and Joints.parseNumbers(value, count)[i]
        end)
        exact[i] = type(shared) == "number" and shared or nil
    end
    inwuts[name] = Rows.createInputRow(label, holder, function(inputs, index)
        local value = tonumber(inputs[index].textfieldstr[1])
        if value then Joints.setComponent(selectedJoints(), key, index, count, value) end
    end, hints, help, nil, { exact = exact })
end

---Sets a whole prop to one value on the selected joints
---@param key string
---@param value string
local function setAll(key, value)
    Joints.setProps(selectedJoints(), key, function() return value end)
end

---Pos row: the selected joints' center (the gizmo's pivot), a typed axis moves them together so the
---center gets there. Joints without a pos line start from their objects' midpoint (Joints.setPosAxis)
---@param holder UIElement
---@param joints FileParserEnvObjJoint[]
local function buildPos(holder, joints)
    local target = Joints.target(joints)
    local hints = target and Rows.formatHints(target.pivot()) or { "none", "none", "none" }
    -- the wheel steps from the exact center; locked joints only ("none"): from their objects' midpoint
    local exact = target and target.pivot()
    if not exact then
        local sum, n = { 0, 0, 0 }, 0
        for _, joint in ipairs(joints) do
            local a, b = Joints.objectById(joint.obj1), Joints.objectById(joint.obj2)
            if a and b then
                local m = Joints.parseNumbers(Joints.midpoint(a, b), 3)
                for k = 1, 3 do sum[k] = sum[k] + m[k] end
                n = n + 1
            end
        end
        if n > 0 then exact = { sum[1] / n, sum[2] / n, sum[3] / n } end
    end
    inwuts.jointPos = Rows.createInputRow("Pos", holder, function(inputs, index)
        local value = tonumber(inputs[index].textfieldstr[1])
        -- the list read again: a reload replaces the joint tables
        if value then Joints.setPosAxis(selectedJoints(), index, value) end
    end, hints,
        "The point it turns around (world coordinates).\n" ..
        "None: the game locks the two objects together,\n" ..
        "a typed value makes it a hinge there.", nil, { exact = exact or nil })
end

---Type row: the jointtype line, a whole number
---@param holder UIElement
---@param joints FileParserEnvObjJoint[]
local function buildType(holder, joints)
    local hint = Rows.sharedChoice(joints, function(joint) return valueOf(joint, "jointtype") end) or "-"
    inwuts.jointType = Rows.createInputRow("Type", holder, function(inputs)
        local value = tonumber(inputs[1].textfieldstr[1])
        if value then setAll("jointtype", tostring(math.floor(value))) end
    end, { hint }, "The jointtype line, a number (most mods write 0).", nil, { whole = true })
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
        "Turning direction in world space, any numbers\n" ..
        "(0 0 1, 0.5 0 1...), negative reverses it. Very\n" ..
        "big ones like 0 0 90 can make it unstable.")
    numberRow(holder, joints, "Range", "jointRange", "range", 2,
        "Limits, high then low (1.5: 90 degrees, 3: 180).\n" ..
        "4 -4 with a motor: keeps turning.")
    numberRow(holder, joints, "Strength", "jointStrength", "strength", 1,
        "The joint's strength (its motor force).")
    numberRow(holder, joints, "Velocity", "jointVelocity", "velocity", 1,
        "The joint's motor velocity.")
    buildType(holder, joints)
    buildVisible(holder, joints)
    Rows.createToggleButtonRow("", holder, {
        { label = "Recenter", active = false, onClick = function() Joints.centerPos(selectedJoints()) end },
    }, "Puts each selected joint's anchor halfway\nbetween its two objects (a locked one: a hinge).")
end

---@type EditorPanelModule
return {
    blocks = { { name = "joint", build = buildJoints, panel = "joint", row = 0, rows = ROWS } },
    inputs = { rebuilt = INPUT_LISTS },
}
