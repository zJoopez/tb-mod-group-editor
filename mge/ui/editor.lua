-- Editor area under the object list: one panel per tab, picked by the window's tab row
-- (Main.applyTab -> editor.applyPanel). Each tab's rows live in their own file:
--   core:     ui/editor_core.lua      Pos, Rot, Scale, Color, Mass, Shape, Visible
--   advanced: ui/editor_advanced.lua  Friction, Bounce, Flags, Model, Ids (Reindex)
--   thrust:   ui/editor_thrust.lua    Frames, Direction, Axes (World / Object / Off)
--   generate: ui/editor_generate.lua  Align, Amount, Gap, Angle, Size, Increment, Position, Generate / To view
--   player:   ui/editor_player.lua    Pos, Rot, Scale, parts of the selected players (the Players list's Core tab)
--   jointLink: ui/editor_link.lua     the 2 linked objects (grid), Create / Update, Reset (the Joints list's Link tab)
--   joint:    ui/editor_joint.lua     Pos, Axis, Range, Strength, Velocity, Type (the Joints list's Properties tab)
--   atmo:     ui/editor_atmo.lua      Depth, Graphics levels, kept lines, To objects, Save atmo (the Atmo list's
--                                     Atmo tab; its Core tab is core, on the selected atmo objects)
-- Shared row widgets are in ui/editor_rows.lua, the transform math in utils/transforms.lua.
-- Every block of rows has its own holder. Fixed blocks are built once (typed values stay), the
-- others are rebuilt when the selection or the objects change, so their placeholders / highlights
-- show current values (typed text is carried over the rebuild).

local editor = {}
local ModData = MGE.ModData
local History = MGE.History
local Joints = MGE.Joints
local Widgets = MGE.Widgets
local getSelected = ModData.getSelected
-- what the panels show and edit: the selected atmo objects on the Atmo list (its Core tab is this Core)
local getEditSelection = ModData.getEditSelection

local Rows = dofile(MGE.scriptPath .. "ui/editor_rows.lua")
local inwuts = Rows.inputs

---@class EditorBlock
---@field name string? rebuilt blocks only, used by Rows.refreshBlocks
---@field build fun(holder: UIElement, selected: FileParserEnvObj[])
---@field panel string
---@field row integer first row in the panel
---@field rows integer

---@class EditorPanel
---@field height number

---@class EditorPanelModule
---@field fixed EditorBlock[]? built once
---@field blocks EditorBlock[]? rebuilt with the selection, in this order
---@field inputs { fixed: string[]?, rebuilt: string[]? }? Rows.inputs lists the module fills

local Core = dofile(MGE.scriptPath .. "ui/editor_core.lua") ---@type EditorPanelModule
local MODULES = {
    Core,
    dofile(MGE.scriptPath .. "ui/editor_advanced.lua"),
    dofile(MGE.scriptPath .. "ui/editor_thrust.lua"),
    dofile(MGE.scriptPath .. "ui/editor_generate.lua"),
    dofile(MGE.scriptPath .. "ui/editor_player.lua"), -- the Players list's Core tab
    dofile(MGE.scriptPath .. "ui/editor_link.lua"), -- the Joints list's Link tab
    dofile(MGE.scriptPath .. "ui/editor_joint.lua"), -- the Joints list's Properties tab
    dofile(MGE.scriptPath .. "ui/editor_atmo.lua"), -- the Atmo list's Atmo tab
    dofile(MGE.scriptPath .. "ui/editor_misc.lua"), -- the World list's panel
}

local ROW_H = MGE.Widgets.ROW_H
-- panel heights, all as tall as the tallest (Generate, 8 rows). The editor area in ui/main.lua fits them.
-- No Reset inputs button: the editor's fields empty themselves once applied (ui/editor_rows.lua)
local PANEL_H = 8 * ROW_H
local PANELS = {
    core = { height = PANEL_H },
    advanced = { height = PANEL_H },
    thrust = { height = PANEL_H },
    generate = { height = PANEL_H },
    player = { height = PANEL_H }, -- the Players list's Core tab (TAB_SETS in ui/main.lua)
    jointLink = { height = PANEL_H }, -- the Joints list's Link tab
    joint = { height = PANEL_H }, -- the Joints list's Properties tab
    atmo = { height = PANEL_H }, -- the Atmo list's Atmo tab
    misc = { height = PANEL_H }, -- the World list's panel
}

-- collected from the modules: fixed and rebuilt blocks, rebuilt block names in build order, input lists
---@type EditorBlock[]
local FIXED = {}
---@type table<string, EditorBlock>
local BLOCKS = {}
---@type string[]
local BLOCK_ORDER = {}
-- the rebuilt input lists keep typed text over a rebuild
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

---@type table<string, UIElement>
local panels = {}
---@type table<string, UIElement> holders of the rebuilt blocks by name
local blocks = {}
-- Only the shown panel's blocks are rebuilt (a selection change, a list switch, an edit): the others are
-- marked dirty and rebuilt when their panel is shown (editor.applyPanel). Rebuilding every panel's blocks
-- read the whole selection once per block: with thousands of atmo objects selected, switching lists or
-- selecting froze for a moment over panels nobody could see
---@type string? the shown panel's id, nil until the first is shown (everything is built then)
local shownPanel = nil
---@type table<string, boolean> rebuilt blocks out of date, by name
local dirty = {}
---@type fun(names: string[])
local rebuildBlocks

---Shows one editor panel, called by Main.applyTab
---@param id string "core"|"advanced"|"thrust"|"generate"|"player"|"jointLink"|"joint"
function editor.applyPanel(id)
    local panel = PANELS[id]
    if not panel then return end
    shownPanel = id
    for panelId, element in pairs(panels) do
        if not element.destroyed then
            if panelId == id then element:show(true) else element:hide(true) end
        end
    end
    -- its blocks that changed while it was hidden (rebuildBlocks calls back here through reapplyTabs: the
    -- list is empty by then)
    local stale = {}
    for _, name in ipairs(BLOCK_ORDER) do
        if dirty[name] and BLOCKS[name].panel == id then stale[#stale + 1] = name end
    end
    if #stale > 0 then rebuildBlocks(stale) end
end

---Rebuilt children are visible by default, let the window re-apply which tab/panel is shown
local function reapplyTabs()
    if MGE.Main and MGE.Main.applyTab then MGE.Main.applyTab() end
end

---Text typed in the rebuilt input rows, kept over a rebuild
---@return table<string, string[]>
local function saveTypedProperties()
    local saved = {}
    for _, key in ipairs(REBUILT_INPUTS) do
        saved[key] = {}
        for i, input in ipairs(inwuts[key] or {}) do
            -- the field being applied (Rows.applying) comes back empty: its placeholder shows the new value
            saved[key][i] = input ~= Rows.applying and input.textfieldstr[1] or nil
        end
    end
    return saved
end

---@param saved table<string, string[]>
local function restoreTypedProperties(saved)
    for key, texts in pairs(saved) do
        for i, input in ipairs(inwuts[key] or {}) do
            local text = texts[i]
            if text and text ~= "" then
                input.textfieldstr[1] = text
                input.textfieldindex = #text -- cursor at the end
            end
        end
    end
end

---Rebuilt input that has keyboard focus, as its inwuts key and index
---@return string? key, integer? index
local function findFocusedInput()
    for _, key in ipairs(REBUILT_INPUTS) do
        for i, input in ipairs(inwuts[key] or {}) do
            -- hide() doesn't clear keyboard, a field on a hidden tab isn't focused
            if input.keyboard and input.displayed and not input.destroyed then return key, i end
        end
    end
    return nil, nil
end

---Gives a text field keyboard focus, same as clicking it (UIElement.handleMouseDn)
---@param input UIElement
local function focusInput(input)
    for _, v in ipairs(UIKeyboardHandler) do v.keyboard = v.permanentListener end
    input.keyboard = true
    input:enableMenuKeyboard()
    disable_camera_movement()
end

---Rebuilds the named blocks with the current selection, typed text is kept and the field that had
---focus gets it back (applying a value with Enter rebuilds the rows, you can keep trying values)
---@param names string[]
rebuildBlocks = function(names)
    if not blocks.measured or blocks.measured.destroyed then return end
    -- blocks of hidden panels wait until theirs is shown
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
    local selected = getEditSelection() -- read once, every row shows values of the same objects
    local typed = saveTypedProperties()
    local focusKey, focusIndex = findFocusedInput()
    for _, name in ipairs(names) do
        Widgets.clearChildren(blocks[name])
        -- one failing block must not stop the rest: the blocks after it would keep old rows, and
        -- reapplyTabs below would be skipped, leaving every panel's new rows visible on top of each other
        local ok, err = pcall(BLOCKS[name].build, blocks[name], selected)
        if not ok then MGE.say("editor panel error (" .. name .. "): " .. tostring(err)) end
    end
    restoreTypedProperties(typed)
    reapplyTabs()

    ---@type UIElement?
    local refocus = focusKey and focusIndex and (inwuts[focusKey] or {})[focusIndex] or nil
    if refocus and not refocus.destroyed and refocus.displayed then focusInput(refocus) end
end

Rows.refreshBlocks = rebuildBlocks
Rows.refreshProperties = function() rebuildBlocks(BLOCK_ORDER) end
-- after a move / rotate / scale only the measured values change
Rows.refreshMeasured = function() rebuildBlocks({ "measured" }) end
MGE.Transforms.onChanged = Rows.refreshMeasured

---Called when the selection changes: refresh current values
function editor.onSelectionChanged()
    Rows.refreshProperties()
end

---Duplicate on the Atmo list: copies of the selected atmo objects with all their lines, new names, selected
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
        obj.selected = nil -- selection moves to the copies
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
    -- only joints between selected objects are copied, so only those copies need low ids
    local linkedJoints = Joints.getLinked(Joints.idSet(selected))
    if not Joints.haveRoom(#linkedJoints) then return end
    local linkedIds = Joints.getObjectIds(linkedJoints)
    local plans = {}
    for i, obj in ipairs(selected) do
        plans[i] = { pool = ModData.isStatic(obj, true) and "static" or "nonStatic", linked = linkedIds[obj.id] or false }
    end
    local ids = ModData.allocateIds(plans) -- all or nothing
    if not ids then return end

    local idMap = {} -- original id -> copy id, used to copy joints between duplicated objects
    for i, obj in ipairs(selected) do
        local copy = ModData.copy(obj)
        copy.id = ids[i]
        copy.props = ModData.copy(obj.props) -- don't share props with the original
        -- the game flag is read by id, a copy without a flag line could get a different default
        -- (objects moved by allocateIds already have their flag written)
        copy.props.flag = copy.props.flag or tostring(get_obj_flag(obj.id - 1) or 0)
        table.insert(ModData.parsed.env_obj, copy)
        idMap[obj.id] = copy.id
        obj.selected = false -- selection moves to the copies (copy keeps selected = true)
    end
    Joints.copyLinked(Joints.getLinked(idMap), idMap)
    ModData.sortObjects()
    History.commit()
    MGE.apply()
end

local function delete()
    if MGE.Main.listTab == "atmo" then -- the atmo objects: not in the .tbm, no reload
        MGE.AtmoLayer.removeSelected()
        History.commit()
        MGE.Main.updateWindow()
        return
    end
    local deleted = {}
    for i = #ModData.parsed.env_obj, 1, -1 do -- iterating backwards to prevent index issues when removing
        local obj = ModData.parsed.env_obj[i]
        if obj.selected then
            deleted[obj.id] = true
            table.remove(ModData.parsed.env_obj, i)
            ModData.releaseId(obj.id)
        end
    end
    Joints.removeLinkedToAny(deleted) -- a joint can't point to a missing object
    History.commit()
    MGE.apply()
end

---Asks for confirmation with Toribash's own popup (TBMenu:showConfirmationWindow) before deleting what the
---shown list has selected: objects, or atmo objects
local function onDeleteClick()
    local atmo = MGE.Main.listTab == "atmo"
    local count = #getEditSelection()
    if count == 0 or (MGE.confirmOverlay and not MGE.confirmOverlay.destroyed) then return end
    local message = "Delete " .. count .. " selected " .. (atmo and "atmo " or "") .. "object" .. (count == 1 and "" or "s") ..
        "?\nUndo can bring them back."
    MGE.confirm(message, delete) -- Enter / Continue deletes, Esc / Cancel doesn't
end

---@param parent UIElement
---@param block EditorBlock
---@return UIElement holder
local function addHolder(parent, block)
    return panels[block.panel]:addChild({
        pos = { 0, block.row * ROW_H },
        size = { parent.size.w, block.rows * ROW_H },
    })
end

---@param parent UIElement editor container from ui/main.lua
function editor.create(parent)
    dirty = {} -- every block is built below
    -- all panels start at the top of the editor area
    panels = {}
    for id, panel in pairs(PANELS) do
        panels[id] = parent:addChild({
            pos = { 0, 0 },
            size = { parent.size.w, panel.height },
        })
    end
    local selected = getEditSelection()
    -- fixed blocks first (built once), then the rebuilt ones
    for _, block in ipairs(FIXED) do
        block.build(addHolder(parent, block), selected)
    end
    blocks = {}
    for _, name in ipairs(BLOCK_ORDER) do
        local block = BLOCKS[name]
        blocks[name] = addHolder(parent, block)
        block.build(blocks[name], selected)
    end

    -- Duplicate/Delete are in the list's button bar (Main.setListActions), Save in the toolbar
    -- (ui/main.lua). Positions and visibility are applied by Main.applyTab after create
end

-- used by the object list's Duplicate/Delete buttons
editor.duplicate = duplicate
editor.deleteSelected = onDeleteClick -- asks for confirmation first

MGE.Editor = editor
return editor
