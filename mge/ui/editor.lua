-- Editor area under the object list: one panel per tab, picked by the window's tab row
-- (Main.applyTab -> editor.applyPanel). Each tab's rows live in their own file:
--   core:     ui/editor_core.lua      Pos/Move, Rot/Rotate, Scale/Resize, Color, Mass, Shape, Visible
--   advanced: ui/editor_advanced.lua  Friction, Bounce, Flags, Model, Ids (Reindex)
--   thrust:   ui/editor_thrust.lua    Frames, Direction, Axes (World / Object / Off)
--   generate: ui/editor_generate.lua  Align, Amount, Gap, Angle, Size, Increment, Position, Generate / To view
--   player:   ui/editor_player.lua    Pos, Rot, Scale, parts of the selected players (the Players list's Core tab)
--   jointLink: ui/editor_link.lua     the 2 linked objects (grid), Create / Update, Delete, Reset (the Joints list's Link tab)
--   joint:    ui/editor_joint.lua     Pos, Axis, Range, Strength, Velocity, Type (the Joints list's Properties tab)
-- Shared row widgets are in ui/editor_rows.lua, the transform math in utils/transforms.lua.
-- Every block of rows has its own holder. Fixed blocks are built once (typed values stay), the
-- others are rebuilt when the selection or the objects change, so their placeholders / highlights
-- show current values (typed text is carried over the rebuild). The reset button is under each panel.

local editor = {}
local ModData = MGE.ModData
local History = MGE.History
local Joints = MGE.Joints
local Widgets = MGE.Widgets
local getSelected = ModData.getSelected

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
---@field ownButtons boolean? the panel has its own buttons in place of the Reset inputs footer

---@class EditorPanelModule
---@field fixed EditorBlock[]? built once
---@field blocks EditorBlock[]? rebuilt with the selection, in this order
---@field inputs { fixed: string[]?, rebuilt: string[]? }? Rows.inputs lists the module fills
---@field applyTransformModes fun(coreShown: boolean)? core only

local Core = dofile(MGE.scriptPath .. "ui/editor_core.lua") ---@type EditorPanelModule
local MODULES = {
    Core,
    dofile(MGE.scriptPath .. "ui/editor_advanced.lua"),
    dofile(MGE.scriptPath .. "ui/editor_thrust.lua"),
    dofile(MGE.scriptPath .. "ui/editor_generate.lua"),
    dofile(MGE.scriptPath .. "ui/editor_player.lua"), -- the Players list's Core tab
    dofile(MGE.scriptPath .. "ui/editor_link.lua"), -- the Joints list's Link tab
    dofile(MGE.scriptPath .. "ui/editor_joint.lua"), -- the Joints list's Properties tab
}

local ROW_H = 30
local FOOTER_GAP = 4
local FOOTER_H = 24 -- reset button
-- panel heights, all as tall as the tallest (Generate, 8 rows) so the reset button stays in place
-- between tabs. The editor area in ui/main.lua fits them with the reset button under them
local PANEL_H = 8 * ROW_H
local PANELS = {
    core = { height = PANEL_H },
    advanced = { height = PANEL_H },
    thrust = { height = PANEL_H },
    generate = { height = PANEL_H },
    player = { height = PANEL_H }, -- the Players list's Core tab (TAB_SETS in ui/main.lua)
    jointLink = { height = PANEL_H, ownButtons = true }, -- the Joints list's Link tab, has its own Reset
    joint = { height = PANEL_H }, -- the Joints list's Properties tab
}

-- collected from the modules: fixed and rebuilt blocks, rebuilt block names in build order, input lists
---@type EditorBlock[]
local FIXED = {}
---@type table<string, EditorBlock>
local BLOCKS = {}
---@type string[]
local BLOCK_ORDER = {}
-- all input lists are cleared by "Reset inputs", the rebuilt ones keep typed text over a rebuild
local ALL_INPUTS, REBUILT_INPUTS = {}, {}
for _, module in ipairs(MODULES) do
    for _, block in ipairs(module.fixed or {}) do table.insert(FIXED, block) end
    for _, block in ipairs(module.blocks or {}) do
        BLOCKS[block.name] = block
        table.insert(BLOCK_ORDER, block.name)
    end
    local inputs = module.inputs or {}
    for _, key in ipairs(inputs.fixed or {}) do table.insert(ALL_INPUTS, key) end
    for _, key in ipairs(inputs.rebuilt or {}) do
        table.insert(ALL_INPUTS, key)
        table.insert(REBUILT_INPUTS, key)
    end
end

---@type table<string, UIElement>
local panels = {}
---@type table<string, UIElement> holders of the rebuilt blocks by name
local blocks = {}
---@type UIElement? reset button, shown under the shown panel
local inputFooter = nil

---Shows the core panel's transform rows in their current mode (ui/editor_core.lua)
local function applyTransformModes()
    Core.applyTransformModes(panels.core ~= nil and not panels.core.destroyed and panels.core.displayed)
end

---Shows one editor panel, called by Main.applyTab
---@param id string "core"|"advanced"|"thrust"|"generate"|"player"|"jointLink"|"joint"
function editor.applyPanel(id)
    local panel = PANELS[id]
    if not panel then return end
    for panelId, element in pairs(panels) do
        if not element.destroyed then
            if panelId == id then element:show(true) else element:hide(true) end
        end
    end
    applyTransformModes() -- after the panel, rebuilt rows start visible
    if inputFooter and not inputFooter.destroyed then
        if panel.ownButtons then
            inputFooter:hide(true)
        else
            inputFooter:show(true)
            inputFooter:moveTo(nil, panel.height + FOOTER_GAP)
        end
    end
end

---Rebuilt children are visible by default, let the window re-apply which tab/panel is shown
local function reapplyTabs()
    if MGE.Main and MGE.Main.applyTab then MGE.Main.applyTab() end
end

---Empties all input fields, placeholders show again
local function clearInputs()
    for _, key in ipairs(ALL_INPUTS) do
        for _, input in ipairs(inwuts[key] or {}) do
            if not input.destroyed then input:clearTextfield() end
        end
    end
end

---Text typed in the rebuilt input rows, kept over a rebuild
---@return table<string, string[]>
local function saveTypedProperties()
    local saved = {}
    for _, key in ipairs(REBUILT_INPUTS) do
        saved[key] = {}
        for i, input in ipairs(inwuts[key] or {}) do saved[key][i] = input.textfieldstr[1] end
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
local function rebuildBlocks(names)
    if not blocks.measured or blocks.measured.destroyed then return end
    local selected = getSelected() -- read once, every row shows values of the same objects
    local typed = saveTypedProperties()
    local focusKey, focusIndex = findFocusedInput()
    for _, name in ipairs(names) do
        Widgets.clearChildren(blocks[name])
        -- one failing block must not stop the rest: the blocks after it would keep old rows, and
        -- reapplyTabs below would be skipped, leaving every panel's new rows visible on top of each other
        local ok, err = pcall(BLOCKS[name].build, blocks[name], selected)
        if not ok then echo("^04[MGE] editor panel error (" .. name .. "): " .. tostring(err)) end
    end
    restoreTypedProperties(typed)
    reapplyTabs()
    applyTransformModes() -- also when the editor isn't the shown tab (applyPanel isn't called then)

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

local function duplicate()
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

---Asks for confirmation with Toribash's own popup (TBMenu:showConfirmationWindow) before deleting
local function onDeleteClick()
    local count = #getSelected()
    if count == 0 or (MGE.confirmOverlay and not MGE.confirmOverlay.destroyed) then return end
    local message = "Delete " .. count .. " selected object" .. (count == 1 and "" or "s") .. "?\nUndo can bring them back."
    -- stored so MGE.quit can close it, cleared by either button
    MGE.confirmOverlay = TBMenu:showConfirmationWindow(message, function()
        MGE.confirmOverlay = nil
        delete()
    end, function()
        MGE.confirmOverlay = nil
    end)
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
    -- all panels start at the top of the editor area
    panels = {}
    for id, panel in pairs(PANELS) do
        panels[id] = parent:addChild({
            pos = { 0, 0 },
            size = { parent.size.w, panel.height },
        })
    end
    local selected = getSelected()
    -- fixed blocks first: the core panel's offset rows register before the measured rows that share
    -- their slot (Core.applyTransformModes shows one of them)
    for _, block in ipairs(FIXED) do
        block.build(addHolder(parent, block), selected)
    end
    blocks = {}
    for _, name in ipairs(BLOCK_ORDER) do
        local block = BLOCKS[name]
        blocks[name] = addHolder(parent, block)
        block.build(blocks[name], selected)
    end

    -- full width reset button under the input fields (it only clears inputs, Enter in a field applies it)
    inputFooter = parent:addChild({
        pos = { 0, 0 },
        size = { parent.size.w, FOOTER_H },
    })
    Widgets.buttonRow(inputFooter, 0, FOOTER_H, { { label = "Reset inputs", onClick = clearInputs } }, 0, nil, Widgets.PANEL_STYLE)
    -- Duplicate/Delete are in the object list's bottom bar (ui/obj_selector.lua), Save in the toolbar
    -- (ui/main.lua). Positions and visibility are applied by Main.applyTab after create
end

-- used by the object list's Duplicate/Delete buttons
editor.duplicate = duplicate
editor.deleteSelected = onDeleteClick -- asks for confirmation first

MGE.Editor = editor
return editor
