require("toriui.uielement")

---@class Main
---@field window UIElement
---@field page integer
---@field pageSize integer
---@field toggleAll boolean
---@field activeTab "core"|"advanced"|"thrust"|"generate" editor panel, kept while the Players list hides the editor
---@field listTab "objects"|"players" what the list area shows
---@field selectedPlayer integer player Export / Import act on, picked in the Players list
local Main = { page = 1, pageSize = 120, toggleAll = false, activeTab = "core", listTab = "objects", selectedPlayer = 0 }
MGE.Main = Main -- registered before UI modules load so they can alias it

local ModData = MGE.ModData
local History = MGE.History
local Widgets = dofile(MGE.scriptPath .. "ui/widgets.lua") -- MGE.Widgets, shared button helpers

local defaultPos = { 0, 0 }
local margin = 10
local SECTION_GAP = 6 -- space between window sections
---Moves the next section's position under one that is height tall
---@param height number?
---@param gap number? space before the next section, defaults to SECTION_GAP
local function updateContentHeight(height, gap)
    defaultPos[2] = defaultPos[2] + (height or 0) + (gap or SECTION_GAP)
end

local windowContainer
Main.window, windowContainer = TBMenu:spawnMoveableWindow({
    x = margin,
    y = 100,
    w = 400,
    h = 692
})
local content = windowContainer:addChild({
    pos = { margin, margin },
    size = { windowContainer.size.w - margin * 2, windowContainer.size.h - margin * 2 },
}, true)

-- top menu, same bar style as the list bars:
--   left:  shortcuts to the game's own mod list and gamerules menus
--   right: save, gizmo tool toggles, undo / redo, settings, then the shortcut help
local menuH = 25
local helpSize = menuH - 4
local iconSize = menuH - 4 -- bar buttons have 2px padding top and bottom
local iconGap = 4
local menuBar = content:addChild({
    pos = defaultPos,
    size = { content.size.w, menuH },
    bgColor = TB_MENU_DEFAULT_BG_COLOR,
})
local ICON_COUNT = 7
local iconsW = iconSize * ICON_COUNT + iconGap * (ICON_COUNT - 1)
local iconsX = menuBar.size.w - (helpSize + 4) - iconGap - iconsW
local iconButtons = menuBar:addChild({
    pos = { iconsX, 0 },
    size = { iconsW, menuH },
})
-- gizmo tools: on / off toggles, at most one on (utils/gizmo.lua). Icons in mge/textures/
local TOOLS = {
    { mode = "move", label = "Move (Shift + Q)" },
    { mode = "rotate", label = "Rotate (Shift + W)" },
    { mode = "scale", label = "Scale (Shift + E)" },
}
local TOOL_FIRST = 2 -- index of the first tool in the bar
local bar = {
    -- working file (same as Ctrl+S), game's save icon
    { label = "Save (Ctrl + S)", icon = "../textures/menu/general/buttons/savewhite.tga", onClick = function() MGE.save() end },
}
for _, tool in ipairs(TOOLS) do
    table.insert(bar, { label = tool.label, icon = MGE.scriptPath .. "textures/" .. tool.mode .. ".tga",
        onClick = function() MGE.Gizmo.toggle(tool.mode) end })
end
-- game's undo icon, redo is the same icon mirrored (mge/textures/redo.tga)
table.insert(bar, { label = "Undo (Shift + Z)", icon = "../textures/menu/general/buttons/undo.tga", onClick = function() History.undo() end })
table.insert(bar, { label = "Redo (Shift + Y)", icon = MGE.scriptPath .. "textures/redo.tga", onClick = function() History.redo() end })
-- camera follow and world clicking (ui/settings_overlay.lua), game's settings icon
table.insert(bar, { label = "Settings", icon = "../textures/menu/general/buttons/settingswhite.tga",
    onClick = function() dofile(MGE.scriptPath .. "ui/settings_overlay.lua") end })
local icons = Widgets.barButtons(iconButtons, bar)

---The active tool's button is highlighted
local function updateToolButtons()
    for i, tool in ipairs(TOOLS) do
        local btn = icons[TOOL_FIRST + i - 1]
        if btn and not btn.destroyed then
            btn.bgColor = MGE.Gizmo.mode == tool.mode and TB_MENU_DEFAULT_LIGHTER_COLOR or Widgets.STYLE.bg
        end
    end
end
table.insert(MGE.Gizmo.modeListeners, updateToolButtons)
updateToolButtons()
local menuTextW = 80 -- fixed width, leaves open space between the text and icon groups
local textButtons = menuBar:addChild({
    pos = { 0, 0 },
    size = { menuTextW * 2 + iconGap, menuH },
})
Widgets.barButtons(textButtons, {
    { label = "Mods", onClick = function() dofile("system/mods.lua") end },           -- game's mod list
    { label = "Rules", onClick = function() dofile("system/gamerules.lua") end },     -- game's gamerules menu
})
Widgets.helpIcon(menuBar, -helpSize - 2, 2, helpSize,
    "Shortcuts\n" ..
    "F1: show / hide window\n" ..
    "Ctrl + S: save and reload\n" ..
    "Ctrl + A: select / deselect all\n" ..
    "Ctrl + N / D: new object / duplicate selected\n" ..
    "Delete: delete selected (asks first)\n" ..
    "Shift + Z / Y: undo / redo\n" ..
    "Enter: apply the typed field\n" ..
    "Shift + Q / W / E: Move / Rotate / Scale gizmo on / off\n" ..
    "Click Pos / Rot / Scale: switch to Move / Rotate / Resize\n" ..
    "Click object or id: select it, Shift + click: add / remove\n" ..
    "Export / Import: save selection or player as an asset / add one\n" ..
    "Gizmo (toolbar toggles): drag arrows / squares to move,\n" ..
    "rings to rotate, cubes to scale, the white cube scales evenly (Ctrl: steps)\n" ..
    "Drag (off the gizmo) / wheel: orbit / zoom camera\n" ..
    "Settings: camera follow, click to select in the world (off to play), gizmo snap steps")
updateContentHeight(menuH)

-- tabs for the list area: objects (with how full the mod is) and players. The active tab has the
-- list's color and touches it, same idea as the editor tabs
local TAB_PANEL_COLOR = Widgets.TAB_PANEL_COLOR -- darkens the window, buttons inside (DARKER) stay visible
local TAB_PADDING = 6 -- space between a tab panel's edge and its content

---Active tabs are part of the panel under them: panel color, no hover/press change.
---Inactive tabs keep the normal button look. Used by the list tabs and the editor tabs
---@param btn UIElement
---@param active boolean
local function styleTab(btn, active)
    if active then
        btn.bgColor, btn.hoverColor, btn.pressedColor = TAB_PANEL_COLOR, TAB_PANEL_COLOR, TAB_PANEL_COLOR
    else
        btn.bgColor = TB_MENU_DEFAULT_DARKER_COLOR
        btn.hoverColor = TB_MENU_DEFAULT_LIGHTER_COLOR
        btn.pressedColor = TB_MENU_DEFAULT_DARKEST_COLOR
    end
end
local listHeader = content:addChild({
    pos = defaultPos,
    size = { content.size.w, 26 },
})
updateContentHeight(listHeader.size.h, 0) -- no gap, the list panel starts right under the tabs
local listTabNames = {
    { id = "objects", label = function()
        return "Objects " .. #ModData.parsed.env_obj .. "/" .. MGE.MAX_ENV_OBJECTS
    end },
    { id = "players", label = "Players" },
}
local listTabItems = {}
for i, tab in ipairs(listTabNames) do
    listTabItems[i] = { label = tab.label, onClick = function() Main.setListTab(tab.id) end }
end
local listTabButtons = {}
for i, btn in ipairs(Widgets.buttonRow(listHeader, 0, listHeader.size.h, listTabItems, 4)) do
    listTabButtons[listTabNames[i].id] = btn
end

-- the list sits in a panel like the editor's: panel color, padding, the active list tab touches it
local listH = 175 -- the list's bars and rows, ScrollList.rowHeight (25) each
local listPanel = content:addChild({
    pos = defaultPos,
    size = { content.size.w, listH + TAB_PADDING * 2 },
    bgColor = TAB_PANEL_COLOR,
})
local obj_selector_container = listPanel:addChild({
    pos = { TAB_PADDING, TAB_PADDING },
    size = { listPanel.size.w - TAB_PADDING * 2, listH },
    bgColor = TB_MENU_DEFAULT_DARKER_COLOR
})
updateContentHeight(listPanel.size.h)

-- Tabs, right above the area they switch (title row and object list stay the same on every tab).
-- The area has its own panel color and the active tab uses the same color and touches the panel,
-- so it reads as one shape. Inactive tabs keep the normal button look.
local TAB_GAP = 4
local tabRow = content:addChild({
    pos = defaultPos,
    size = { content.size.w, 30 },
})
updateContentHeight(tabRow.size.h, 0) -- no gap, the panel starts right under the tabs

-- editor panels for objects. Players have no controls here yet, the tab row and panel are hidden
-- for them (Main.applyTab)
local tabNames = {
    { id = "core", label = "Core" },
    { id = "advanced", label = "Advanced" },
    { id = "thrust", label = "Thrust" },
    { id = "generate", label = "Generate" },
}
local tabItems = {}
for i, tab in ipairs(tabNames) do
    tabItems[i] = { label = tab.label, onClick = function() Main.setTab(tab.id) end }
end
---@type table<string, UIElement>
local tabButtons = {}
for i, btn in ipairs(Widgets.buttonRow(tabRow, 0, tabRow.size.h, tabItems, TAB_GAP)) do
    tabButtons[tabNames[i].id] = btn
end

-- the editor area inside the tab panel: fits the panels (8 rows each, see PANELS in ui/editor.lua)
-- with the reset button under them
local areaH = 268
local tabPanel = content:addChild({
    pos = defaultPos,
    size = { content.size.w, areaH + TAB_PADDING * 2 },
    bgColor = TAB_PANEL_COLOR,
})
local editorContainer = tabPanel:addChild({
    pos = { TAB_PADDING, TAB_PADDING },
    size = { tabPanel.size.w - TAB_PADDING * 2, areaH },
})
updateContentHeight(tabPanel.size.h)

-- Duplicate/Delete/Import/Export are in the list's bottom bar (ui/obj_selector.lua, ui/player_list.lua),
-- Reindex in the Advanced panel

-- named copy of the mod, under the editor area
local saveAsRow = content:addChild({
    pos = defaultPos,
    size = { content.size.w, 24 },
})
Widgets.buttonRow(saveAsRow, 0, saveAsRow.size.h, {
    { label = "Save as", onClick = function() dofile(MGE.scriptPath .. "ui/save_overlay.lua") end },
}, margin)
updateContentHeight(saveAsRow.size.h)

-- footer: small centered info rows stacked without gaps
---@param text string?
---@return UIElement
local function addFooterRow(text)
    local row = content:addChild({
        pos = defaultPos,
        size = { content.size.w, Widgets.INFO_HEIGHT },
        bgColor = { 0, 0, 0, 0 }
    })
    if text then Widgets.infoText(row, text) end
    updateContentHeight(row.size.h, 0)
    return row
end
local limitsRow = addFooterRow() -- dynamic id and joint usage, set by setDynamicStrings
addFooterRow("Project Mod Group Editor by joopez")


dofile(MGE.scriptPath .. "ui/scroll_list.lua") -- MGE.ScrollList, used by the lists and the file picker
dofile(MGE.scriptPath .. "ui/file_picker.lua") -- MGE.FilePicker, folder browser: asset import, Model row
dofile(MGE.scriptPath .. "ui/assets.lua") -- MGE.Assets, export / import overlay for the lists' buttons
local obj_selector = dofile(MGE.scriptPath .. "ui/obj_selector.lua")
local player_list = dofile(MGE.scriptPath .. "ui/player_list.lua")
local editor = dofile(MGE.scriptPath .. "ui/editor.lua")

---Shows the tab row and the active editor panel. Players have no editor controls yet, their list
---shows without the tab area. hide(true) keeps hidden parts hidden when the window is re-shown (F1)
function Main.applyTab()
    if Main.listTab == "players" then
        tabRow:hide(true)
        tabPanel:hide(true)
        return
    end
    tabRow:show(true)
    tabPanel:show(true)
    editor.applyPanel(Main.activeTab)
    for id, btn in pairs(tabButtons) do
        styleTab(btn, id == Main.activeTab)
    end
end

---@param id "core"|"advanced"|"thrust"|"generate"
function Main.setTab(id)
    if not tabButtons[id] then return end
    Main.activeTab = id
    Main.applyTab()
end

---Players in the current mod (numplayers gamerule), keeps the selected player in range
---@return integer
function Main.getPlayerCount()
    local count = math.max(tonumber(get_game_rules().numplayers) or 2, 1)
    if Main.selectedPlayer >= count then Main.selectedPlayer = 0 end -- picked in a mod with more players
    return count
end

local function applyListTab()
    for id, btn in pairs(listTabButtons) do
        styleTab(btn, id == Main.listTab)
    end
end

---Switches the list area between objects and players, the top level choice: the editor tabs are
---only there for objects
---@param id "objects"|"players"
function Main.setListTab(id)
    Main.listTab = id
    applyListTab()
    Main.applyTab()
    Main.updateWindow()
end

-- footer text color while dynamic objects need attention
local WARNING_COLOR = { 1, 0.45, 0.35, 1 }

---Why dynamic objects won't fully work yet, nil when they do
---@return string?
function Main.dynamicWarning()
    local dynamic, misplaced = ModData.countDynamic(), ModData.countMisplaced()
    if dynamic > MGE.MAX_NONSTATIC_OBJECTS then
        return (dynamic - MGE.MAX_NONSTATIC_OBJECTS) .. " too many dynamic, make some static"
    elseif misplaced > 0 then
        return misplaced .. " dynamic above id " .. MGE.MAX_NONSTATIC_OBJECTS .. ", Reindex"
    end
    return nil
end

local function setDynamicStrings()
    local warning = Main.dynamicWarning()
    limitsRow.uiColor = warning and WARNING_COLOR or UICOLORWHITE
    Widgets.infoText(limitsRow, "Dynamic " .. ModData.countDynamic() .. "/" .. MGE.MAX_NONSTATIC_OBJECTS ..
        (warning and " (" .. warning .. ")" or "") ..
        "    Joints " .. #ModData.parsed.env_obj_joint .. "/" .. MGE.MAX_ENV_JOINTS)
end

local function createObjSelector()
    if Main.listTab == "players" then
        player_list.create(obj_selector_container)
    else
        obj_selector.create(obj_selector_container, ModData.parsed.env_obj)
    end
end

local function createEditor()
    editor.create(editorContainer)
end

---Selection changed: editor shows the new selection's current values
function Main.onSelectionChanged()
    editor.onSelectionChanged()
end

function Main.updateWindow()
    if not Main.window.displayed then return end
    Widgets.clearChildren(obj_selector_container)
    setDynamicStrings()
    createObjSelector()
    Main.onSelectionChanged() -- called after select all, saves and reloads
end

---Selects or deselects every object (object list's select all icon, Ctrl+A)
---@param value boolean? nil selects all, or deselects all when everything is already selected
function Main.toggleSelectAll(value)
    local objects = ModData.parsed.env_obj
    if value == nil then
        value = false
        for _, obj in ipairs(objects) do
            if not obj.selected then value = true break end
        end
    end
    Main.toggleAll = value
    for _, obj in ipairs(objects) do
        obj.selected = value or nil
    end
    Main.updateWindow()
    -- selecting everything frames it when the camera button is on, like selecting in the list
    if value then MGE.Camera.followSelection() end
end

function Main.resetWindow()
    Main.page = 1
    Main.toggleAll = false
    Main.updateWindow()
end

function Main.resetEditor()
    Widgets.clearChildren(editorContainer)
    createEditor()
    Main.applyTab() -- rebuilt children are visible by default
end

setDynamicStrings()
createObjSelector();
createEditor()
Main.applyTab()
applyListTab()

-- closing the window quits the script, window is already being killed so quit skips it
Main.window.killAction = function() MGE.quit(true) end
return Main
