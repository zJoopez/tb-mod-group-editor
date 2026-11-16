















local editor = {}
local ModData = MGE.ModData
local History = MGE.History
local Joints = MGE.Joints
local Widgets = MGE.Widgets
local getSelected = ModData.getSelected

local getEditSelection = ModData.getEditSelection

local Rows = dofile(MGE.scriptPath .. "ui/editor_rows.lua")
local inwuts = Rows.inputs
















local Core = dofile(MGE.scriptPath .. "ui/editor_core.lua")
local MODULES = {
    Core,
    dofile(MGE.scriptPath .. "ui/editor_advanced.lua"),
    dofile(MGE.scriptPath .. "ui/editor_thrust.lua"),
    dofile(MGE.scriptPath .. "ui/editor_generate.lua"),
    dofile(MGE.scriptPath .. "ui/editor_player.lua"),
    dofile(MGE.scriptPath .. "ui/editor_link.lua"),
    dofile(MGE.scriptPath .. "ui/editor_joint.lua"),
    dofile(MGE.scriptPath .. "ui/editor_atmo.lua"),
    dofile(MGE.scriptPath .. "ui/editor_misc.lua"),
}

local ROW_H = MGE.Widgets.ROW_H


local PANEL_H = MGE.Widgets.PANEL_ROWS * ROW_H
local PANELS = {
    core = { height = PANEL_H },
    advanced = { height = PANEL_H },
    thrust = { height = PANEL_H },
    generate = { height = PANEL_H },
    player = { height = PANEL_H },
    jointLink = { height = PANEL_H },
    joint = { height = PANEL_H },
    atmo = { height = PANEL_H },
    misc = { height = PANEL_H },
}



local FIXED = {}

local BLOCKS = {}

local BLOCK_ORDER = {}

local REBUILT_INPUTS = {}
for _, module in ipairs(MODULES) do
    for _, block in ipairs(module.fixed or {}) do table.insert(FIXED, block) end
    for _, block in ipairs(module.blocks or {}) do
        BLOCKS[block.name] = block
        table.insert(BLOCK_ORDER, block.name)
    end
    local inputs = module.inputs or {}
    for _, key in ipairs(inputs.rebuilt or {}) do table.insert(REBUILT_INPUTS, key) end
end


local panels = {}

local blocks = {}





local shownPanel = nil

local dirty = {}

local rebuildBlocks



function editor.applyPanel(id)
    local panel = PANELS[id]
    if not panel then return end
    shownPanel = id
    for panelId, element in pairs(panels) do
        if not element.destroyed then
            if panelId == id then element:show(true) else element:hide(true) end
        end
    end


    local stale = {}
    for _, name in ipairs(BLOCK_ORDER) do
        if dirty[name] and BLOCKS[name].panel == id then stale[#stale + 1] = name end
    end
    if #stale > 0 then rebuildBlocks(stale) end
end


local function reapplyTabs()
    if MGE.Main and MGE.Main.applyTab then MGE.Main.applyTab() end
end



local function saveTypedProperties()
    local saved = {}
    for _, key in ipairs(REBUILT_INPUTS) do
        saved[key] = {}
        for i, input in ipairs(inwuts[key] or {}) do

            saved[key][i] = input ~= Rows.applying and input.textfieldstr[1] or nil
        end
    end
    return saved
end


local function restoreTypedProperties(saved)
    for key, texts in pairs(saved) do
        for i, input in ipairs(inwuts[key] or {}) do
            local text = texts[i]
            if text and text ~= "" then
                input.textfieldstr[1] = text
                input.textfieldindex = #text
            end
        end
    end
end



local function findFocusedInput()
    for _, key in ipairs(REBUILT_INPUTS) do
        for i, input in ipairs(inwuts[key] or {}) do

            if input.keyboard and input.displayed and not input.destroyed then return key, i end
        end
    end
    return nil, nil
end



local function focusInput(input)
    for _, v in ipairs(UIKeyboardHandler) do v.keyboard = v.permanentListener end
    input.keyboard = true
    input:enableMenuKeyboard()
    disable_camera_movement()
end




rebuildBlocks = function(names)
    if not blocks.measured or blocks.measured.destroyed then return end

    local now = {}
    for _, name in ipairs(names) do
        if shownPanel and BLOCKS[name].panel ~= shownPanel then
            dirty[name] = true
        else
            dirty[name] = nil
            now[#now + 1] = name
        end
    end
    if #now == 0 then return end
    names = now
    local selected = getEditSelection()
    local typed = saveTypedProperties()
    local focusKey, focusIndex = findFocusedInput()
    for _, name in ipairs(names) do
        Widgets.clearChildren(blocks[name])


        local ok, err = pcall(BLOCKS[name].build, blocks[name], selected)
        if not ok then MGE.say("editor panel error (" .. name .. "): " .. tostring(err)) end
    end
    restoreTypedProperties(typed)
    reapplyTabs()


    local refocus = focusKey and focusIndex and (inwuts[focusKey] or {})[focusIndex] or nil
    if refocus and not refocus.destroyed and refocus.displayed then focusInput(refocus) end
end

Rows.refreshBlocks = rebuildBlocks
Rows.refreshProperties = function() rebuildBlocks(BLOCK_ORDER) end

Rows.refreshMeasured = function() rebuildBlocks({ "measured" }) end
MGE.Transforms.onChanged = Rows.refreshMeasured


function editor.onSelectionChanged()
    Rows.refreshProperties()
end


local function duplicateAtmo()
    local selected = ModData.getSelectedAtmo()
    if #selected == 0 then return end
    if #selected > MGE.AtmoLayer.room() then
        MGE.say("no room for " .. #selected .. " more atmo objects (Settings > Max atmo objects)")
        return
    end
    local atmoObjs = ModData.parsed.atmo
    for _, obj in ipairs(selected) do
        local copy = { kind = "atmo", props = ModData.copy(obj.props), lines = obj.lines, selected = true }
        obj.selected = nil
        atmoObjs[#atmoObjs + 1] = copy
        copy.id = #atmoObjs
    end
    History.commit()
    MGE.Main.updateWindow()
end

local function duplicate()
    if MGE.Main.listTab == "atmo" then return duplicateAtmo() end
    local selected = getSelected()
    if #selected == 0 then return end

    local linkedJoints = Joints.getLinked(Joints.idSet(selected))
    if not Joints.haveRoom(#linkedJoints) then return end
    local linkedIds = Joints.getObjectIds(linkedJoints)
    local plans = {}
    for i, obj in ipairs(selected) do
        plans[i] = { pool = ModData.isStatic(obj, true) and "static" or "nonStatic", linked = linkedIds[obj.id] or false }
    end
    local ids = ModData.allocateIds(plans)
    if not ids then return end

    local idMap = {}
    for i, obj in ipairs(selected) do
        local copy = ModData.copy(obj)
        copy.id = ids[i]
        copy.props = ModData.copy(obj.props)


        copy.props.flag = copy.props.flag or tostring(get_obj_flag(obj.id - 1) or 0)
        table.insert(ModData.parsed.env_obj, copy)
        idMap[obj.id] = copy.id
        obj.selected = false
    end
    Joints.copyLinked(Joints.getLinked(idMap), idMap)
    ModData.sortObjects()
    History.commit()
    MGE.apply()
end

local function delete()
    if MGE.Main.listTab == "atmo" then
        MGE.AtmoLayer.removeSelected()
        History.commit()
        MGE.Main.updateWindow()
        return
    end
    local deleted = {}
    for i = #ModData.parsed.env_obj, 1, -1 do
        local obj = ModData.parsed.env_obj[i]
        if obj.selected then
            deleted[obj.id] = true
            table.remove(ModData.parsed.env_obj, i)
            ModData.releaseId(obj.id)
        end
    end
    Joints.removeLinkedToAny(deleted)
    History.commit()
    MGE.apply()
end



local function onDeleteClick()
    local atmo = MGE.Main.listTab == "atmo"
    local count = #getEditSelection()
    if count == 0 or (MGE.confirmOverlay and not MGE.confirmOverlay.destroyed) then return end
    local message = "Delete " .. count .. " selected " .. (atmo and "atmo " or "") .. "object" .. (count == 1 and "" or "s") ..
        "?\nUndo can bring them back."
    MGE.confirm(message, delete)
end




local function addHolder(parent, block)
    return panels[block.panel]:addChild({
        pos = { 0, block.row * ROW_H },
        size = { parent.size.w, block.rows * ROW_H },
    })
end


function editor.create(parent)
    dirty = {}

    panels = {}
    for id, panel in pairs(PANELS) do
        panels[id] = parent:addChild({
            pos = { 0, 0 },
            size = { parent.size.w, panel.height },
        })
    end
    local selected = getEditSelection()

    for _, block in ipairs(FIXED) do
        block.build(addHolder(parent, block), selected)
    end
    blocks = {}
    for _, name in ipairs(BLOCK_ORDER) do
        local block = BLOCKS[name]
        blocks[name] = addHolder(parent, block)
        block.build(blocks[name], selected)
    end



end


editor.duplicate = duplicate
editor.deleteSelected = onDeleteClick

MGE.Editor = editor
return editor
