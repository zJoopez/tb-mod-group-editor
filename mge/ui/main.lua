require("toriui.uielement")

---@class Main
---@field window UIElement
---@field page integer
---@field pageSize integer
---@field toggleAll boolean
---@field activeTab "transform"|"properties"|"assets"
local Main = { page = 1, pageSize = 64, toggleAll = false, activeTab = "transform" }
MGE.Main = Main -- registered before UI modules load so they can alias it

local ModData = MGE.ModData
local History = MGE.History
local Widgets = dofile(MGE.scriptPath .. "ui/widgets.lua") -- MGE.Widgets, shared button helpers

local defaultPos = { 0, 0 }
local margin = 10
local function updateContentHeight(height)
    local h = height or 0
    defaultPos[2] = defaultPos[2] + h + 10 --10 margin
end

local windowContainer
Main.window, windowContainer = TBMenu:spawnMoveableWindow({
    x = margin,
    y = 100,
    w = 400,
    h = 750
})
local content = windowContainer:addChild({
    pos = { margin, margin },
    size = { windowContainer.size.w - margin * 2, windowContainer.size.h - margin * 2 },
}, true)

-- object count on the left, undo/redo buttons on the right
local historyW = 125 -- two 60px buttons and a 5px gap
local titleY = defaultPos[2]
local titleObjCount = content:addChild({
    pos = { 0, titleY },
    size = { content.size.w - historyW - margin, 30 },
})
local historyHolder = content:addChild({
    pos = { content.size.w - historyW, titleY },
    size = { historyW, 30 },
})
Widgets.buttonRow(historyHolder, 2, 26, {
    { label = "Undo", onClick = function() History.undo() end },
    { label = "Redo", onClick = function() History.redo() end },
}, 5)
updateContentHeight(titleObjCount.size.h)

local obj_selector_container = content:addChild({
    pos = defaultPos,
    size = { content.size.w, 200 },
    bgColor = TB_MENU_DEFAULT_DARKER_COLOR
})
updateContentHeight(obj_selector_container.size.h)

-- Tabs, right above the area they switch (title row and object list stay the same on every tab)
local tabRow = content:addChild({
    pos = defaultPos,
    size = { content.size.w, 30 },
})
updateContentHeight(tabRow.size.h)

local tabNames = {
    { id = "transform", label = "Transform" },
    { id = "properties", label = "Properties" },
    { id = "assets", label = "Assets" },
}
local tabItems = {}
for i, tab in ipairs(tabNames) do
    tabItems[i] = { label = tab.label, onClick = function() Main.setTab(tab.id) end }
end
local tabButtons = {}
for i, btn in ipairs(Widgets.buttonRow(tabRow, 0, tabRow.size.h, tabItems, margin)) do
    tabButtons[tabNames[i].id] = btn
end

-- editor and assets tabs share the same area, only one is shown at a time
-- (300 fits the Properties panel with the hint, reset and duplicate/delete rows under it)
local editorContainer = content:addChild({
    pos = defaultPos,
    size = { content.size.w, 300 },
})
local assetsContainer = content:addChild({
    pos = defaultPos,
    size = { content.size.w, 300 },
})
updateContentHeight(editorContainer.size.h)

-- Save/Export stay available on every tab
local fileRow = content:addChild({
    pos = defaultPos,
    size = { content.size.w, 30 },
})
Widgets.buttonRow(fileRow, 0, fileRow.size.h, {
    { label = "Save", onClick = function() MGE.save() end },
    { label = "Export", onClick = function() dofile(MGE.scriptPath .. "ui/save_overlay.lua") end },
}, margin)
updateContentHeight(fileRow.size.h)

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
    updateContentHeight(row.size.h - margin)
    return row
end
local limitsRow = addFooterRow() -- dynamic id and joint usage, set by setDynamicStrings
addFooterRow("F1 shows/hides window")
addFooterRow("Project Mod Group Editor by joopez")


dofile(MGE.scriptPath .. "ui/scroll_list.lua") -- MGE.ScrollList, used by obj_selector and assets
local obj_selector = dofile(MGE.scriptPath .. "ui/obj_selector.lua")
local editor = dofile(MGE.scriptPath .. "ui/editor.lua")
local assetsView = dofile(MGE.scriptPath .. "ui/assets.lua")

-- Transform and Properties are two panels of the editor area, Assets has its own area
local tabContainers = { transform = editorContainer, properties = editorContainer, assets = assetsContainer }

---Shows the active tab's area (and editor panel) and hides the rest.
---hide(true) keeps hidden areas hidden when the window is re-shown (F1)
function Main.applyTab()
    local active = tabContainers[Main.activeTab]
    for _, container in pairs({ editorContainer, assetsContainer }) do
        if container ~= active then container:hide(true) end
    end
    active:show(true)
    if active == editorContainer then
        editor.applyPanel(Main.activeTab)
    end
    for id, btn in pairs(tabButtons) do
        btn.bgColor = id == Main.activeTab and TB_MENU_DEFAULT_LIGHTER_COLOR or TB_MENU_DEFAULT_DARKER_COLOR
    end
end

---@param id "transform"|"properties"|"assets"
function Main.setTab(id)
    if not tabContainers[id] then return end
    Main.activeTab = id
    Main.applyTab()
end

local function setDynamicStrings()
    titleObjCount:addAdaptedText("Objects " .. #ModData.parsed.env_obj .. "/" .. MGE.MAX_ENV_OBJECTS, nil, nil, nil, LEFTMID, nil, nil, nil)
    Widgets.infoText(limitsRow, "Dynamic " .. ModData.countDynamic() .. "/" .. MGE.MAX_NONSTATIC_OBJECTS ..
        "    Joints " .. #ModData.parsed.env_obj_joint .. "/" .. MGE.MAX_ENV_JOINTS)
end

local function createObjSelector()
    obj_selector.create(obj_selector_container, ModData.parsed.env_obj)
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
    Main.onSelectionChanged() -- called after toggle all, saves and reloads
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
assetsView.create(assetsContainer)
Main.applyTab()

-- closing the window quits the script, window is already being killed so quit skips it
Main.window.killAction = function() MGE.quit(true) end
return Main
