-- Shared button helpers so every button looks the same and rows line up with the window edges

---@class Widgets
local Widgets = {}

---@class WidgetRect
---@field x number
---@field y number
---@field w number
---@field h number

---Standard MGE button
---@param parent UIElement
---@param rect WidgetRect position relative to parent
---@param label string|fun(): string function labels are re-read every frame
---@param onClick function?
---@param textScale number? omit to let the text adapt to the button size
---@return UIElement
function Widgets.button(parent, rect, label, onClick, textScale)
    local btn = parent:addChild({
        pos = { rect.x, rect.y },
        size = { rect.w, rect.h },
        interactive = true,
        bgColor = TB_MENU_DEFAULT_DARKER_COLOR,
        hoverColor = TB_MENU_DEFAULT_LIGHTER_COLOR,
        pressedColor = TB_MENU_DEFAULT_DARKEST_COLOR,
    }, true)
    if type(label) == "function" then
        btn:addCustomDisplay(false, function()
            btn:uiText(label(), nil, nil, nil, CENTERMID, textScale or 0.8, nil, nil, nil)
        end)
    elseif textScale then
        btn:addAdaptedText(label, nil, nil, nil, CENTERMID, textScale, nil, nil)
    else
        btn:addAdaptedText(label)
    end
    if onClick then btn:addMouseUpHandler(onClick) end
    return btn
end

---Equal width buttons filling the parent's width exactly: n buttons and n - 1 gaps between them
---@param parent UIElement
---@param y number
---@param h number
---@param buttons { label: string|fun(): string, onClick: function? }[]
---@param gap number space between buttons
---@param textScale number?
---@return UIElement[]
function Widgets.buttonRow(parent, y, h, buttons, gap, textScale)
    local count = #buttons
    local w = (parent.size.w - gap * (count - 1)) / count
    local created = {}
    for i, info in ipairs(buttons) do
        created[i] = Widgets.button(parent, { x = (i - 1) * (w + gap), y = y, w = w, h = h },
            info.label, info.onClick, textScale)
    end
    return created
end

-- buttons inside list bars (object list, asset list): 2px top/bottom padding, small text
local BAR_PADDING = 2
local BAR_GAP = 4

---Buttons filling a list bar with the shared bar padding (e.g. reindex, export/import)
---@param bar UIElement
---@param buttons { label: string|fun(): string, onClick: function? }[]
---@return UIElement[]
function Widgets.barButtons(bar, buttons)
    return Widgets.buttonRow(bar, BAR_PADDING, bar.size.h - BAR_PADDING * 2, buttons, BAR_GAP, 0.7)
end

MGE.Widgets = Widgets
return Widgets
