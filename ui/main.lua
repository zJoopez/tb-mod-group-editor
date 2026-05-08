require("toriui.uielement")

local window, windowContainer = TBMenu:spawnMoveableWindow({
    x = 10,
    y = 100,
    w = 300,
    h = 500
})
local content = windowContainer:addChild({
    pos = { 10, 10 },
    size = { windowContainer.size.w - 20, windowContainer.size.h - 20 },
}, true)

local btnSave = content:addChild({
    size = { content.size.w, 30 },
    interactive = true,
    bgColor = TB_MENU_DEFAULT_DARKER_COLOR,
    hoverColor = TB_MENU_DEFAULT_LIGHTER_COLOR,
    pressedColor = TB_MENU_DEFAULT_DARKEST_COLOR,
})
btnSave:addAdaptedText("save")

local btnAssets = content:addChild({
    pos = { 0, 40 },
    size = { content.size.w, 30 },
    interactive = true,
    bgColor = TB_MENU_DEFAULT_DARKER_COLOR,
    hoverColor = TB_MENU_DEFAULT_LIGHTER_COLOR,
    pressedColor = TB_MENU_DEFAULT_DARKEST_COLOR,
})
btnAssets:addAdaptedText("Assets")

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

window.killAction = MGE.quit
return window
