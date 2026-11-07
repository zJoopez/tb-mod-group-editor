require("toriui.uielement")

---@class Main
---@field window UIElement
---@field page integer
---@field pageSize integer
---@field toggleAll boolean
---@field activeTab "editor"|"assets"
local Main = { page = 1, pageSize = 64, toggleAll = false, activeTab = "editor" }
MGE.Main = Main -- registered before UI modules load so they can alias it

local ModData = MGE.ModData
local History = MGE.History

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
    h = 670
})
local content = windowContainer:addChild({
    pos = { margin, margin },
    size = { windowContainer.size.w - margin * 2, windowContainer.size.h - margin * 2 },
}, true)

-- Tabs
local tabRow = content:addChild({
    pos = defaultPos,
    size = { content.size.w, 30 },
})
updateContentHeight(tabRow.size.h)

local tabButtons = {}
local tabNames = { { id = "editor", label = "Editor" }, { id = "assets", label = "Assets" } }
for i, tab in ipairs(tabNames) do
    local tabWidth = (tabRow.size.w - margin) / #tabNames
    local btn = tabRow:addChild({
        pos = { (i - 1) * (tabWidth + margin), 0 },
        size = { tabWidth, tabRow.size.h },
        interactive = true,
        bgColor = TB_MENU_DEFAULT_DARKER_COLOR,
        hoverColor = TB_MENU_DEFAULT_LIGHTER_COLOR,
        pressedColor = TB_MENU_DEFAULT_DARKEST_COLOR,
    }, true)
    btn:addAdaptedText(tab.label, nil, nil, nil, CENTERMID, 0.7, nil, nil)
    btn:addMouseUpHandler(function()
        Main.setTab(tab.id)
    end)
    tabButtons[tab.id] = btn
end

-- object count on the left, undo/redo buttons on the right
local historyBtnW = 60
local titleY = defaultPos[2]
local titleObjCount = content:addChild({
    pos = { 0, titleY },
    size = { content.size.w - (historyBtnW + 5) * 2, 30 },
})
for i, btnInfo in ipairs({ { "Undo", function() History.undo() end }, { "Redo", function() History.redo() end } }) do
    local btn = content:addChild({
        pos = { content.size.w - (historyBtnW + 5) * (3 - i) + 5, titleY + 2 },
        size = { historyBtnW, 26 },
        interactive = true,
        bgColor = TB_MENU_DEFAULT_DARKER_COLOR,
        hoverColor = TB_MENU_DEFAULT_LIGHTER_COLOR,
        pressedColor = TB_MENU_DEFAULT_DARKEST_COLOR,
    }, true)
    btn:addAdaptedText(btnInfo[1], nil, nil, nil, CENTERMID, 0.7, nil, nil)
    btn:addMouseUpHandler(btnInfo[2])
end
updateContentHeight(titleObjCount.size.h)

local obj_selector_container = content:addChild({
    pos = defaultPos,
    size = { content.size.w, 200 },
    bgColor = TB_MENU_DEFAULT_DARKER_COLOR
})
updateContentHeight(obj_selector_container.size.h)

-- editor and assets tabs share the same area, only one is shown at a time
local editorContainer = content:addChild({
    pos = defaultPos,
    size = { content.size.w, 280 },
})
local assetsContainer = content:addChild({
    pos = defaultPos,
    size = { content.size.w, 280 },
})
updateContentHeight(editorContainer.size.h)

local info = content:addChild({
    pos = defaultPos,
    size = { content.size.w, 15 },
    bgColor = { 0, 0, 0, 0 }
})
info:addAdaptedText(true, "F1 shows/hides window", nil, nil, FONTS.SMALL, CENTER, 0.6)
updateContentHeight(info.size.h - margin)

-- copyright
local copyright = content:addChild({
    pos = defaultPos,
    size = { content.size.w, 15 },
    bgColor = { 0, 0, 0, 0 }
})
copyright:addAdaptedText(true, "Project Mod Group Editor by joopez", nil, nil, FONTS.SMALL, CENTER, 0.6)
updateContentHeight(copyright.size.h)


dofile(MGE.scriptPath .. "ui/scroll_list.lua") -- MGE.ScrollList, used by obj_selector and assets
local obj_selector = dofile(MGE.scriptPath .. "ui/obj_selector.lua")
local editor = dofile(MGE.scriptPath .. "ui/editor.lua")
local assetsView = dofile(MGE.scriptPath .. "ui/assets.lua")

local tabContainers = { editor = editorContainer, assets = assetsContainer }

---Shows the active tab and hides the rest. hide(true) keeps hidden tabs hidden when the window is re-shown (F1)
function Main.applyTab()
    for id, container in pairs(tabContainers) do
        if id == Main.activeTab then
            container:show(true)
        else
            container:hide(true)
        end
        tabButtons[id].bgColor = id == Main.activeTab and TB_MENU_DEFAULT_LIGHTER_COLOR or TB_MENU_DEFAULT_DARKER_COLOR
    end
end

---@param id "editor"|"assets"
function Main.setTab(id)
    if not tabContainers[id] then return end
    Main.activeTab = id
    Main.applyTab()
end

local function setDynamicStrings()
    titleObjCount:addAdaptedText("Objects " .. #ModData.parsed.env_obj .. "/" .. MGE.MAX_ENV_OBJECTS, nil, nil, nil, LEFTMID, nil, nil, nil)
end

local function createObjSelector()
    obj_selector.create(obj_selector_container, ModData.parsed.env_obj)
end

local function createEditor()
    editor.create(editorContainer)
end

function Main.updateWindow()
    if not Main.window.displayed then return end
    obj_selector_container:kill(true)
    setDynamicStrings()
    createObjSelector()
end

function Main.resetWindow()
    Main.page = 1
    Main.toggleAll = false
    Main.updateWindow()
end

function Main.resetEditor()
    editorContainer:kill(true)
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
