















local Rows = MGE.EditorRows
local Joints = MGE.Joints
local inwuts = Rows.inputs

local ROWS = MGE.Widgets.PANEL_ROWS

local INPUT_LISTS = { "jointPos", "jointAxis", "jointRange", "jointStrength", "jointVelocity", "jointType" }


local function selectedJoints()
    return MGE.Main.selectedJointList()
end





local function addLine(holder, text, row)
    local line = holder:addChild({
        pos = { 8, row * (holder.size.h / ROWS) },
        size = { holder.size.w - 16, holder.size.h / ROWS },
    })
    line:addAdaptedText(text, nil, nil, MGE.Widgets.FONT, LEFTMID, MGE.Widgets.TEXT_SCALE, nil, nil)
end




local DEFAULTS = { axis = "0 0 0", range = "0 0", strength = "0", velocity = "0", visible = "0", jointtype = "0" }




local function valueOf(joint, key)
    return joint.props[key] or DEFAULTS[key]
end








local function hintOf(joints, key, index, count)
    return Rows.sharedChoice(joints, function(joint)
        local value = valueOf(joint, key)
        if value == nil then return "-" end
        return Joints.parseNumbers(value, count)[index]
    end) or "-"
end










local function numberRow(holder, joints, label, name, key, count, help)
    local hints = {}
    for i = 1, count do hints[i] = hintOf(joints, key, i, count) end
    inwuts[name] = Rows.createInputRow(label, holder, function(inputs, index)
        local value = tonumber(inputs[index].textfieldstr[1])
        if value then Joints.setComponent(selectedJoints(), key, index, count, value) end
    end, hints, help)
end




local function setAll(key, value)
    Joints.setProps(selectedJoints(), key, function() return value end)
end





local function buildPos(holder, joints)


    local target = Joints.target(joints)
    local hints = target and target.pivot()
    if not hints then
        local sum, n = { 0, 0, 0 }, 0
        for _, joint in ipairs(joints) do
            local m = Joints.jointMidpoint(joint)
            if m then
                for k = 1, 3 do sum[k] = sum[k] + m[k] end
                n = n + 1
            end
        end
        hints = {}
        for k = 1, 3 do hints[k] = { text = "none", value = n > 0 and sum[k] / n or nil } end
    end
    inwuts.jointPos = Rows.createInputRow("Pos", holder, function(inputs, index)
        local value = tonumber(inputs[index].textfieldstr[1])

        if value then Joints.setPosAxis(selectedJoints(), index, value) end
    end, hints,
        "The point it turns around (world coordinates).\n" ..
        "None: the game locks the two objects together,\n" ..
        "a typed value makes it a hinge there.")
end




local function buildType(holder, joints)
    local hint = Rows.sharedChoice(joints, function(joint) return valueOf(joint, "jointtype") end) or "-"
    inwuts.jointType = Rows.createInputRow("Type", holder, function(inputs)
        local value = tonumber(inputs[1].textfieldstr[1])
        if value then setAll("jointtype", tostring(math.floor(value))) end
    end, { hint }, "The jointtype line, a number (most mods write 0).", nil, { whole = true })
end




local function buildVisible(holder, joints)
    local visible = Rows.sharedChoice(joints, function(joint) return valueOf(joint, "visible") end)
    Rows.createChoiceRow("Visible", holder, {
        { label = "Visible", value = "1" },
        { label = "Hidden", value = "0" },
    }, visible, function(value) setAll("visible", value) end,
        "The visible line, lit when all selected joints\nhave it. Without the line: hidden.")
end


local function buildJoints(holder)
    Rows.begin()
    for _, name in ipairs(INPUT_LISTS) do inwuts[name] = {} end
    local joints = selectedJoints()
    if #joints == 0 then
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


return {
    blocks = { { name = "joint", build = buildJoints, panel = "joint", row = 0, rows = ROWS } },
    inputs = { rebuilt = INPUT_LISTS },
}
