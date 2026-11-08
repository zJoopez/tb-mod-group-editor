require("toriui.uielement")

---@class Main
---@field window UIElement
---@field page integer
---@field pageSize integer
---@field toggleAll boolean
---@field activeTab "values"|"options"|"assets"
local Main = { page = 1, pageSize = 64, toggleAll = false, activeTab = "values" }
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
    h = 625
})
local content = windowContainer:addChild({
    pos = { margin, margin },
    size = { windowContainer.size.w - margin * 2, windowContainer.size.h - margin * 2 },
}, true)

-- top menu: file and history actions, shortcuts to the game's own mod list and gamerules menus,
-- shortcut help at the end. Same bar style as the list bars
local menuH = 25
local helpSize = menuH - 4
local menuBar = content:addChild({
    pos = defaultPos,
    size = { content.size.w, menuH },
    bgColor = TB_MENU_DEFAULT_BG_COLOR,
})
local menuButtons = menuBar:addChild({
    pos = { 0, 0 },
    size = { menuBar.size.w - helpSize - 6, menuH },
})
Widgets.barButtons(menuButtons, {
    -- named copy of the mod, Ctrl+S saves the working file (see shortcut help)
    { label = "Save as", onClick = function() dofile(MGE.scriptPath .. "ui/save_overlay.lua") end },
    { label = "Undo", onClick = function() History.undo() end },
    { label = "Redo", onClick = function() History.redo() end },
    { label = "Mods", onClick = function() dofile("system/mods.lua") end },           -- game's mod list
    { label = "Rules", onClick = function() dofile("system/gamerules.lua") end },     -- game's gamerules menu
})
Widgets.helpIcon(menuBar, -helpSize - 2, 2, helpSize,
    "Shortcuts\n" ..
    "F1: show / hide this window\n" ..
    "Ctrl + S: save edits to the working file and reload it\n" ..
    "Ctrl + A: select / deselect all objects\n" ..
    "Shift + Z: undo\n" ..
    "Shift + Y: redo\n" ..
    "Enter: apply the value typed in an input field\n" ..
    "Click an object in the world: select / deselect it\n" ..
    "Drag / mouse wheel: orbit / zoom the camera after looking at objects")
updateContentHeight(menuH)

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
    { id = "values", label = "Values" },
    { id = "options", label = "Options" },
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
-- (240 fits the 7 input rows of the Values panel with the reset button under them)
local editorContainer = content:addChild({
    pos = defaultPos,
    size = { content.size.w, 240 },
})
local assetsContainer = content:addChild({
    pos = defaultPos,
    size = { content.size.w, 240 },
})
updateContentHeight(editorContainer.size.h)

-- Duplicate/Delete/Reindex are in the object list's bottom bar (ui/obj_selector.lua)

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
local limitsRow = addFooterRow() -- object, dynamic id and joint usage, set by setDynamicStrings
addFooterRow("Project Mod Group Editor by joopez")


dofile(MGE.scriptPath .. "ui/scroll_list.lua") -- MGE.ScrollList, used by obj_selector and assets
local obj_selector = dofile(MGE.scriptPath .. "ui/obj_selector.lua")
local editor = dofile(MGE.scriptPath .. "ui/editor.lua")
local assetsView = dofile(MGE.scriptPath .. "ui/assets.lua")

-- Values and Options are two panels of the editor area, Assets has its own area
local tabContainers = { values = editorContainer, options = editorContainer, assets = assetsContainer }

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

---@param id "values"|"options"|"assets"
function Main.setTab(id)
    if not tabContainers[id] then return end
    Main.activeTab = id
    Main.applyTab()
end

local function setDynamicStrings()
    Widgets.infoText(limitsRow, "Objects " .. #ModData.parsed.env_obj .. "/" .. MGE.MAX_ENV_OBJECTS ..
        "    Dynamic " .. ModData.countDynamic() .. "/" .. MGE.MAX_NONSTATIC_OBJECTS ..
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

---Selects or deselects every object ("Toggle All" checkbox, Ctrl+A)
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
