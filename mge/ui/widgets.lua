


local Widgets = {}










Widgets.UI_SCALE = tonumber(MGE_UI_SCALE) or 1.3
Widgets.UI_SCALES = { 1, 1.15, 1.3, 1.5, 1.75 }




function Widgets.px(n)
    return math.floor(n * Widgets.UI_SCALE + 0.5)
end



Widgets.FONT = FONTS.LMEDIUM



Widgets.TEXT_SCALE = 0.5 * Widgets.UI_SCALE
Widgets.TEXT_SCALE_SMALL = 0.45 * Widgets.UI_SCALE
Widgets.TAB_TEXT_SCALE = 0.42 * Widgets.UI_SCALE
Widgets.BUTTON_TEXT_SCALE = 0.45 * Widgets.UI_SCALE
Widgets.TITLE_SCALE = 0.7 * Widgets.UI_SCALE

Widgets.ROW_H = Widgets.px(24)
Widgets.PANEL_ROWS = 9

Widgets.LIST_ROW_H = Widgets.px(20)


Widgets.GAP = 2


Widgets.INSET = Widgets.GAP / 2






function Widgets.mix(a, b, t)
    return { a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t, 1 }
end



Widgets.HOVER_COLOR = Widgets.mix(TB_MENU_DEFAULT_BG_COLOR, TB_MENU_DEFAULT_LIGHTER_COLOR, 0.4)

Widgets.SELECTED_COLOR = Widgets.mix(TB_MENU_DEFAULT_BG_COLOR, TB_MENU_DEFAULT_LIGHTEST_COLOR, 0.5)


Widgets.ACTIVE_COLOR = Widgets.SELECTED_COLOR




local function darkest(share)
    local c = TB_MENU_DEFAULT_DARKEST_COLOR
    return { c[1] * share, c[2] * share, c[3] * share, 1 }
end

Widgets.BAR_COLOR = darkest(0.8)


Widgets.CONTENT_BG = darkest(0.9)









Widgets.STYLE = {
    bg = TB_MENU_DEFAULT_BG_COLOR,
    hover = Widgets.HOVER_COLOR,
    pressed = TB_MENU_DEFAULT_DARKEST_COLOR,
}

Widgets.PANEL_STYLE = Widgets.STYLE


Widgets.TAB_PANEL_COLOR = { 0, 0, 0, 0.15 }


Widgets.TAB_PANEL_SOLID = {
    TB_MENU_DEFAULT_BG_COLOR[1] * (1 - Widgets.TAB_PANEL_COLOR[4]),
    TB_MENU_DEFAULT_BG_COLOR[2] * (1 - Widgets.TAB_PANEL_COLOR[4]),
    TB_MENU_DEFAULT_BG_COLOR[3] * (1 - Widgets.TAB_PANEL_COLOR[4]),
    1,
}









function Widgets.button(parent, rect, label, onClick, textScale, style)
    textScale = textScale or Widgets.BUTTON_TEXT_SCALE
    style = style or Widgets.STYLE
    local btn = parent:addChild({
        pos = { rect.x, rect.y },
        size = { rect.w, rect.h },
        interactive = true,
        bgColor = style.bg,
        hoverColor = style.hover,
        pressedColor = style.pressed,
    }, true)
    if type(label) == "function" then
        btn:addCustomDisplay(false, function()
            btn:uiText(label(), nil, nil, Widgets.FONT, CENTERMID, textScale, nil, nil, nil)
        end)
    elseif label ~= "" then
        btn:addAdaptedText(label, nil, nil, Widgets.FONT, CENTERMID, textScale, nil, nil)
    end
    if onClick then btn:addMouseUpHandler(onClick) end
    return btn
end








function Widgets.iconButton(parent, rect, image, onClick, style)
    local btn = Widgets.button(parent, rect, "", onClick, nil, style)
    local size = math.min(rect.w, rect.h) - 6
    Widgets.trackImage(btn:addChild({
        pos = { (rect.w - size) / 2, (rect.h - size) / 2 },
        size = { size, size },
        bgImage = image,
    }), image)
    return btn
end






local trackedImages = setmetatable({}, { __mode = "k" })





function Widgets.trackImage(element, image)
    trackedImages[element] = image
    return element
end



function Widgets.reloadImages()
    for element, image in pairs(trackedImages) do
        if element.destroyed then
            trackedImages[element] = nil
        else
            element.bgImage = nil
            element:updateImage(image, nil, true)
        end
    end
end



Widgets.onScreenChanged = {}

add_hook("resolution_changed", MGE.hookname, function()
    Widgets.reloadImages()
    for _, callback in ipairs(Widgets.onScreenChanged) do pcall(callback) end
end)














function Widgets.popupBelowLeft(element, message)
    local popup = TBMenu:displayPopup(element, message)
    if popup then popup:moveTo(-popup.size.w, element.size.h + 4) end
    return popup
end







function Widgets.popupBelow(element, message)
    local popup = TBMenu:displayPopup(element, message)
    if not popup then return nil end
    local gap, margin = 4, 10

    local x, y = 0.0, element.size.h + gap
    local overflow = element.pos.x + popup.size.w - (WIN_W - margin)
    if overflow > 0 then x = -overflow end
    if element.pos.y + y + popup.size.h > WIN_H - margin then y = -(popup.size.h + gap) end


    popup:moveTo(0, 0)
    popup:moveTo(x, y, true)
    return popup
end




function Widgets.closeOnEscape(field)
    field:addKeyboardHandlers(function(key)
        if key == 27 and MGE and MGE.closeTopOverlay then MGE.closeTopOverlay() end
    end)
end






function Widgets.addDrawBefore(element, func)
    local previous = element.customDisplayBefore
    element:addCustomDisplay(false, function(...)
        if previous then previous(...) end
        func()
    end, true)
end












function Widgets.buttonRow(parent, y, h, buttons, gap, textScale, style)
    local squareCount = 0
    for _, info in ipairs(buttons) do
        if info.icon and not info.wide then squareCount = squareCount + 1 end
    end
    local sharedCount = #buttons - squareCount
    local sharedW = sharedCount > 0 and (parent.size.w - gap * (#buttons - 1) - squareCount * h) / sharedCount or 0
    local created = {}
    local x = 0
    for i, info in ipairs(buttons) do
        local w = (info.icon and not info.wide) and h or sharedW
        local rect = { x = x, y = y, w = w, h = h }
        if info.icon then
            created[i] = Widgets.iconButton(parent, rect, info.icon, info.onClick, style)
            local label = info.label
            if type(label) == "string" and label ~= "" then

                local place = info.popupLeft and Widgets.popupBelowLeft or Widgets.popupBelow
                place(created[i], label)
            end
        else
            created[i] = Widgets.button(parent, rect, info.label, info.onClick, textScale, style)
        end
        x = x + w + gap
    end
    return created
end






function Widgets.releaseKeyboard(element)
    if not UIKeyboardHandler or not element then return end
    local owned = { [element] = true }
    local function collect(e)
        for _, c in ipairs(e.child or {}) do
            owned[c] = true
            collect(c)
        end
    end
    collect(element)
    for i = #UIKeyboardHandler, 1, -1 do
        local v = UIKeyboardHandler[i]
        if owned[v] then
            if v.menuKeyboardId then v:disableMenuKeyboard() end
            table.remove(UIKeyboardHandler, i)
        end
    end
end



function Widgets.clearChildren(element)
    for _, c in ipairs(element.child or {}) do Widgets.releaseKeyboard(c) end
    element:kill(true)
end











function Widgets.helpIcon(parent, x, y, size, message, mark, style)
    style = style or Widgets.STYLE
    local icon = parent:addChild({
        pos = { x, y },
        size = { size, size },
        bgColor = style.bg,
        hoverColor = style.hover,
        pressedColor = style.pressed,
        interactive = true,
        shapeType = ROUNDED,
        rounded = size,
    })
    icon:addChild({}):addAdaptedText(true, mark or "?", nil, nil, Widgets.FONT, nil, Widgets.TEXT_SCALE)
    local popup = TBMenu:displayHelpPopup(icon, message, nil, true)
    if popup then
        popup:moveTo(size + 5, (size - popup.size.h) / 2, true)
    end
    return icon
end






function Widgets.isMouseOverUI(x, y)
    local window = MGE.Main and MGE.Main.window
    if window and window.displayed and x >= window.pos.x and x <= window.pos.x + window.size.w
        and y >= window.pos.y and y <= window.pos.y + window.size.h then
        return true
    end

    for _, element in ipairs(UIMouseHandler or {}) do
        if not element.clickThrough and element:shouldReceiveInput()
            and x > element.pos.x and x < element.pos.x + element.size.w
            and y > element.pos.y and y < element.pos.y + element.size.h then
            return true
        end
    end
    return false
end


Widgets.INFO_HEIGHT = Widgets.px(18)
local INFO_MAX_SCALE = 0.7 * Widgets.UI_SCALE





function Widgets.infoText(element, text, align)
    element:addAdaptedText(true, text, nil, nil, FONTS.SMALL, align or CENTERMID, INFO_MAX_SCALE)
end

MGE.Widgets = Widgets
return Widgets
