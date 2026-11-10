require("toriui.uielement")

---@class Main
---@field window UIElement
---@field page integer
---@field pageSize integer
---@field toggleAll boolean
---@field activeTab "core"|"advanced"|"thrust"|"generate" editor panel, kept while the Players list hides the editor
---@field listTab "objects"|"players" what the list area shows
---@field selectedPlayer integer last picked player: the players panel shows it (also when none is selected)
---@field selectedPlayers table<integer, boolean> selected players (Shift adds), the gizmo moves them together
---@field selectPlayer fun(id: integer, additive: boolean?) picks a player (list row, world click)
local Main = { page = 1, pageSize = 120, toggleAll = false, activeTab = "core", listTab = "objects", selectedPlayer = 0,
    selectedPlayers = { [0] = true } }
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
    h = 710
})
local content = windowContainer:addChild({
    pos = { margin, margin },
    size = { windowContainer.size.w - margin * 2, windowContainer.size.h - margin * 2 },
}, true)

-- top menu, same bar style as the list bars:
--   left:  shortcuts to the game's own mod list and gamerules menus
--   right: play, gizmo tool toggles, undo / redo, settings (Save is in the row above the footer)
local menuH = 25
local iconSize = menuH - 4 -- bar buttons have 2px padding top and bottom
local iconGap = 4
local menuBar = content:addChild({
    pos = defaultPos,
    size = { content.size.w, menuH },
    bgColor = TB_MENU_DEFAULT_BG_COLOR,
})
local ICON_COUNT = 7
local iconsW = iconSize * ICON_COUNT + iconGap * (ICON_COUNT - 1)
local iconsX = menuBar.size.w - iconsW
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
local TOOL_FIRST = 2 -- index of the first tool in the bar, after Play

-- Play: the game gets the clicks and keys, no selecting, no gizmo, MGE's shortcuts off (F1 and Esc
-- still work), everything deselected so no highlight is left. Playing is world clicking off
-- (WorldSelect.enabled), a gizmo tool turns it back on. Leaving with the button brings back the tool
-- used before
local toolBeforePlay = nil
local function togglePlay()
    local WorldSelect = MGE.WorldSelect
    if WorldSelect.enabled then
        toolBeforePlay = MGE.Gizmo.mode
        WorldSelect.setEnabled(false) -- also turns the tool off and ends a drag
        for _, obj in ipairs(ModData.parsed.env_obj) do obj.selected = nil end
        Main.toggleAll = false
        Main.selectedPlayers = {}
        Main.updateWindow() -- list highlights and the editor's values follow
    else
        WorldSelect.setEnabled(true)
        if toolBeforePlay and toolBeforePlay ~= "none" then MGE.Gizmo.setMode(toolBeforePlay) end
        toolBeforePlay = nil
    end
end
-- play triangle (mge/textures/play.tga, the game's playpause.tga has both symbols)
local bar = { { label = "Play: clicks and keys go to the game", icon = MGE.scriptPath .. "textures/play.tga",
    onClick = togglePlay } }
for _, tool in ipairs(TOOLS) do
    table.insert(bar, { label = tool.label, icon = MGE.scriptPath .. "textures/" .. tool.mode .. ".tga",
        onClick = function() MGE.Gizmo.toggle(tool.mode) end })
end
-- game's undo icon, redo is the same icon mirrored (mge/textures/redo.tga)
table.insert(bar, { label = "Undo (Shift + Z)", icon = "../textures/menu/general/buttons/undo.tga", onClick = function() History.undo() end })
table.insert(bar, { label = "Redo (Shift + Y)", icon = MGE.scriptPath .. "textures/redo.tga", onClick = function() History.redo() end })
-- camera follow, gizmo snapping, shortcuts (ui/settings_overlay.lua), game's settings icon
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

---The Play button is lit while playing (world clicking off)
local function updatePlayButton()
    local btn = icons[1]
    if btn and not btn.destroyed then
        btn.bgColor = MGE.WorldSelect.enabled and Widgets.STYLE.bg or TB_MENU_DEFAULT_LIGHTER_COLOR
    end
end
MGE.WorldSelect.onChanged = updatePlayButton
updatePlayButton()
local menuTextW = 80 -- fixed width, leaves open space between the text and icon groups
local textButtons = menuBar:addChild({
    pos = { 0, 0 },
    size = { menuTextW * 2 + iconGap, menuH },
})
Widgets.barButtons(textButtons, {
    { label = "Mods", onClick = function() dofile("system/mods.lua") end },           -- game's mod list
    { label = "Rules", onClick = function() dofile("system/gamerules.lua") end },     -- game's gamerules menu
})
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

-- editor panels for objects. The Players list hides the tab row and shows its own panel in the
-- same area (Main.applyTab, ui/editor_player.lua)
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

-- Save and Rename, under the editor area, right above the footer line naming the file they write
local saveRow = content:addChild({
    pos = defaultPos,
    size = { content.size.w, 24 },
})
local saveButtons = Widgets.buttonRow(saveRow, 0, saveRow.size.h, {
    { label = "Save", onClick = function() MGE.save() end },     -- Ctrl + S, same as the toolbar icon
    { label = "Rename", onClick = function() MGE.saveAs() end }, -- Ctrl + Shift + S
}, margin)
TBMenu:displayPopup(saveButtons[1], "Saves the mod into mod/" .. MGE.saveFolder .. " (Ctrl + S),\na mod from elsewhere is copied there.")
TBMenu:displayPopup(saveButtons[2], "Saves under a new name, Save writes there from then on.\nThe old file stays (Ctrl + Shift + S).")
updateContentHeight(saveRow.size.h)

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
local fileRow = addFooterRow() -- the file Save writes and whether there are unsaved changes
addFooterRow("Project Mod Group Editor by joopez")

-- footer text color while something needs attention (dynamic objects, unsaved changes)
local WARNING_COLOR = { 0.3, 0.02, 0.02, 1 } -- dark red: reads against the window's red, light pink didn't

-- File row: checked every frame, the mod text is only built again when the data changed (an edit
-- commits a new undo state, a reload parses new data) or the source changed (load, save). Lua
-- strings are interned, comparing savedText is cheap
local shown = {}
Widgets.addDrawBefore(fileRow, function()
    local parsed, state, source, saved = ModData.parsed, History.states[History.index], MGE.sourcePath, MGE.savedText
    if shown.parsed == parsed and shown.state == state and shown.source == source and shown.saved == saved
        and shown.done then return end
    shown = { parsed = parsed, state = state, source = source, saved = saved, done = true }
    local target = MGE.saveTarget()
    local unsaved = MGE.hasUnsavedChanges()
    -- where Save writes (a mod from outside modmaker/ is copied there, its original stays as it is)
    local text = target and "Mod: " .. target .. (unsaved and "  (unsaved changes)" or "")
        or "Not saved to a mod yet, Save asks the name"
    fileRow.uiColor = target and not unsaved and UICOLORWHITE or WARNING_COLOR
    Widgets.infoText(fileRow, text)
end)


dofile(MGE.scriptPath .. "ui/scroll_list.lua") -- MGE.ScrollList, used by the lists and the file picker
dofile(MGE.scriptPath .. "ui/file_picker.lua") -- MGE.FilePicker, folder browser: asset import, Model row
dofile(MGE.scriptPath .. "ui/assets.lua") -- MGE.Assets, export / import overlay for the lists' buttons
local obj_selector = dofile(MGE.scriptPath .. "ui/obj_selector.lua")
local player_list = dofile(MGE.scriptPath .. "ui/player_list.lua")
local editor = dofile(MGE.scriptPath .. "ui/editor.lua")

---Shows the tab row and the active editor panel. The Players list has no tabs, the players panel
---shows instead. hide(true) keeps hidden parts hidden when the window is re-shown (F1)
function Main.applyTab()
    if Main.listTab == "players" then
        -- the players' own panel (ui/editor_player.lua) instead of the object tabs
        tabRow:hide(true)
        tabPanel:show(true)
        editor.applyPanel("player")
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

---Players in the current mod (numplayers gamerule), keeps the selected players in range
---@return integer
function Main.getPlayerCount()
    local count = math.max(tonumber(get_game_rules().numplayers) or 2, 1)
    for id in pairs(Main.selectedPlayers) do
        if id >= count then Main.selectedPlayers[id] = nil end -- picked in a mod with more players
    end
    if Main.selectedPlayer >= count then Main.selectedPlayer = 0 end
    return count
end

---Selected players in order, what the gizmo, the highlight, Import, Resize and camera follow work on.
---Can be empty (Ctrl + A on all, Shift + click on the last one)
---@return integer[]
function Main.selectedPlayerList()
    Main.getPlayerCount() -- in range
    local list = {}
    for id in pairs(Main.selectedPlayers) do table.insert(list, id) end
    table.sort(list)
    return list
end

local function applyListTab()
    for id, btn in pairs(listTabButtons) do
        styleTab(btn, id == Main.listTab)
    end
end

---Picks a player (its row in the Players list, a click on it in the world): the list, the players panel
---and the highlight show it, camera follow frames the selection. Shift (additive) adds it to the
---selected players or takes it out, like objects, the selection can end up empty. The panel shows the
---last picked one (Main.selectedPlayer), also when nothing is selected
---@param id integer 0-based
---@param additive boolean?
function Main.selectPlayer(id, additive)
    if not additive then
        Main.selectedPlayers = { [id] = true }
        Main.selectedPlayer = id
    elseif Main.selectedPlayers[id] then
        Main.selectedPlayers[id] = nil
        if id == Main.selectedPlayer then -- the panel moves to another selected player, if any
            for p in pairs(Main.selectedPlayers) do Main.selectedPlayer = p break end
        end
    else
        Main.selectedPlayers[id] = true
        Main.selectedPlayer = id
    end
    Main.updateWindow() -- list row highlights, panel values
    MGE.Camera.followPlayer(Main.selectedPlayerList())
end

---Ctrl + A on the Players list: every player, or none when all are selected already (like objects)
function Main.toggleSelectAllPlayers()
    local count = Main.getPlayerCount()
    local all = true
    for id = 0, count - 1 do
        if not Main.selectedPlayers[id] then all = false break end
    end
    Main.selectedPlayers = {}
    if not all then
        for id = 0, count - 1 do Main.selectedPlayers[id] = true end
        MGE.Camera.followPlayer(Main.selectedPlayerList())
    end
    Main.updateWindow()
end

---Switches the list area between objects and players, the top level choice: the editor tabs are
---only there for objects
---@param id "objects"|"players"
function Main.setListTab(id)
    local changed = Main.listTab ~= id
    Main.listTab = id
    applyListTab()
    Main.applyTab()
    Main.updateWindow()
    -- with camera follow on: the picked player's camera, back on objects the selection again
    if changed then
        if id == "players" then MGE.Camera.followPlayer(Main.selectedPlayerList()) else MGE.Camera.followSelection() end
    end
end

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
