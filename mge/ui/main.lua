require("toriui.uielement")

---@class Main
---@field window UIElement
---@field page integer
---@field pageSize integer
---@field toggleAll boolean
---@field activeTab "core"|"advanced"|"thrust"|"generate" the objects' editor tab, kept while another list is shown
---@field activeTabs table<string, string> each list's active editor tab (panel id), by list
---@field listTab "objects"|"atmo"|"joints"|"players" what the list area shows
---@field selectedPlayer integer last picked player: the players panel shows it (also when none is selected)
---@field selectedPlayers table<integer, boolean> selected players (Shift adds), the gizmo moves them together
---@field selectPlayer fun(id: integer, additive: boolean?) picks a player (list row, world click)
---@field selectedJoints table<integer, boolean> selected joint slots (Shift adds), never empty, empty slots too
---@field jointSlot integer the current joint slot (last clicked), always selected: the Link tab edits it
local Main = { page = 1, pageSize = 120, toggleAll = false, activeTab = "core", listTab = "objects", selectedPlayer = 0,
    selectedPlayers = { [0] = true }, selectedJoints = { [1] = true }, jointSlot = 1,
    activeTabs = { objects = "core", atmo = "core", players = "player", joints = "jointLink" } }
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
--   right: gizmo tool toggles, undo / redo, settings (Save is in the row above the footer)
local menuH = 25
local iconSize = menuH - 4 -- bar buttons have 2px padding top and bottom
local iconGap = 4
local menuBar = content:addChild({
    pos = defaultPos,
    size = { content.size.w, menuH },
    bgColor = TB_MENU_DEFAULT_BG_COLOR,
})
local ICON_COUNT = 6
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
local bar = {}
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
        local btn = icons[i]
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
updateContentHeight(menuH)

-- tabs for the list area: objects, joints and players (how full the mod is shows in the footer). The
-- active tab has the list's color and touches it, same idea as the editor tabs
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
    { id = "objects", label = "Objects" },
    { id = "atmo", label = "Atmo" }, -- atmo objects: drawn only, the mod's .atmo file (utils/atmo.lua)
    { id = "joints", label = "Joints" },
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

-- editor tabs of each list, a tab's id is the editor panel it shows (PANELS in ui/editor.lua). The
-- Players and Joints lists have one tab so far, their tab row is there for more. Each list has its own
-- row, shown with the list (Main.applyTab)
local TAB_SETS = {
    objects = {
        { id = "core", label = "Core" },
        { id = "advanced", label = "Advanced" },
        { id = "thrust", label = "Thrust" },
        { id = "generate", label = "Generate" },
    },
    -- the same Core panel as objects (its rows work on the atmo objects there, utils/transforms.lua),
    -- the atmo objects' own lines and To objects (ui/editor_atmo.lua), and the same Generate panel (its
    -- pieces go to the atmo, without joints: ui/editor_generate.lua)
    atmo = {
        { id = "core", label = "Core" },
        { id = "atmo", label = "Atmo" },
        { id = "generate", label = "Generate" },
    },
    players = { { id = "player", label = "Core" } },
    joints = { { id = "jointLink", label = "Link" }, { id = "joint", label = "Properties" } },
}
-- every tab is as wide as an object tab, so a list with fewer tabs lines up with the objects' row
local TAB_SLOTS = #TAB_SETS.objects
local tabW = (tabRow.size.w - TAB_GAP * (TAB_SLOTS - 1)) / TAB_SLOTS
---@type table<string, UIElement> tab rows by list
local tabRows = {}
---@type table<string, table<string, UIElement>> tab buttons by list, then panel id (a panel can be on
---several lists: Core)
local tabButtons = {}
---@type table<string, string> a list each panel id is on (the one setTab uses when the shown list hasn't it)
local tabList = {}
for list, tabs in pairs(TAB_SETS) do
    tabRows[list] = tabRow:addChild({
        pos = { 0, 0 },
        size = { #tabs * tabW + (#tabs - 1) * TAB_GAP, tabRow.size.h },
    })
    local items = {}
    for i, tab in ipairs(tabs) do
        items[i] = { label = tab.label, onClick = function() Main.setTab(tab.id) end }
        if not tabList[tab.id] or list == "objects" then tabList[tab.id] = list end
    end
    tabButtons[list] = {}
    for i, btn in ipairs(Widgets.buttonRow(tabRows[list], 0, tabRow.size.h, items, TAB_GAP)) do
        tabButtons[list][tabs[i].id] = btn
    end
end

---@param list string
---@param id string panel id
---@return boolean the list has that tab
local function listHasTab(list, id)
    for _, tab in ipairs(TAB_SETS[list] or {}) do
        if tab.id == id then return true end
    end
    return false
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
local limitsRow = addFooterRow() -- object, dynamic id and joint usage, set by setDynamicStrings
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
    -- the atmo file's saved text too: Export atmo writes it without saving the mod (utils/atmo.lua)
    local atmo = MGE.Atmo.state.text
    if shown.parsed == parsed and shown.state == state and shown.source == source and shown.saved == saved
        and shown.atmo == atmo and shown.done then return end
    shown = { parsed = parsed, state = state, source = source, saved = saved, atmo = atmo, done = true }
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
local joint_list = dofile(MGE.scriptPath .. "ui/joint_list.lua")
local player_list = dofile(MGE.scriptPath .. "ui/player_list.lua")
local editor = dofile(MGE.scriptPath .. "ui/editor.lua")

---Shows the shown list's tab row and its active editor panel. hide(true) keeps hidden parts hidden when
---the window is re-shown (F1)
function Main.applyTab()
    for list, row in pairs(tabRows) do
        if list == Main.listTab then row:show(true) else row:hide(true) end
    end
    tabPanel:show(true)
    local active = Main.activeTabs[Main.listTab]
    editor.applyPanel(active)
    for id, btn in pairs(tabButtons[Main.listTab] or {}) do
        styleTab(btn, id == active)
    end
end

---Makes a tab its list's active one (shown when that list is), e.g. "core" or "player". A panel on several
---lists (Core: objects and atmo) is the shown list's when it has it
---@param id string panel id, see TAB_SETS
function Main.setTab(id)
    local list = listHasTab(Main.listTab, id) and Main.listTab or tabList[id]
    if not list then return end
    Main.activeTabs[list] = id
    if list == "objects" then Main.activeTab = id --[[@as "core"|"advanced"|"thrust"|"generate"]] end
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
---and the highlight show it, camera follow frames the selection. Like objects (ModData.clickSelect): a
---click selects only that player, clicking the only selected one deselects it, Shift (additive) adds
---it or takes it out. The panel shows the last picked one (Main.selectedPlayer), also with none selected
---@param id integer 0-based
---@param additive boolean?
function Main.selectPlayer(id, additive)
    if not additive then
        local onlySelected = Main.selectedPlayers[id] == true
        for p in pairs(Main.selectedPlayers) do
            if p ~= id then onlySelected = false end
        end
        Main.selectedPlayers = onlySelected and {} or { [id] = true }
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

---Selected joints in id order, only joints the mod has. Selected empty slots (Main.selectedJoints keeps
---them: the Link tab makes a joint there) are left out
---@return FileParserEnvObjJoint[]
function Main.selectedJointList()
    local list = {}
    for _, joint in ipairs(ModData.parsed.env_obj_joint) do
        if joint.id and Main.selectedJoints[joint.id] then table.insert(list, joint) end
    end
    table.sort(list, function(a, b) return a.id < b.id end)
    return list
end

---The current joint slot: the last one clicked, always selected (a joint or empty). The Link tab edits it
---@return integer
function Main.selectedSlot()
    return Main.jointSlot
end

---The slot whose objects a world click picks: the current slot while the Joints list's Link tab shows
---@return integer?
function Main.linkSlot()
    if Main.listTab ~= "joints" or Main.activeTabs.joints ~= "jointLink" then return nil end
    return Main.jointSlot
end

---Camera follow on the Joints list: frames the objects the selected joints link
local function followJoints()
    local ids = MGE.Joints.getObjectIds(Main.selectedJointList())
    local objects = {}
    for _, obj in ipairs(ModData.parsed.env_obj) do
        if ids[obj.id] then table.insert(objects, obj) end
    end
    if MGE.Camera.followMoves and #objects > 0 then MGE.Camera.focus(objects) end
end
Main.followJoints = followJoints -- also after the Link tab's Create / Update (ui/editor_link.lua)

---After the joint selection changed: a draft for another slot is dropped (the Link tab starts from the
---saved link again)
local function dropOtherDraft()
    local draft = MGE.Joints.draft
    if draft and draft.jointId ~= Main.jointSlot then MGE.Joints.resetDraft() end
end

---Picks a joint slot (its cell in the Joints list): a click makes it the current slot and selects only
---it, Shift (additive) adds it or takes it out (the Properties tab edits all selected). One slot always
---stays selected. An empty slot opens the Link tab: linking two objects is what it needs
---@param id integer joint id
---@param additive boolean?
function Main.selectJoint(id, additive)
    local selected = Main.selectedJoints
    if additive and selected[id] then
        if next(selected, nil) ~= id or next(selected, id) ~= nil then -- not the last selected one
            selected[id] = nil
            if Main.jointSlot == id then Main.jointSlot = next(selected) end
        end
    elseif additive then
        selected[id] = true
        Main.jointSlot = id
    else
        Main.selectedJoints = { [id] = true }
        Main.jointSlot = id
    end
    dropOtherDraft()
    if Main.selectedJoints[id] then
        followJoints()
        if not MGE.Joints.find(id) and Main.activeTabs.joints ~= "jointLink" then Main.setTab("jointLink") end
    end
    Main.onSelectionChanged() -- the panel; the cells are restyled by the grid
end

---Selects only these joint slots, the first is the current one, e.g. a new joint
---@param ids integer[]
function Main.selectJointsOnly(ids)
    if not ids[1] then return end
    Main.selectedJoints = {}
    for _, id in ipairs(ids) do Main.selectedJoints[id] = true end
    Main.jointSlot = ids[1]
    dropOtherDraft()
end

---Ctrl + A on the Joints list: every joint, or back to only the current slot when all are selected
---already. Empty slots aren't selected by it, the current slot stays selected
function Main.toggleSelectAllJoints()
    local joints = ModData.parsed.env_obj_joint
    local all = #joints > 0
    for _, joint in ipairs(joints) do
        if not Main.selectedJoints[joint.id] then all = false break end
    end
    Main.selectedJoints = { [Main.jointSlot] = true }
    if not all then
        for _, joint in ipairs(joints) do
            if joint.id then Main.selectedJoints[joint.id] = true end
        end
        followJoints()
    end
    Main.updateWindow()
end

---Switches the list area between objects, atmo objects, joints and players, the top level choice. On
---the Atmo list the mod's objects are see-through (utils/atmo_layer.lua), the atmo objects are edited
---@param id "objects"|"atmo"|"joints"|"players"
function Main.setListTab(id)
    local changed = Main.listTab ~= id
    Main.listTab = id
    MGE.AtmoLayer.setObjectsSeeThrough(id == "atmo")
    applyListTab()
    Main.applyTab()
    Main.updateWindow()
    -- with camera follow on: the picked player's camera, the selected joints, or the object selection
    if changed then
        if id == "players" then
            MGE.Camera.followPlayer(Main.selectedPlayerList())
        elseif id == "joints" then
            followJoints()
        else
            MGE.Camera.followSelection()
        end
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
    local atmoCount = #ModData.parsed.atmo
    Widgets.infoText(limitsRow, "Objects " .. #ModData.parsed.env_obj .. "/" .. MGE.MAX_ENV_OBJECTS ..
        (atmoCount > 0 and (" +" .. atmoCount .. " atmo") or "") ..
        "    Dynamic " .. ModData.countDynamic() .. "/" .. MGE.MAX_NONSTATIC_OBJECTS ..
        (warning and " (" .. warning .. ")" or "") ..
        "    Joints " .. #ModData.parsed.env_obj_joint .. "/" .. MGE.MAX_ENV_JOINTS)
end

local function createObjSelector()
    if Main.listTab == "players" then
        player_list.create(obj_selector_container)
    elseif Main.listTab == "joints" then
        joint_list.create(obj_selector_container)
    elseif Main.listTab == "atmo" then
        obj_selector.create(obj_selector_container, ModData.parsed.atmo, "atmo")
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

---Selects every atmo object, or none when all are selected already (the Atmo list's select all, Ctrl + A)
function Main.toggleSelectAllAtmo()
    local list = ModData.parsed.atmo
    local all = #list > 0
    for _, obj in ipairs(list) do
        if not obj.selected then all = false break end
    end
    for _, obj in ipairs(list) do obj.selected = not all or nil end
    Main.updateWindow()
    if not all then MGE.Camera.followSelection() end
end

function Main.resetWindow()
    Main.page = 1
    Main.toggleAll = false
    Main.selectedJoints, Main.jointSlot = { [1] = true }, 1 -- another mod: its joints are other joints
    MGE.Joints.resetDraft() -- its slot belongs to the old mod
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
