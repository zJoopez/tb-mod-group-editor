require("toriui.uielement")

function MGE.initUI()
    MGE.window, MGE.windowContainer = TBMenu:spawnMoveableWindow({
        x = 10,
        y = 100,
        w = 300,
        h = 500
    })
    local content = MGE.windowContainer:addChild({
        pos = { 10, 10 },
        size = { MGE.windowContainer.size.w - 20, MGE.windowContainer.size.h - 20 },
    }, true)

    local saveBtn = content:addChild({
        size = { content.size.w, 30 },
        interactive = true,
        bgColor = TB_MENU_DEFAULT_DARKER_COLOR,
        hoverColor = TB_MENU_DEFAULT_LIGHTER_COLOR,
        pressedColor = TB_MENU_DEFAULT_DARKEST_COLOR,
    })
    saveBtn:addAdaptedText("save")

    local btn2 = content:addChild({
        pos = { 0, 40 },
        size = { content.size.w, 30 },
        interactive = true,
        bgColor = TB_MENU_DEFAULT_DARKER_COLOR,
        hoverColor = TB_MENU_DEFAULT_LIGHTER_COLOR,
        pressedColor = TB_MENU_DEFAULT_DARKEST_COLOR,
    })
    btn2:addAdaptedText("parse")

    saveBtn:addMouseUpHandler(function()
        MGE.save()
    end)

    btn2:addMouseUpHandler(function()
        MGE.updateSource()
    end)

    MGE.window.killAction = MGE.quit
end