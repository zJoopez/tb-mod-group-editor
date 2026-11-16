


local Rows = MGE.EditorRows
local Widgets = MGE.Widgets
local ModData = MGE.ModData
local History = MGE.History
local getSelected = ModData.getSelected
local inwuts = Rows.inputs
local sharedChoice = Rows.sharedChoice
local createRow = Rows.createRow
local createToggleButtonRow = Rows.createToggleButtonRow
local function refreshProperties() Rows.refreshProperties() end




local function buildAdvancedProps(holder, selected)
    Rows.begin()
    inwuts.advancedProps = Rows.buildPropertyRows(holder, selected, { { "Friction", "friction" }, { "Bounce", "bounce" }, { "Hardness", "hardness" } })
end




local function getFlag(obj)
    return tonumber(obj.props.flag) or get_obj_flag(obj.id - 1) or 0
end




local function hasBits(flag, bits)
    return bit.band(flag, bits) == bits
end





local function withBits(flag, bits, on)
    return on and bit.bor(flag, bits) or flag - bit.band(flag, bits)
end





local function setFlagBits(bits, on)
    local changed = false
    for _, v in ipairs(getSelected()) do
        local flag = getFlag(v)
        local newFlag = withBits(flag, bits, on)
        if newFlag ~= flag or v.props.flag == nil then
            v.props.flag = tostring(newFlag)
            set_obj_flag(v.id - 1, newFlag)
            changed = true
        end
    end
    if not changed then return end
    History.commit()
    refreshProperties()
end






local function setStatic(static)
    local changed = false
    for _, v in ipairs(getSelected()) do
        if ModData.isStatic(v, true) ~= static then
            v.props.flag = tostring(withBits(getFlag(v), MGE.FLAGS.STATIC, static))
            changed = true
        end
    end
    if not changed then return end
    History.commit()
    MGE.apply()
end




local function buildFlags(holder, selected)
    Rows.begin()


    local FLAGS = MGE.FLAGS
    local function allHave(objects, bits)
        return sharedChoice(objects, function(obj) return hasBits(getFlag(obj), bits) end) == true
    end
    local function flagButton(label, bits, apply)
        return {
            label = label,
            active = allHave(selected, bits),
            onClick = function()
                local current = getSelected()
                if #current > 0 then apply(not allHave(current, bits)) end
            end,
        }
    end
    createToggleButtonRow("Flags", holder, {
        flagButton("Static", FLAGS.STATIC, setStatic),
        flagButton("Weapon", FLAGS.WEAPON, function(on) setFlagBits(FLAGS.WEAPON, on) end),
        flagButton("Nogrip", FLAGS.UNGRIPPABLE, function(on) setFlagBits(FLAGS.UNGRIPPABLE, on) end),
    }, "Click to toggle, lit when all selected have it.\n" ..
        "Static: doesn't move. Dynamic needs ids 1-" .. MGE.MAX_NONSTATIC_OBJECTS .. " (Reindex).\n" ..
        "Weapon: acts as a weapon. Nogrip: can't be grabbed.")
end




local function getModel(obj)
    if obj.props.use_model ~= "1" then return false end
    return ModData.fromModelName(obj.props.model_name, MGE.modPath) or obj.props.model_name or false
end



local function setModel(model)
    local changed = false
    for _, v in ipairs(getSelected()) do
        local useModel = model and "1" or "0"
        local modelName = model and ModData.toModelName(model) or v.props.model_name
        if v.props.use_model ~= useModel or v.props.model_name ~= modelName then
            v.props.use_model = useModel
            v.props.model_name = modelName
            changed = true
        end
    end
    if not changed then return end
    History.commit()
    MGE.apply()
end




local function buildModel(holder, selected)
    Rows.begin()
    local current = sharedChoice(selected, getModel)
    local row, contentX, contentW = createRow("Model", holder,
        "Draws a .obj from data/mod_assets instead of the shape,\n" ..
        "the shape still collides. Trash icon: no model.")
    local labels = { [false] = "Pick model", mixed = "Mixed" }
    local label = current == nil and "-" or labels[current] or tostring(current)
    local gap, inset = Widgets.GAP, Widgets.INSET
    local h = row.size.h - inset * 2
    local noneW = h
    local modelW = contentW - inset * 2 - gap - noneW
    Widgets.button(row, { x = contentX + inset, y = inset, w = modelW, h = h }, label, function()
        if #getSelected() == 0 then return end
        MGE.FilePicker.open({
            title = "Pick Model",
            root = "data/mod_assets",
            rootLabel = "mod_assets",
            extension = "obj",
            selected = type(current) == "string" and current or nil,
            confirmLabel = "Use model",
            onConfirm = setModel,
        })
    end, nil, Widgets.PANEL_STYLE)

    local none = Widgets.iconButton(row, { x = contentX + inset + modelW + gap, y = inset, w = noneW, h = h },
        "../textures/menu/general/buttons/trash.tga", function() setModel(nil) end, Widgets.PANEL_STYLE)
    Widgets.popupBelow(none, "No model (remove)")
end




local function reindex()
    local moved, left = ModData.reindex()
    if left > 0 then
        MGE.say("reindex: " .. left .. " dynamic objects still above id " .. MGE.MAX_NONSTATIC_OBJECTS ..
            ", make some static")
    end
    if moved == 0 then
        MGE.say("reindex: nothing to move")
        return
    end
    History.commit()
    MGE.apply()
    MGE.say("reindex moved " .. moved .. " objects")
end



local function buildIdRow(holder)
    Rows.begin()
    createToggleButtonRow("Ids", holder, {
        { label = "Reindex", active = false, onClick = reindex },
    }, "Moves dynamic objects to ids 1-" .. MGE.MAX_NONSTATIC_OBJECTS .. ", static above.\n" ..
        "Acts on all objects, joints follow.")
end


return {
    fixed = {
        { build = buildIdRow, panel = "advanced", row = 5, rows = 1 },
    },
    blocks = {
        { name = "advancedProps", build = buildAdvancedProps, panel = "advanced", row = 0, rows = 3 },
        { name = "flags", build = buildFlags, panel = "advanced", row = 3, rows = 1 },
        { name = "model", build = buildModel, panel = "advanced", row = 4, rows = 1 },
    },
    inputs = { rebuilt = { "advancedProps" } },
}
