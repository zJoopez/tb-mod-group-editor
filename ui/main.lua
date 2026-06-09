require("toriui.uielement")

---@class Main
---@field window UIElement
---@field pageStr string
---@field page integer
---@field pageSize integer
---@field toggleAll boolean
Main = { page = 1, pageSize = 64, toggleAll = false }

local defaultPos = { 0, 0 }
local margin = 10
local function updateContentHeight(height)
    local h = height or 0
    defaultPos[2] = defaultPos[2] + h + 10 --10 margin
end

Main.window, windowContainer = TBMenu:spawnMoveableWindow({
    x = margin,
    y = 100,
    w = 400,
    h = 700
})
local content = windowContainer:addChild({
    pos = { margin, margin },
    size = { windowContainer.size.w - margin * 2, windowContainer.size.h - margin * 2 },
}, true)

local titleObjCount = content:addChild({
    pos = defaultPos,
    size = { content.size.w, 30 },
})
updateContentHeight(titleObjCount.size.h)

local obj_selector_container = content:addChild({
    pos = defaultPos,
    size = { content.size.w, 200 },
    bgColor = TB_MENU_DEFAULT_DARKER_COLOR
})
updateContentHeight(obj_selector_container.size.h)

local editorContainer = content:addChild({
    pos = defaultPos,
    size = { content.size.w, 300 },
})
updateContentHeight(editorContainer.size.h)

-- local btnAssets = content:addChild({
--     pos = defaultPos,
--     size = { content.size.w, 30 },
--     interactive = true,
--     bgColor = TB_MENU_DEFAULT_DARKER_COLOR,
--     hoverColor = TB_MENU_DEFAULT_LIGHTER_COLOR,
--     pressedColor = TB_MENU_DEFAULT_DARKEST_COLOR,
-- })
-- btnAssets:addAdaptedText("Assets")
-- updateContentHeight(btnAssets.size.h)

-- btnAssets:addMouseUpHandler(function()
--     if not MGE.assetWindow then
--         MGE.assetWindow = dofile(MGE.scriptPath .. "/ui/assets.lua")
--     else
--         MGE.assetWindow:show()
--     end
-- end)

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


local obj_selector = dofile(MGE.scriptPath .. "ui/obj_selector.lua")
local editor = dofile(MGE.scriptPath .. "ui/editor.lua")

local function setDynamicStrings()
    titleObjCount:addAdaptedText("Objects " .. #ModData.parsed.env_obj .. "/" .. MAX_ENV_OBJECTS)
    Main.pageStr = "Page " .. Main.page .. "/" .. math.max(math.ceil(#ModData.parsed.env_obj / Main.pageSize), 1)
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

setDynamicStrings()
createObjSelector(false);
createEditor()

Main.window.killAction = MGE.quit
return Main
