require("toriui.uielement")

local defaultPos = { 0, 0 }
local margin = 10
local function updateContentHeight(height)
    local h = height or 0
    defaultPos[2] = defaultPos[2] + h + 10 --10 margin
end

local window, windowContainer = TBMenu:spawnMoveableWindow({
    x = margin,
    y = 100,
    w = 500,
    h = 500
})
local content = windowContainer:addChild({
    pos = { margin, margin },
    size = { windowContainer.size.w - margin * 2, windowContainer.size.h - margin * 2 },
}, true)

local obj_label = content:addChild({
    pos = defaultPos,
    size = { content.size.w, 30 },
})
obj_label:addAdaptedText("Objects " .. #MGE.objects.objects .. "/" .. MAX_ENV_OBJECTS)
updateContentHeight(obj_label.size.h)

local obj_selector = content:addChild({
    pos = defaultPos,
    size = { content.size.w, 200 },
    bgColor = TB_MENU_DEFAULT_DARKER_COLOR
})
updateContentHeight(obj_selector.size.h)

local scrollbar = dofile(MGE.scriptPath .. "ui/scrollbar.lua")
scrollbar:create(obj_selector, MGE.objects.objects)

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

window.killAction = MGE.quit
return window
