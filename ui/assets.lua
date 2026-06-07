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

window.killAction = function()
    MGE.assetWindow = nil
end

return window
