-- Shared button helpers so every button looks the same and rows line up with the window edges

---@class Widgets
local Widgets = {}

---@class WidgetRect
---@field x number
---@field y number
---@field w number
---@field h number

-- one text size for every button (tabs, bars, editor rows), adapted text only shrinks it to fit
Widgets.TEXT_SCALE = 0.7

---Standard MGE button
---@param parent UIElement
---@param rect WidgetRect position relative to parent
---@param label string|fun(): string function labels are re-read every frame
---@param onClick function?
---@param textScale number? defaults to Widgets.TEXT_SCALE
---@return UIElement
function Widgets.button(parent, rect, label, onClick, textScale)
    textScale = textScale or Widgets.TEXT_SCALE
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
            btn:uiText(label(), nil, nil, nil, CENTERMID, textScale, nil, nil, nil)
        end)
    else
        btn:addAdaptedText(label, nil, nil, nil, CENTERMID, textScale, nil, nil)
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

-- buttons inside list bars (object list, asset list): 2px top/bottom padding
local BAR_PADDING = 2
local BAR_GAP = 4

---Buttons filling a list bar with the shared bar padding (e.g. reindex, export/import)
---@param bar UIElement
---@param buttons { label: string|fun(): string, onClick: function? }[]
---@return UIElement[]
function Widgets.barButtons(bar, buttons)
    return Widgets.buttonRow(bar, BAR_PADDING, bar.size.h - BAR_PADDING * 2, buttons, BAR_GAP)
end

---Removes an element and its descendants from toriui's keyboard handler list (UIKeyboardHandler).
---Text fields and toggles add themselves there on creation, but kill() only removes the one that
---has focus. UI that is rebuilt often (object list, properties panel) would keep piling up dead
---entries, and toriui walks the whole list on every key press and mouse click.
---@param element UIElement
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

---Destroys an element's children (kill(true)) without leaving them in toriui's keyboard list
---@param element UIElement
function Widgets.clearChildren(element)
    for _, c in ipairs(element.child or {}) do Widgets.releaseKeyboard(c) end
    element:kill(true)
end

---Round icon that shows a short explanation on hover (TBMenu:displayHelpPopup), same style as
---the game's mods menu. The popup opens on the right side of the icon
---@param parent UIElement
---@param x number negative values count from the parent's right edge
---@param y number
---@param size number
---@param message string
---@param mark string? icon text, defaults to "?"
---@return UIElement
function Widgets.helpIcon(parent, x, y, size, message, mark)
    local icon = parent:addChild({
        pos = { x, y },
        size = { size, size },
        bgColor = TB_MENU_DEFAULT_DARKER_COLOR,
        hoverColor = TB_MENU_DEFAULT_DARKEST_COLOR,
        pressedColor = TB_MENU_DEFAULT_DARKEST_COLOR,
        interactive = true,
        shapeType = ROUNDED,
        rounded = size,
    })
    icon:addChild({}):addAdaptedText(true, mark or "?", nil, nil, nil, nil, 0.7)
    local popup = TBMenu:displayHelpPopup(icon, message, nil, true) -- true: our own mark above
    if popup then
        popup:moveTo(size + 5, (size - popup.size.h) / 2, true)
    end
    return icon
end

---True when the screen position is on MGE's window or any other interactive UI, used to keep
---world clicks and camera zoom from reacting to clicks/scrolls meant for menus
---@param x number
---@param y number
---@return boolean
function Widgets.isMouseOverUI(x, y)
    local window = MGE.Main and MGE.Main.window
    if window and window.displayed and x >= window.pos.x and x <= window.pos.x + window.size.w
        and y >= window.pos.y and y <= window.pos.y + window.size.h then
        return true
    end
    -- same test toriui uses for its buttons (UIElement.handleMouseDn), covers popups and other menus
    for _, element in ipairs(UIMouseHandler or {}) do
        if not element.clickThrough and element:shouldReceiveInput()
            and x > element.pos.x and x < element.pos.x + element.size.w
            and y > element.pos.y and y < element.pos.y + element.size.h then
            return true
        end
    end
    return false
end

-- small centered info lines (window footer)
Widgets.INFO_HEIGHT = 18
local INFO_MAX_SCALE = 0.7 -- adapted text shrinks below this only if the line doesn't fit

---Small centered info text, replaces the element's previous text
---@param element UIElement
---@param text string
function Widgets.infoText(element, text)
    element:addAdaptedText(true, text, nil, nil, FONTS.SMALL, CENTERMID, INFO_MAX_SCALE)
end

MGE.Widgets = Widgets
return Widgets
