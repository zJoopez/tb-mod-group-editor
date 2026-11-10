-- Advanced tab: Friction, Bounce, Hardness, Flags, Model, Ids (Reindex)
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

---Friction, bounce and hardness rows (advanced panel)
---@param holder UIElement
---@param selected FileParserEnvObj[]
local function buildAdvancedProps(holder, selected)
    Rows.begin()
    inwuts.advancedProps = Rows.buildPropertyRows(holder, selected, { { "Friction", "friction" }, { "Bounce", "bounce" }, { "Hardness", "hardness" } })
end

-- flag is a bit mask (MGE.FLAGS), objects without a flag line use the game's value
---@param obj FileParserEnvObj loaded object
---@return integer
local function getFlag(obj)
    return tonumber(obj.props.flag) or get_obj_flag(obj.id - 1) or 0
end

---@param flag integer
---@param bits integer
---@return boolean all bits set
local function hasBits(flag, bits)
    return bit.band(flag, bits) == bits
end

---@param flag integer
---@param bits integer
---@param on boolean
---@return integer flag with bits set or cleared, other bits kept
local function withBits(flag, bits, on)
    return on and bit.bor(flag, bits) or flag - bit.band(flag, bits)
end

---Sets or clears flag bits on selected objects, applied live (set_obj_flag) and saved with the
---next save. Not for the static bit, the game only reads that when the mod loads (setStatic)
---@param bits integer
---@param on boolean
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

---Makes selected objects static or dynamic. Ids don't change: dynamic objects above id 48 are
---treated partly as static by the game, the window warns about them until Reindex moves them down.
---Saved instead of set live: tested in game, set_obj_flag doesn't switch static/dynamic, the game
---only reads it when the mod loads. The reload also refreshes the dynamic count and warning.
---@param static boolean
local function setStatic(static)
    local changed = false
    for _, v in ipairs(getSelected()) do
        if ModData.isStatic(v, true) ~= static then
            v.props.flag = tostring(withBits(getFlag(v), MGE.FLAGS.STATIC, static)) -- other flags are kept
            changed = true
        end
    end
    if not changed then return end
    History.commit()
    MGE.apply()
end

---Flags row (advanced panel)
---@param holder UIElement
---@param selected FileParserEnvObj[]
local function buildFlags(holder, selected)
    Rows.begin()
    -- highlighted when every selected object has the flag. A click clears it if they all have it,
    -- otherwise sets it on all of them (decided on click, from the selection at that moment)
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

---3d model shown instead of the object's shape (model_name + use_model), nil for no model
---@param obj FileParserEnvObj
---@return string|false model path in mod_assets, false when the object uses no model
local function getModel(obj)
    if obj.props.use_model ~= "1" then return false end
    return ModData.fromModelName(obj.props.model_name, MGE.modPath) or obj.props.model_name or false
end

---Sets model_name / use_model on the selected objects, needs a reload
---@param model string? model path in mod_assets without .obj, nil turns the model off
local function setModel(model)
    local changed = false
    for _, v in ipairs(getSelected()) do
        local useModel = model and "1" or "0"
        local modelName = model and ModData.toModelName(model) or v.props.model_name
        if v.props.use_model ~= useModel or v.props.model_name ~= modelName then
            v.props.use_model = useModel
            v.props.model_name = modelName -- kept when turning the model off, the game ignores it then
            changed = true
        end
    end
    if not changed then return end
    History.commit()
    MGE.apply()
end

---Model row (advanced panel): the model button opens the picker, the trash icon turns the model off
---@param holder UIElement
---@param selected FileParserEnvObj[]
local function buildModel(holder, selected)
    Rows.begin()
    local current = sharedChoice(selected, getModel)
    local row, contentX, contentW = createRow("Model", holder,
        "Draws a .obj from data/mod_assets instead of the shape,\n" ..
        "the shape still collides. Trash icon: no model.")
    local labels = { [false] = "Pick model", mixed = "Mixed" }
    local label = current == nil and "-" or labels[current] or tostring(current)
    local gap = 4
    local h = row.size.h - 4
    local noneW = h -- square icon button, the model name gets the rest
    local modelW = contentW - 4 - gap - noneW
    Widgets.button(row, { x = contentX + 2, y = 2, w = modelW, h = h }, label, function()
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
    -- game's trash icon, like the object list's Delete
    local none = Widgets.iconButton(row, { x = contentX + 2 + modelW + gap, y = 2, w = noneW, h = h },
        "../textures/menu/general/buttons/trash.tga", function() setModel(nil) end, Widgets.PANEL_STYLE)
    TBMenu:displayPopup(none, "No model (remove)")
end

---Dynamic objects can end up above id 48 (the footer warns), this moves them down and static
---objects up, as far as ids allow. Acts on all objects, not the selection
local function reindex()
    local moved, left = ModData.reindex()
    if left > 0 then
        print("reindex: " .. left .. " dynamic objects still above id " .. MGE.MAX_NONSTATIC_OBJECTS ..
            ", make some static")
    end
    if moved == 0 then
        print("reindex: nothing to move")
        return
    end
    History.commit()
    MGE.apply()
    print("reindex moved " .. moved .. " objects")
end

---Ids row (advanced panel), built once: its buttons act on all objects, nothing to refresh
---@param holder UIElement
local function buildIdRows(holder)
    Rows.begin()
    createToggleButtonRow("Ids", holder, {
        { label = "Reindex", active = false, onClick = reindex },
    }, "Moves dynamic objects to ids 1-" .. MGE.MAX_NONSTATIC_OBJECTS .. ", static above.\n" ..
        "Acts on all objects, joints follow.")
end


---@type EditorPanelModule
return {
    fixed = { { build = buildIdRows, panel = "advanced", row = 5, rows = 1 } },
    blocks = {
        { name = "advancedProps", build = buildAdvancedProps, panel = "advanced", row = 0, rows = 3 },
        { name = "flags", build = buildFlags, panel = "advanced", row = 3, rows = 1 },
        { name = "model", build = buildModel, panel = "advanced", row = 4, rows = 1 },
    },
    inputs = { rebuilt = { "advancedProps" } },
}
