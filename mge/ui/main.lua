require("toriui.uielement")

---@class Main
---@field window UIElement
---@field page integer
---@field pageSize integer
---@field toggleAll boolean
---@field activeTab "core"|"advanced"|"thrust"|"generate" the objects' editor tab, kept while another list is shown
---@field activeTabs table<string, string> each list's active editor tab (panel id), by list
---@field listTab "objects"|"atmo"|"joints"|"players"|"misc" what the list area shows (misc: the whole mod's things)
---@field selectedPlayer integer last picked player: the players panel shows it (also when none is selected)
---@field selectedPlayers table<integer, boolean> selected players (Shift adds), the gizmo moves them together
---@field selectPlayer fun(id: integer, additive: boolean?) picks a player (list row, world click)
---@field selectedJoints table<integer, boolean> selected joint slots (Shift adds), never empty, empty slots too
---@field jointSlot integer the current joint slot (last clicked), always selected: the Link tab edits it
local Main = { page = 1, pageSize = 64, toggleAll = false, activeTab = "core", listTab = "objects", selectedPlayer = 0,
    selectedPlayers = { [0] = true }, selectedJoints = { [1] = true }, jointSlot = 1,
    activeTabs = { objects = "core", atmo = "core", players = "player", joints = "jointLink", misc = "misc" } }
MGE.Main = Main -- registered before UI modules load so they can alias it

local ModData = MGE.ModData
local History = MGE.History
local Widgets = dofile(MGE.scriptPath .. "ui/widgets.lua") -- MGE.Widgets, shared button helpers

local defaultPos = { 0, 0 }
local PAD = 0 -- the panel's edge to its content: none, the sections reach its edges
local SECTION_GAP = 6 -- space between window sections
---Moves the next section's position under one that is height tall
---@param height number?
---@param gap number? space before the next section, defaults to SECTION_GAP
local function updateContentHeight(height, gap)
    defaultPos[2] = defaultPos[2] + (height or 0) + (gap or SECTION_GAP)
end

-- Layout: a thin bar across the whole top of the screen, a static panel under it on the left edge, as tall
-- as its sections, and a footer row along the screen's bottom. The screen is the game's UI size: window
-- size / GUI scale, 1920x1080 at 1.6x is 675 tall.
--   bar, left:   the list tabs (over the panel, the active one joins the list under it), Mods, Rules
--   bar, right:  the tools, close (the list's buttons are under the list: Main.setListActions)
--   panel:       the list (LIST_ROWS rows, no bars of its own), the editor tabs and panel
--   footer:      counters, credits, the mod name
-- The game's view stays free under the panel. It was a movable window, 710 tall with a drag bar, margins
-- and its own tab / list bars: at 1.6x it didn't fit and the list kept 2 rows
-- sizes in layout units, Widgets.px scales them by MGE's overall size (Widgets.UI_SCALE)
local px = Widgets.px
local PANEL_W = px(300)
local BAR_H = px(30) -- the top bar
local BAR_ICON = BAR_H - px(6) -- its icon buttons, 3 units above and under
local BAR_GAP = Widgets.GAP -- between the bar's buttons, the same gap as everywhere (Widgets.GAP)
local BAR_SEP = px(14) -- between its groups
local EDITOR_TABS_H = px(20)
local TAB_PADDING = px(6) -- space between a tab panel's edge and its content
-- the editor area: fits the panels (8 rows each, PANELS in ui/editor.lua), a gap and the reset button
local EDITOR_H = 8 * Widgets.ROW_H + px(4) + Widgets.ROW_H
local FOOTER_H = Widgets.INFO_HEIGHT + px(4) -- the footer row along the screen's bottom
local LIST_ROWS = 6 -- the list's height, it scrolls; fewer when the panel wouldn't fit the screen (below)
local rowH = Widgets.LIST_ROW_H -- ScrollList.rowHeight (loaded below) is the same
local screenW = WIN_W or 1280 -- the top bar starts this wide, Main.fitScreen keeps it fitted
local listH = LIST_ROWS * rowH
-- the list's buttons, a bar under it on the list's own dark background (Main.setListActions), lined up
-- with the grid's cells: GAP from the list's sides and its bottom, INSET under the last row (whose cells keep
-- INSET free too, so GAP between them)
local ACTIONS_H = px(18)
local ACTIONS_GAP = Widgets.INSET + Widgets.GAP -- the bar's height beyond its buttons
local panelH = BAR_H + listH + ACTIONS_GAP + ACTIONS_H + TAB_PADDING * 2 + EDITOR_TABS_H + EDITOR_H + TAB_PADDING * 2
-- a big UI size at a big GUI scale made the panel taller than the screen: the list gives up rows (down to
-- 3) so the panel ends above the footer
local fitH = (WIN_H or 720) - FOOTER_H
while panelH > fitH and LIST_ROWS > 3 do
    LIST_ROWS, listH, panelH = LIST_ROWS - 1, listH - rowH, panelH - rowH
end
Main.LIST_ROWS = LIST_ROWS -- the Link tab's object grid is as tall (ui/editor_link.lua)

-- the bar's and the content areas' colors (ui/widgets.lua, shared with the overlays)
local BAR_COLOR = Widgets.BAR_COLOR
local BAR_STYLE = { bg = BAR_COLOR, hover = Widgets.HOVER_COLOR, pressed = TB_MENU_DEFAULT_DARKEST_COLOR }
local LIST_BG = Widgets.CONTENT_BG

Main.window = UIElement.new({
    globalid = TB_MENU_HUB_GLOBALID,
    pos = { 0, 0 },
    size = { PANEL_W, panelH },
    bgColor = TB_MENU_DEFAULT_BG_COLOR,
})
local content = Main.window:addChild({
    pos = { PAD, BAR_H },
    size = { PANEL_W - PAD * 2, panelH - BAR_H },
}, true)

-- the top bar: a child of the panel reaching past its right edge, shown, hidden and killed with it.
-- Interactive so clicks on it don't go through to the world (widgets.lua isMouseOverUI)
local topBar = Main.window:addChild({
    pos = { 0, 0 },
    size = { screenW, BAR_H },
    interactive = true,
    bgColor = BAR_COLOR,
    hoverColor = BAR_COLOR,
    pressedColor = BAR_COLOR,
})
Main.topBar = topBar

-- right end: close (quits MGE, F1 only hides it)
local closeButton = TBMenu:spawnCloseButton(topBar, { x = -BAR_H, y = 0, w = BAR_H, h = BAR_H }, function()
    Main.window:kill() -- killAction quits
end, { default = BAR_COLOR, hover = Widgets.HOVER_COLOR, pressed = TB_MENU_DEFAULT_DARKEST_COLOR,
    ui = { 1, 1, 1, 1 } }) -- the bar's button colors, its default ones are the panel's red
Widgets.popupBelowLeft(closeButton, TBMenu:displayPopup(closeButton, "Close MGE (F1 only hides it)"))
if closeButton.child and closeButton.child[1] then -- its cross loads again after a graphics change
    Widgets.trackImage(closeButton.child[1], "../textures/menu/general/buttons/crosswhite.tga")
end

-- the tools, left of close: gizmo tool toggles, undo / redo, save / rename, settings
local ICON_COUNT = 8 -- move, rotate, scale, undo, redo, save, rename, settings
local toolsW = BAR_ICON * ICON_COUNT + BAR_GAP * (ICON_COUNT - 1)
-- negative x: from the bar's right edge, so the groups follow it when the screen size changes (Main.fitScreen)
local toolsX = -(BAR_H + BAR_SEP + toolsW)
local iconButtons = topBar:addChild({
    pos = { toolsX, (BAR_H - BAR_ICON) / 2 },
    size = { toolsW, BAR_ICON },
})

---@type UIElement the bar under the list, set with the list panel (below)
local actionsHolder

---The list's action buttons in the bar under it (Select all, New, Duplicate, Import, Export, Delete, as many
---as the list has), sharing its width. Called by each list when it's built. They were on the top bar for a
---while: under the list it's clearer what they act on
---@param items WidgetRowButton[]
---@return UIElement[] buttons in the same order
function Main.setListActions(items)
    Widgets.clearChildren(actionsHolder)
    return Widgets.buttonRow(actionsHolder, 0, actionsHolder.size.h, items, Widgets.GAP, nil, Widgets.PANEL_STYLE)
end
-- the lists' Select all button, unlit (lit: Widgets.ACTIVE_COLOR)
Main.ACTIONS_BG = Widgets.PANEL_STYLE.bg

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
-- Save and Rename (the game's save and edit icons), the footer's right end names the file they write
table.insert(bar, { label = "Save (Ctrl + S): the mod into mod/" .. MGE.saveFolder .. ",\na mod from elsewhere is copied there",
    icon = "../textures/menu/general/buttons/savewhite.tga", onClick = function() MGE.save() end })
table.insert(bar, { label = "Rename (Ctrl + Shift + S): saves under a new name,\nSave writes there from then on. The old file stays",
    icon = "../textures/menu/general/buttons/edit.tga", onClick = function() MGE.saveAs() end })
-- camera follow, gizmo snapping, shortcuts (ui/settings_overlay.lua), game's settings icon
table.insert(bar, { label = "Settings", icon = "../textures/menu/general/buttons/settingswhite.tga",
    onClick = function() dofile(MGE.scriptPath .. "ui/settings_overlay.lua") end })
for _, item in ipairs(bar) do item.popupLeft = true end -- near the screen's right edge
local icons = Widgets.buttonRow(iconButtons, 0, BAR_ICON, bar, BAR_GAP, nil, BAR_STYLE)

---The active tool's button is highlighted
local function updateToolButtons()
    for i, tool in ipairs(TOOLS) do
        local btn = icons[i]
        if btn and not btn.destroyed then
            btn.bgColor = MGE.Gizmo.mode == tool.mode and Widgets.ACTIVE_COLOR or BAR_COLOR
        end
    end
end
table.insert(MGE.Gizmo.modeListeners, updateToolButtons)
updateToolButtons()

-- tabs: the active one has the color of the panel under it and touches it, so they read as one shape
local TAB_PANEL_COLOR = Widgets.TAB_PANEL_COLOR -- darkens the window, buttons inside (DARKER) stay visible

---Active tabs are part of the panel under them: panel color, no hover/press change.
---Inactive tabs keep the normal button look (on the top bar: the bar's color). Used by the list tabs and
---the editor tabs
---@param btn UIElement
---@param active boolean
---@param activeColor number[]? the panel's color as the tab is drawn (default TAB_PANEL_COLOR)
---@param idleColor number[]? default TB_MENU_DEFAULT_DARKER_COLOR
local function styleTab(btn, active, activeColor, idleColor)
    if active then
        activeColor = activeColor or TAB_PANEL_COLOR
        btn.bgColor, btn.hoverColor, btn.pressedColor = activeColor, activeColor, activeColor
    else
        btn.bgColor = idleColor or TB_MENU_DEFAULT_DARKER_COLOR
        btn.hoverColor = Widgets.HOVER_COLOR
        btn.pressedColor = TB_MENU_DEFAULT_DARKEST_COLOR
    end
end

-- the list tabs, on the top bar over the panel (how full the mod is shows in the footer). On the bar the
-- active one is drawn solid: the see-through panel color would show the bar under it
local listTabNames = {
    { id = "objects", label = "Objects" },
    { id = "atmo", label = "Atmo" }, -- atmo objects: drawn only, the mod's .atmo file (utils/atmo.lua)
    { id = "joints", label = "Joints" },
    { id = "players", label = "Players" },
    { id = "misc", label = "Misc" }, -- the whole mod: message, shader, reindex, convert map (ui/editor_misc.lua)
}
local listTabItems = {}
for i, tab in ipairs(listTabNames) do
    listTabItems[i] = { label = tab.label, onClick = function() Main.setListTab(tab.id) end }
end
-- the bar's text buttons are all this wide, as wide as their text needs, not stretched over the panel
local BAR_TEXT_W = px(56)
local listTabRow = topBar:addChild({
    pos = { PAD, 0 },
    size = { BAR_TEXT_W * #listTabItems + BAR_GAP * (#listTabItems - 1), BAR_H },
})
local listTabButtons = {}
for i, btn in ipairs(Widgets.buttonRow(listTabRow, 0, BAR_H, listTabItems, BAR_GAP, Widgets.TAB_TEXT_SCALE, BAR_STYLE)) do
    listTabButtons[listTabNames[i].id] = btn
end

-- the game's own mod list and gamerules menus, right of the tabs
local gameMenus = topBar:addChild({
    pos = { PAD + listTabRow.size.w + BAR_GAP, 0 }, -- right after the tabs, the usual gap
    size = { BAR_TEXT_W * 2 + BAR_GAP, BAR_H },
})
Widgets.buttonRow(gameMenus, 0, BAR_H, {
    { label = "Mods", onClick = function() dofile("system/mods.lua") end },
    { label = "Rules", onClick = function() dofile("system/gamerules.lua") end },
}, BAR_GAP, Widgets.TAB_TEXT_SCALE, BAR_STYLE)

-- the list sits in a panel like the editor's: panel color, padding, the active list tab touches it.
-- listH (above): its rows, ScrollList.rowHeight (25) each
local listPanel = content:addChild({
    pos = defaultPos,
    size = { content.size.w, listH + ACTIONS_GAP + ACTIONS_H + TAB_PADDING * 2 },
    bgColor = TAB_PANEL_COLOR,
})
-- the list and its buttons share one dark background
local listArea = listPanel:addChild({
    pos = { TAB_PADDING, TAB_PADDING },
    size = { listPanel.size.w - TAB_PADDING * 2, listH + ACTIONS_GAP + ACTIONS_H },
    bgColor = LIST_BG,
})
local obj_selector_container = listArea:addChild({
    pos = { 0, 0 },
    size = { listArea.size.w, listH },
})
actionsHolder = listArea:addChild({
    pos = { Widgets.GAP, listH + Widgets.INSET },
    size = { listArea.size.w - Widgets.GAP * 2, ACTIONS_H },
})
updateContentHeight(listPanel.size.h, 0) -- the editor tabs sit right under the list

-- Tabs, right above the area they switch (title row and object list stay the same on every tab).
-- The area has its own panel color and the active tab uses the same color and touches the panel,
-- so it reads as one shape. Inactive tabs keep the normal button look.
local TAB_GAP = Widgets.GAP
local tabRow = content:addChild({
    pos = defaultPos,
    size = { content.size.w, EDITOR_TABS_H },
    bgColor = Widgets.TAB_PANEL_SOLID, -- the gaps between the tabs: the inactive tabs' color
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
    misc = { { id = "misc", label = "Misc" } },
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
    for i, btn in ipairs(Widgets.buttonRow(tabRows[list], 0, tabRow.size.h, items, TAB_GAP, Widgets.TAB_TEXT_SCALE)) do
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
local areaH = EDITOR_H
local tabPanel = content:addChild({
    pos = defaultPos,
    size = { content.size.w, areaH + TAB_PADDING * 2 },
    bgColor = LIST_BG, -- dark like the list, the active editor tab joins it
})
local editorContainer = tabPanel:addChild({
    pos = { TAB_PADDING, TAB_PADDING },
    size = { tabPanel.size.w - TAB_PADDING * 2, areaH },
})
updateContentHeight(tabPanel.size.h)

-- Duplicate/Delete/Import/Export are the list's buttons on the top bar (Main.setListActions), Save and
-- Rename are with the tools, Reindex is in the Advanced panel

-- footer: one row along the bottom of the screen over the game's view, no background, a child of the panel
-- reaching past its edges like the top bar. Left: the counters, middle: credits, right: the mod Save writes
-- Placed by Main.fitScreen, like the top bar's width
local FOOTER_EDGE = px(8) -- from the screen's sides
local CREDITS_W = px(260)
---@return UIElement
local function addFooterPart()
    return Main.window:addChild({ pos = { 0, 0 }, size = { 1, FOOTER_H } })
end
local limitsRow = addFooterPart() -- object, dynamic id and joint usage, set by setDynamicStrings
local creditsRow = addFooterPart()
creditsRow.uiColor = { 0, 0, 0, 1 } -- black like the rest of the footer (FOOTER_COLOR, set below)
local fileRow = addFooterPart() -- the file Save writes, unsaved changes
local shown = {} -- what the file row shows (below)

---Fits what spans the screen to its size: the top bar's width (its right-hand groups count from its right
---edge) and the footer along the bottom. At start and when the game's window or GUI scale changes (the
---resolution_changed hook): those were placed for the size MGE started with
function Main.fitScreen()
    local w, h = get_window_size()
    w, h = w or WIN_W or 1280, h or WIN_H or 720
    topBar.size.w = w
    topBar:moveTo(0, 0) -- updates its children's positions
    local sideW = (w - CREDITS_W) / 2 - FOOTER_EDGE - BAR_SEP
    for _, part in ipairs({ { limitsRow, FOOTER_EDGE, sideW }, { creditsRow, (w - CREDITS_W) / 2, CREDITS_W },
        { fileRow, w - FOOTER_EDGE - sideW, sideW } }) do
        part[1].size.w = part[3]
        part[1]:moveTo(part[2], h - FOOTER_H)
    end
    Widgets.infoText(creditsRow, "Project Mod Group Editor by joopez")
    shown = {} -- the file row lays its text out again for its new width
    if Main.refreshCounters then Main.refreshCounters() end
end
table.insert(Widgets.onScreenChanged, Main.fitScreen)
Main.fitScreen()

-- footer text: black over the game's view, dark red while something needs attention (dynamic objects,
-- unsaved changes)
local WARNING_COLOR = { 0.6, 0.02, 0.02, 1 }
local FOOTER_COLOR = { 0, 0, 0, 1 } -- black: the footer is over the game's (light) view

-- File row: checked every frame, the mod text is only built again when the data changed (an edit
-- commits a new undo state, a reload parses new data) or the source changed (load, save). Lua
-- strings are interned, comparing savedText is cheap
Widgets.addDrawBefore(fileRow, function()
    local parsed, state, source, saved = ModData.parsed, History.states[History.index], MGE.sourcePath, MGE.savedText
    -- the atmo file's saved text too: Export atmo writes it without saving the mod (utils/atmo.lua)
    local atmo = tostring(MGE.Atmo.state.text) .. "#" .. MGE.Atmo.headerVersion -- a shader picked counts too
    if shown.parsed == parsed and shown.state == state and shown.source == source and shown.saved == saved
        and shown.atmo == atmo and shown.done then return end
    shown = { parsed = parsed, state = state, source = source, saved = saved, atmo = atmo, done = true }
    local target = MGE.saveTarget()
    local unsaved = MGE.hasUnsavedChanges()
    -- where Save writes (a mod from outside modmaker/ is copied there, its original stays as it is)
    local text = target and "Mod: " .. target .. (unsaved and "  (unsaved changes)" or "")
        or "Not saved to a mod yet, Save asks the name"
    fileRow.uiColor = target and not unsaved and FOOTER_COLOR or WARNING_COLOR
    Widgets.infoText(fileRow, text, RIGHTMID)
end)


dofile(MGE.scriptPath .. "ui/scroll_list.lua") -- MGE.ScrollList, used by the lists and the file picker
MGE.ScrollList.bgColor = LIST_BG -- every list: the object grid, players, the file picker, assets
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
        styleTab(btn, id == active, LIST_BG, Widgets.TAB_PANEL_SOLID) -- active: the editor panel's dark
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
        styleTab(btn, id == Main.listTab, Widgets.TAB_PANEL_SOLID, BAR_COLOR)
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
    limitsRow.uiColor = warning and WARNING_COLOR or FOOTER_COLOR
    local atmoCount = #ModData.parsed.atmo
    Widgets.infoText(limitsRow, "Objects " .. #ModData.parsed.env_obj .. "/" .. MGE.MAX_ENV_OBJECTS ..
        (atmoCount > 0 and (" +" .. atmoCount .. " atmo") or "") ..
        "    Dynamic " .. ModData.countDynamic() .. "/" .. MGE.MAX_NONSTATIC_OBJECTS ..
        (warning and " (" .. warning .. ")" or "") ..
        "    Joints " .. #ModData.parsed.env_obj_joint .. "/" .. MGE.MAX_ENV_JOINTS, LEFTMID)
end
Main.refreshCounters = setDynamicStrings -- also after a screen size change (Main.fitScreen)

local function createObjSelector()
    if Main.listTab == "players" then
        player_list.create(obj_selector_container)
    elseif Main.listTab == "joints" then
        joint_list.create(obj_selector_container)
    elseif Main.listTab == "atmo" then
        obj_selector.create(obj_selector_container, ModData.parsed.atmo, "atmo")
    elseif Main.listTab == "misc" then
        -- nothing to pick: the panel's rows are about the whole mod
        Main.setListActions({})
        obj_selector_container:addChild({
            pos = { Widgets.px(8), 0 },
            size = { obj_selector_container.size.w - Widgets.px(16), obj_selector_container.size.h },
        }):addAdaptedText("Things about the whole mod, not the selected objects:\n" ..
            "its message, the atmo's shader, ids and converting a map", nil, nil, Widgets.FONT, CENTERMID,
            Widgets.TEXT_SCALE_SMALL, nil, nil)
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
