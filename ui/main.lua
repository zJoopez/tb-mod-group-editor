require("toriui.uielement")

---@class Main
---@field window UIElement
Main = {}

local defaultPos = { 0, 0 }
local margin = 10
local function updateContentHeight(height)
    local h = height or 0
    defaultPos[2] = defaultPos[2] + h + 10 --10 margin
end

Main.window, windowContainer = TBMenu:spawnMoveableWindow({
    x = margin,
    y = 100,
    w = 500,
    h = 500
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

local obj_selector = content:addChild({
    pos = defaultPos,
    size = { content.size.w, 200 },
    bgColor = TB_MENU_DEFAULT_DARKER_COLOR
})
updateContentHeight(obj_selector.size.h)

local btnAssets = content:addChild({
    pos = defaultPos,
    size = { content.size.w, 30 },
    interactive = true,
    bgColor = TB_MENU_DEFAULT_DARKER_COLOR,
    hoverColor = TB_MENU_DEFAULT_LIGHTER_COLOR,
    pressedColor = TB_MENU_DEFAULT_DARKEST_COLOR,
})
btnAssets:addAdaptedText("Assets")
updateContentHeight(btnAssets.size.h)

local btnSave = content:addChild({
    pos = defaultPos,
    size = { content.size.w, 30 },
    interactive = true,
    bgColor = TB_MENU_DEFAULT_DARKER_COLOR,
    hoverColor = TB_MENU_DEFAULT_LIGHTER_COLOR,
    pressedColor = TB_MENU_DEFAULT_DARKEST_COLOR,
})
updateContentHeight(btnSave.size.h)

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
copyright:addAdaptedText(true, "script by joopez", nil, nil, FONTS.SMALL, CENTER, 0.6)
updateContentHeight(copyright.size.h)

local scrollbar = dofile(MGE.scriptPath  .. "ui/scrollbar.lua")

local function createObjTitle()
    titleObjCount:addAdaptedText("Objects " .. #MGE.objects.objects .. "/" .. MAX_ENV_OBJECTS)
end

function Main.createScrollBar()
    scrollbar.create(obj_selector, MGE.objects.objects)
end

function Main.updateWindow()
    obj_selector:kill(true)
    Main.createScrollBar()
    createObjTitle()
end

btnSave:addAdaptedText("Save")
updateContentHeight(btnSave.size.h)

btnSave:addMouseUpHandler(function()
    MGE.save()
end)

btnAssets:addMouseUpHandler(function()
    if not MGE.assetWindow then
        MGE.assetWindow = dofile(MGE.scriptPath .. "/ui/assets.lua")
    else
        MGE.assetWindow:show()
    end
end)

createObjTitle()
Main.createScrollBar();

Main.window.killAction = MGE.quit
return Main
