require("toriui.uielement")














local Main = { page = 1, pageSize = 64, toggleAll = false, activeTab = "core", listTab = "objects", selectedPlayer = 0,
    selectedPlayers = { [0] = true }, selectedJoints = { [1] = true }, jointSlot = 1,
    activeTabs = { objects = "core", atmo = "core", players = "player", joints = "jointLink", misc = "misc" } }
MGE.Main = Main

local ModData = MGE.ModData
local History = MGE.History
local Widgets = dofile(MGE.scriptPath .. "ui/widgets.lua")

local defaultPos = { 0, 0 }
local PAD = 0
local SECTION_GAP = 6



local function updateContentHeight(height, gap)
    defaultPos[2] = defaultPos[2] + (height or 0) + (gap or SECTION_GAP)
end











local px = Widgets.px
local PANEL_W = px(300)
local BAR_H = px(30)
local BAR_ICON = BAR_H - px(6)
local BAR_GAP = Widgets.GAP
local BAR_SEP = px(14)
local EDITOR_TABS_H = px(20)
local TAB_PADDING = px(6)

local EDITOR_H = Widgets.PANEL_ROWS * Widgets.ROW_H
local FOOTER_H = Widgets.INFO_HEIGHT + px(4)
local LIST_ROWS = 6
local rowH = Widgets.LIST_ROW_H
local screenW = WIN_W or 1280
local listH = LIST_ROWS * rowH



local ACTIONS_H = px(18)
local ACTIONS_GAP = Widgets.INSET + Widgets.GAP
local panelH = BAR_H + listH + ACTIONS_GAP + ACTIONS_H + TAB_PADDING * 2 + EDITOR_TABS_H + EDITOR_H + TAB_PADDING * 2


local fitH = (WIN_H or 720) - FOOTER_H
while panelH > fitH and LIST_ROWS > 3 do
    LIST_ROWS, listH, panelH = LIST_ROWS - 1, listH - rowH, panelH - rowH
end
Main.LIST_ROWS = LIST_ROWS


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



local topBar = Main.window:addChild({
    pos = { 0, 0 },
    size = { screenW, BAR_H },
    interactive = true,
    bgColor = BAR_COLOR,
    hoverColor = BAR_COLOR,
    pressedColor = BAR_COLOR,
})
Main.topBar = topBar


local closeButton = TBMenu:spawnCloseButton(topBar, { x = -BAR_H, y = 0, w = BAR_H, h = BAR_H }, function()
    Main.window:kill()
end, { default = BAR_COLOR, hover = Widgets.HOVER_COLOR, pressed = TB_MENU_DEFAULT_DARKEST_COLOR,
    ui = { 1, 1, 1, 1 } })
Widgets.popupBelowLeft(closeButton, "Close MGE (F1 only hides it)")
if closeButton.child and closeButton.child[1] then
    Widgets.trackImage(closeButton.child[1], "../textures/menu/general/buttons/crosswhite.tga")
end


local ICON_COUNT = 8
local toolsW = BAR_ICON * ICON_COUNT + BAR_GAP * (ICON_COUNT - 1)

local toolsX = -(BAR_H + BAR_SEP + toolsW)
local iconButtons = topBar:addChild({
    pos = { toolsX, (BAR_H - BAR_ICON) / 2 },
    size = { toolsW, BAR_ICON },
})


local actionsHolder






function Main.setListActions(items)
    Widgets.clearChildren(actionsHolder)
    return Widgets.buttonRow(actionsHolder, 0, actionsHolder.size.h, items, Widgets.GAP, nil, Widgets.PANEL_STYLE)
end

Main.ACTIONS_BG = Widgets.PANEL_STYLE.bg


local TOOLS = {
    { mode = "move", label = "Move (Alt + Q)" },
    { mode = "rotate", label = "Rotate (Alt + W)" },
    { mode = "scale", label = "Scale (Alt + E)" },
}
local bar = {}
for _, tool in ipairs(TOOLS) do
    table.insert(bar, { label = tool.label, icon = MGE.scriptPath .. "textures/" .. tool.mode .. ".tga",
        onClick = function() MGE.Gizmo.toggle(tool.mode) end })
end

table.insert(bar, { label = "Undo (Shift + Z)", icon = "../textures/menu/general/buttons/undo.tga", onClick = function() History.undo() end })
table.insert(bar, { label = "Redo (Shift + Y)", icon = MGE.scriptPath .. "textures/redo.tga", onClick = function() History.redo() end })

table.insert(bar, { label = "Save (Ctrl + S): the mod into mod/" .. MGE.saveFolder .. ",\na mod from elsewhere is copied there",
    icon = "../textures/menu/general/buttons/savewhite.tga", onClick = function() MGE.save() end })
table.insert(bar, { label = "Rename (Ctrl + Shift + S): saves under a new name,\nSave writes there from then on. The old file stays",
    icon = "../textures/menu/general/buttons/edit.tga", onClick = function() MGE.saveAs() end })

table.insert(bar, { label = "Settings", icon = "../textures/menu/general/buttons/settingswhite.tga",
    onClick = function() dofile(MGE.scriptPath .. "ui/settings_overlay.lua") end })
for _, item in ipairs(bar) do item.popupLeft = true end
local icons = Widgets.buttonRow(iconButtons, 0, BAR_ICON, bar, BAR_GAP, nil, BAR_STYLE)


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


local TAB_PANEL_COLOR = Widgets.TAB_PANEL_COLOR








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



local listTabNames = {
    { id = "objects", label = "Objects" },
    { id = "atmo", label = "Atmo" },
    { id = "joints", label = "Joints" },
    { id = "players", label = "Players" },
    { id = "misc", label = "World" },
}
local listTabItems = {}
for i, tab in ipairs(listTabNames) do
    listTabItems[i] = { label = tab.label, onClick = function() Main.setListTab(tab.id) end }
end

local BAR_TEXT_W = px(56)
local listTabRow = topBar:addChild({
    pos = { PAD, 0 },
    size = { BAR_TEXT_W * #listTabItems + BAR_GAP * (#listTabItems - 1), BAR_H },
})
local listTabButtons = {}
for i, btn in ipairs(Widgets.buttonRow(listTabRow, 0, BAR_H, listTabItems, BAR_GAP, Widgets.TAB_TEXT_SCALE, BAR_STYLE)) do
    listTabButtons[listTabNames[i].id] = btn
end


local gameMenus = topBar:addChild({
    pos = { PAD + listTabRow.size.w + BAR_GAP, 0 },
    size = { BAR_TEXT_W * 2 + BAR_GAP, BAR_H },
})
Widgets.buttonRow(gameMenus, 0, BAR_H, {
    { label = "Mods", onClick = function() dofile("system/mods.lua") end },
    { label = "Rules", onClick = function() dofile("system/gamerules.lua") end },
}, BAR_GAP, Widgets.TAB_TEXT_SCALE, BAR_STYLE)



local listPanel = content:addChild({
    pos = defaultPos,
    size = { content.size.w, listH + ACTIONS_GAP + ACTIONS_H + TAB_PADDING * 2 },
    bgColor = TAB_PANEL_COLOR,
})

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
updateContentHeight(listPanel.size.h, 0)




local TAB_GAP = Widgets.GAP
local tabRow = content:addChild({
    pos = defaultPos,
    size = { content.size.w, EDITOR_TABS_H },
    bgColor = Widgets.TAB_PANEL_SOLID,
})
updateContentHeight(tabRow.size.h, 0)




local TAB_SETS = {
    objects = {
        { id = "core", label = "Core" },
        { id = "advanced", label = "Advanced" },
        { id = "thrust", label = "Thrust" },
        { id = "generate", label = "Generate" },
    },



    atmo = {
        { id = "core", label = "Core" },
        { id = "atmo", label = "Advanced" },
        { id = "generate", label = "Generate" },
    },
    players = { { id = "player", label = "Core" } },
    misc = { { id = "misc", label = "Core" } },
    joints = { { id = "jointLink", label = "Link" }, { id = "joint", label = "Properties" } },
}

local TAB_SLOTS = #TAB_SETS.objects
local tabW = (tabRow.size.w - TAB_GAP * (TAB_SLOTS - 1)) / TAB_SLOTS

local tabRows = {}


local tabButtons = {}

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




local function listHasTab(list, id)
    for _, tab in ipairs(TAB_SETS[list] or {}) do
        if tab.id == id then return true end
    end
    return false
end


local areaH = EDITOR_H
local tabPanel = content:addChild({
    pos = defaultPos,
    size = { content.size.w, areaH + TAB_PADDING * 2 },
    bgColor = LIST_BG,
})
local editorContainer = tabPanel:addChild({
    pos = { TAB_PADDING, TAB_PADDING },
    size = { tabPanel.size.w - TAB_PADDING * 2, areaH },
})
updateContentHeight(tabPanel.size.h)








local FOOTER_EDGE = px(8)
local MESSAGE_W = px(380)
local MESSAGE_SHOW, MESSAGE_FADE = 7, 1
local MESSAGE_MAX = 3

local function addFooterPart()
    return Main.window:addChild({ pos = { 0, 0 }, size = { 1, FOOTER_H } })
end
local limitsRow = addFooterPart()
local fileRow = addFooterPart()
local shown = {}




local messageRows = {}
for k = 1, MESSAGE_MAX do
    local row = addFooterPart()
    row.uiColor = { 0, 0, 0, 0 }
    messageRows[k] = row
end


local messages = {}

local rowTexts = {}





function MGE.onMessage(text)
    text = text:gsub("%^%d%d", ""):gsub("%s*\n%s*", "  ")
    for i = #messages, 1, -1 do
        if messages[i].text == text then table.remove(messages, i) end
    end
    messages[#messages + 1] = { text = text, at = os.clock_real() }
    if #messages > MESSAGE_MAX then table.remove(messages, 1) end
end


Widgets.addDrawBefore(messageRows[1], function()
    local now = os.clock_real()

    for i = #messages, 1, -1 do
        if now - messages[i].at >= MESSAGE_SHOW + MESSAGE_FADE then table.remove(messages, i) end
    end
    for k, row in ipairs(messageRows) do
        local m = messages[#messages - k + 1]

        local text, alpha = "", 0
        if m then
            local age = now - m.at
            text, alpha = m.text, age > MESSAGE_SHOW and 1 - (age - MESSAGE_SHOW) / MESSAGE_FADE or 1
        end
        row.uiColor[4] = alpha
        if text ~= rowTexts[k] then
            Widgets.infoText(row, text)
            rowTexts[k] = text
        end
    end
end)




function Main.fitScreen()
    local w, h = get_window_size()
    w, h = w or WIN_W or 1280, h or WIN_H or 720
    topBar.size.w = w
    topBar:moveTo(0, 0)
    local sideW = (w - MESSAGE_W) / 2 - FOOTER_EDGE - BAR_SEP
    for _, part in ipairs({ { limitsRow, FOOTER_EDGE }, { fileRow, w - FOOTER_EDGE - sideW } }) do
        part[1].size.w = sideW
        part[1]:moveTo(part[2], h - FOOTER_H)
    end

    for k, row in ipairs(messageRows) do
        row.size.w = MESSAGE_W
        row:moveTo((w - MESSAGE_W) / 2, h - FOOTER_H * k)
    end
    rowTexts = {}
    shown = {}
    if Main.refreshCounters then Main.refreshCounters() end
end
table.insert(Widgets.onScreenChanged, Main.fitScreen)
Main.fitScreen()



local WARNING_COLOR = { 0.6, 0.02, 0.02, 1 }
local FOOTER_COLOR = { 0, 0, 0, 1 }




Widgets.addDrawBefore(fileRow, function()
    local parsed, state, source, saved = ModData.parsed, History.states[History.index], MGE.sourcePath, MGE.savedText

    local atmo = tostring(MGE.Atmo.state.text) .. "#" .. MGE.Atmo.headerVersion
    if shown.parsed == parsed and shown.state == state and shown.source == source and shown.saved == saved
        and shown.atmo == atmo and shown.done then return end
    shown = { parsed = parsed, state = state, source = source, saved = saved, atmo = atmo, done = true }
    local target = MGE.saveTarget()
    local unsaved = MGE.hasUnsavedChanges()

    local text = target and "Mod: " .. target .. (unsaved and "  (unsaved changes)" or "")
        or "Not saved to a mod yet, Save asks the name"
    fileRow.uiColor = target and not unsaved and FOOTER_COLOR or WARNING_COLOR
    Widgets.infoText(fileRow, text, RIGHTMID)
end)


dofile(MGE.scriptPath .. "ui/scroll_list.lua")
MGE.ScrollList.bgColor = LIST_BG
dofile(MGE.scriptPath .. "ui/file_picker.lua")
dofile(MGE.scriptPath .. "ui/color_picker.lua")
dofile(MGE.scriptPath .. "ui/assets.lua")
local obj_selector = dofile(MGE.scriptPath .. "ui/obj_selector.lua")
local joint_list = dofile(MGE.scriptPath .. "ui/joint_list.lua")
local player_list = dofile(MGE.scriptPath .. "ui/player_list.lua")
local editor = dofile(MGE.scriptPath .. "ui/editor.lua")



function Main.applyTab()
    for list, row in pairs(tabRows) do
        if list == Main.listTab then row:show(true) else row:hide(true) end
    end
    tabPanel:show(true)
    local active = Main.activeTabs[Main.listTab]
    editor.applyPanel(active)
    for id, btn in pairs(tabButtons[Main.listTab] or {}) do
        styleTab(btn, id == active, LIST_BG, Widgets.TAB_PANEL_SOLID)
    end
end




function Main.setTab(id)
    local list = listHasTab(Main.listTab, id) and Main.listTab or tabList[id]
    if not list then return end
    Main.activeTabs[list] = id
    if list == "objects" then Main.activeTab = id  end
    Main.applyTab()
end





function Main.leaveGenerate(list)
    list = list or Main.listTab
    if (list ~= "objects" and list ~= "atmo") or Main.activeTabs[list] ~= "generate" then return end
    Main.activeTabs[list] = "core"
    if list == "objects" then Main.activeTab = "core" end
    if list == Main.listTab then Main.applyTab() end
end





function Main.selectionMade()
    Main.leaveGenerate()
    MGE.Camera.followSelection()
end



function Main.getPlayerCount()
    local count = math.max(tonumber(get_game_rules().numplayers) or 2, 1)
    for id in pairs(Main.selectedPlayers) do
        if id >= count then Main.selectedPlayers[id] = nil end
    end
    if Main.selectedPlayer >= count then Main.selectedPlayer = 0 end
    return count
end




function Main.selectedPlayerList()
    Main.getPlayerCount()
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
        if id == Main.selectedPlayer then
            for p in pairs(Main.selectedPlayers) do Main.selectedPlayer = p break end
        end
    else
        Main.selectedPlayers[id] = true
        Main.selectedPlayer = id
    end
    Main.updateWindow()
    MGE.Camera.followPlayer(Main.selectedPlayerList())
end


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




function Main.selectedJointList()
    local list = {}
    for _, joint in ipairs(ModData.parsed.env_obj_joint) do
        if joint.id and Main.selectedJoints[joint.id] then table.insert(list, joint) end
    end
    table.sort(list, function(a, b) return a.id < b.id end)
    return list
end



function Main.selectedSlot()
    return Main.jointSlot
end



function Main.linkSlot()
    if Main.listTab ~= "joints" or Main.activeTabs.joints ~= "jointLink" then return nil end
    return Main.jointSlot
end


local function followJoints()
    local ids = MGE.Joints.getObjectIds(Main.selectedJointList())
    local objects = {}
    for _, obj in ipairs(ModData.parsed.env_obj) do
        if ids[obj.id] then table.insert(objects, obj) end
    end
    if MGE.Camera.followMoves and #objects > 0 then MGE.Camera.focus(objects) end
end
Main.followJoints = followJoints



local function dropOtherDraft()
    local draft = MGE.Joints.draft
    if draft and draft.jointId ~= Main.jointSlot then MGE.Joints.resetDraft() end
end






function Main.selectJoint(id, additive)
    local selected = Main.selectedJoints
    if additive and selected[id] then
        if next(selected, nil) ~= id or next(selected, id) ~= nil then
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
    Main.onSelectionChanged()
end



function Main.selectJointsOnly(ids)
    if not ids[1] then return end
    Main.selectedJoints = {}
    for _, id in ipairs(ids) do Main.selectedJoints[id] = true end
    Main.jointSlot = ids[1]
    dropOtherDraft()
end



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




function Main.setListTab(id)
    local changed = Main.listTab ~= id
    Main.listTab = id
    if id ~= "joints" then MGE.Joints.worldPick = false end
    MGE.AtmoLayer.setObjectsSeeThrough(id == "atmo")
    applyListTab()
    Main.applyTab()
    Main.updateWindow()

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
Main.refreshCounters = setDynamicStrings

local function createObjSelector()
    if Main.listTab == "players" then
        player_list.create(obj_selector_container)
    elseif Main.listTab == "joints" then
        joint_list.create(obj_selector_container)
    elseif Main.listTab == "atmo" then
        obj_selector.create(obj_selector_container, ModData.parsed.atmo, "atmo")
    elseif Main.listTab == "misc" then

        Main.setListActions({})
        obj_selector_container:addChild({
            pos = { Widgets.px(8), 0 },
            size = { obj_selector_container.size.w - Widgets.px(16), obj_selector_container.size.h },
        }):addAdaptedText("There's only one world\n ...for now", nil, nil, Widgets.FONT, CENTERMID,
            Widgets.TEXT_SCALE_SMALL, nil, nil)
    else
        obj_selector.create(obj_selector_container, ModData.parsed.env_obj)
    end
end

local function createEditor()
    editor.create(editorContainer)
end


function Main.onSelectionChanged()
    editor.onSelectionChanged()
end

function Main.updateWindow()
    if not Main.window.displayed then return end
    Widgets.clearChildren(obj_selector_container)
    setDynamicStrings()
    createObjSelector()
    Main.onSelectionChanged()
end



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
    if value then Main.selectionMade() end
end


function Main.toggleSelectAllAtmo()
    local list = ModData.parsed.atmo
    local all = #list > 0
    for _, obj in ipairs(list) do
        if not obj.selected then all = false break end
    end
    for _, obj in ipairs(list) do obj.selected = not all or nil end
    Main.updateWindow()
    if not all then Main.selectionMade() end
end

function Main.resetWindow()
    Main.page = 1
    Main.toggleAll = false
    Main.selectedJoints, Main.jointSlot = { [1] = true }, 1
    MGE.Joints.resetDraft()
    Main.updateWindow()
end

function Main.resetEditor()
    Widgets.clearChildren(editorContainer)
    createEditor()
    Main.applyTab()
end

setDynamicStrings()
createObjSelector();
createEditor()
Main.applyTab()
applyListTab()


Main.window.killAction = function() MGE.quit(true) end
return Main
