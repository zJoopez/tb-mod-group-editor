-- Shared button helpers so every button looks the same and rows line up with the window edges

---@class Widgets
local Widgets = {}

---@class WidgetRect
---@field x number
---@field y number
---@field w number
---@field h number

-- MGE's overall size: every size and text size of the window is multiplied by it (Widgets.px), on top of
-- the game's GUI scale. The layout's proportions stay the same. 1 was small at the lowest GUI scale.
-- Settings > UI size picks it (MGE_UI_SCALE, a global: kept over the restart that applies it)
Widgets.UI_SCALE = tonumber(MGE_UI_SCALE) or 1.3
Widgets.UI_SCALES = { 1, 1.15, 1.3, 1.5, 1.75 } -- the choices Settings offers

---A size in MGE's layout units as pixels at UI_SCALE, whole pixels
---@param n number
---@return number
function Widgets.px(n)
    return math.floor(n * Widgets.UI_SCALE + 0.5)
end

-- the font of every button and label: the plain one the number fields use (FONTS.LMEDIUM) reads better small
-- than the game's default bold comic font (FONTS.MEDIUM, what MGE used before)
Widgets.FONT = FONTS.LMEDIUM

-- one text size for every button and label (tabs, bars, editor rows, list cells), adapted text only shrinks
-- it to fit. TEXT_SCALE_SMALL for secondary text: input fields, hints, a row's second column
Widgets.TEXT_SCALE = 0.5 * Widgets.UI_SCALE
Widgets.TEXT_SCALE_SMALL = 0.45 * Widgets.UI_SCALE
Widgets.TAB_TEXT_SCALE = 0.42 * Widgets.UI_SCALE -- tabs (list tabs, Mods / Rules, editor tabs)
Widgets.BUTTON_TEXT_SCALE = 0.45 * Widgets.UI_SCALE -- buttons' text (Widgets.button's default), a bit under the labels'
Widgets.TITLE_SCALE = 0.7 * Widgets.UI_SCALE -- the overlays' titles (Settings, Convert Map, the file picker...)
-- height of an editor row (label, inputs or buttons, "?"), the editor tabs and the reset button
Widgets.ROW_H = Widgets.px(24)
-- space between the cells of a grid-like row: the number fields' (they sit this far apart), the object grid's
-- cells, the button rows (Box / Sphere / Pill, the list's buttons, Create / Reset), the editor tabs
Widgets.GAP = 2
-- what a cell keeps free on each side of its row / column: half the gap. The number fields sit this far in
-- (TBMenu:spawnTextField2's shift 1), buttons in the editor rows do the same so they line up with them
Widgets.INSET = Widgets.GAP / 2

---A color between two others (t = 0: a, 1: b), opaque
---@param a number[]
---@param b number[]
---@param t number
---@return number[]
function Widgets.mix(a, b, t)
    return { a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t, 1 }
end

-- Highlight colors, between the window color and the game's lighter ones (those were far brighter than the
-- rest of the scheme). Mixed from the game's menu colors, so they follow its theme
Widgets.HOVER_COLOR = Widgets.mix(TB_MENU_DEFAULT_BG_COLOR, TB_MENU_DEFAULT_LIGHTER_COLOR, 0.4)
-- a selected cell in the object / joint grid, a selected list row: lighter, still with white text
Widgets.SELECTED_COLOR = Widgets.mix(TB_MENU_DEFAULT_BG_COLOR, TB_MENU_DEFAULT_LIGHTEST_COLOR, 0.5)
-- a toggle that's on (Box, Shown, a row label's mode), the current gizmo tool, a lit Select all: the same as a
-- selected cell, so everything chosen reads the same (a darker one was hard to tell from the buttons)
Widgets.ACTIVE_COLOR = Widgets.SELECTED_COLOR

---The menu's darkest color at a share of its brightness
---@param share number
---@return number[]
local function darkest(share)
    local c = TB_MENU_DEFAULT_DARKEST_COLOR
    return { c[1] * share, c[2] * share, c[3] * share, 1 }
end
-- the top bar and the overlays' bars: well darker than the panel (0.6 read nearly black next to it)
Widgets.BAR_COLOR = darkest(0.8)
-- the content areas: the lists, the editor panel and its active tab, the overlays. Darker than the panel
-- around them, lighter than the bar
Widgets.CONTENT_BG = darkest(0.9)

---@class WidgetStyle
---@field bg number[]
---@field hover number[]
---@field pressed number[]

---MGE's button colors, everywhere: the window's red, standing out on the dark content areas, the overlays
---and the bars. (It was the darker red, made for the red window background)
---@type WidgetStyle
Widgets.STYLE = {
    bg = TB_MENU_DEFAULT_BG_COLOR,
    hover = Widgets.HOVER_COLOR,
    pressed = TB_MENU_DEFAULT_DARKEST_COLOR, -- every MGE button presses to the darkest color
}
---The same style, the name the editor panels use
Widgets.PANEL_STYLE = Widgets.STYLE

---Tab panel color (ui/main.lua): darkens the window, the active tab uses it too so it touches the panel
Widgets.TAB_PANEL_COLOR = { 0, 0, 0, 0.15 }
---The tab panel color as a solid color: the window color under it, darkened the same. For parts that
---have to cover what's behind them, like list bars over rows that scroll past the list edges
Widgets.TAB_PANEL_SOLID = {
    TB_MENU_DEFAULT_BG_COLOR[1] * (1 - Widgets.TAB_PANEL_COLOR[4]),
    TB_MENU_DEFAULT_BG_COLOR[2] * (1 - Widgets.TAB_PANEL_COLOR[4]),
    TB_MENU_DEFAULT_BG_COLOR[3] * (1 - Widgets.TAB_PANEL_COLOR[4]),
    1,
}

---Standard MGE button
---@param parent UIElement
---@param rect WidgetRect position relative to parent
---@param label string|fun(): string function labels are re-read every frame
---@param onClick function?
---@param textScale number? defaults to Widgets.BUTTON_TEXT_SCALE
---@param style WidgetStyle? defaults to Widgets.STYLE
---@return UIElement
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
    elseif label ~= "" then -- "" for icon buttons
        btn:addAdaptedText(label, nil, nil, Widgets.FONT, CENTERMID, textScale, nil, nil)
    end
    if onClick then btn:addMouseUpHandler(onClick) end
    return btn
end

---Standard MGE button showing an image instead of text, the image is a square centered in the button
---@param parent UIElement
---@param rect WidgetRect position relative to parent
---@param image string texture path, "../textures/..." for game textures or relative to data/script
---@param onClick function?
---@param style WidgetStyle?
---@return UIElement
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

-- Changing the game's graphics settings reloads its graphics (reload_graphics, the resolution_changed
-- hook): the texture ids loaded before don't show the right images any more, icons came out garbled.
-- Elements built after it were fine (a tab change), so every image element MGE makes is kept here with
-- its path and loads its image again then, like a rebuilt one. Weak keys: killed elements drop out
---@type table<UIElement, string>
local trackedImages = setmetatable({}, { __mode = "k" })

---Keeps an element showing an image so it loads it again after the game reloads its graphics
---@param element UIElement made with bgImage = image
---@param image string the same path
---@return UIElement element
function Widgets.trackImage(element, image)
    trackedImages[element] = image
    return element
end

---Loads every tracked image again (after reload_graphics). The old ids aren't unloaded: after the
---reload they're not the images they were
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

---@type fun()[] called after a graphics reload, window size or GUI scale change, after the images reload
---(ui/main.lua: Main.fitScreen)
Widgets.onScreenChanged = {}

add_hook("resolution_changed", MGE.hookname, function()
    Widgets.reloadImages()
    for _, callback in ipairs(Widgets.onScreenChanged) do pcall(callback) end
end)

---@class WidgetRowButton
---@field label string|fun(): string text, for icon buttons the name shown when hovering (string labels)
---@field icon string? image shown instead of the label
---@field wide boolean? icon buttons are square unless wide, wide ones share the width like text buttons
---@field onClick function?
---@field popupLeft boolean? the hover name goes under the button, its right edge at the button's (Widgets.popupBelowLeft)

---Puts a hover popup (TBMenu:displayPopup's) under its element, right edges lined up, so it opens to the
---left: for buttons near the screen's right edge (the top bar). The game's own placement moves a popup
---that would leave the screen before it shrinks to its text: its text and background ended up apart
---@param element UIElement
---@param popup UIElement what TBMenu:displayPopup returned
function Widgets.popupBelowLeft(element, popup)
    popup:moveTo(-popup.size.w, element.size.h + 4) -- negative x: from the element's right edge
end

---Esc in an overlay's text field closes the overlay (MGE.closeTopOverlay). A focused field takes every
---key first, MGE's key hook may not see the Esc then. Keeps the field's other key handlers
---@param field UIElement text field inside an MGE overlay
function Widgets.closeOnEscape(field)
    field:addKeyboardHandlers(function(key)
        if key == 27 and MGE and MGE.closeTopOverlay then MGE.closeTopOverlay() end
    end)
end

---Runs func every frame before the element draws, after anything already set to run there. An
---element has one such slot (addCustomDisplay with drawBefore) and the hover popups of icon buttons
---(TBMenu:displayPopup) use it, setting it directly would replace them
---@param element UIElement
---@param func fun()
function Widgets.addDrawBefore(element, func)
    local previous = element.customDisplayBefore
    element:addCustomDisplay(false, function(...)
        if previous then previous(...) end
        func()
    end, true)
end

---Buttons filling the parent's width exactly: n buttons and n - 1 gaps between them.
---Entries with `icon` show that image instead of the label and are square (h wide) unless `wide`,
---the other buttons share the rest of the width equally. Icon buttons show their label on hover
---@param parent UIElement
---@param y number
---@param h number
---@param buttons WidgetRowButton[]
---@param gap number space between buttons
---@param textScale number?
---@param style WidgetStyle?
---@return UIElement[]
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
                local popup = TBMenu:displayPopup(created[i], label) -- name of the icon on hover
                if info.popupLeft and popup then Widgets.popupBelowLeft(created[i], popup) end
            end
        else
            created[i] = Widgets.button(parent, rect, info.label, info.onClick, textScale, style)
        end
        x = x + w + gap
    end
    return created
end

-- buttons inside list bars (object list, asset list): 2px top/bottom padding
local BAR_PADDING = 2
local BAR_GAP = 4

---Buttons filling a list bar with the shared bar padding (e.g. duplicate/delete, import)
---@param bar UIElement
---@param buttons WidgetRowButton[]
---@param style WidgetStyle?
---@return UIElement[]
function Widgets.barButtons(bar, buttons, style)
    return Widgets.buttonRow(bar, BAR_PADDING, bar.size.h - BAR_PADDING * 2, buttons, BAR_GAP, nil, style)
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
---@param style WidgetStyle? bg color from the style, defaults to Widgets.STYLE
---@return UIElement
function Widgets.helpIcon(parent, x, y, size, message, mark, style)
    style = style or Widgets.STYLE
    local icon = parent:addChild({
        pos = { x, y },
        size = { size, size },
        bgColor = style.bg,
        hoverColor = style.hover, -- like every other button (it used to turn darker on hover)
        pressedColor = style.pressed,
        interactive = true,
        shapeType = ROUNDED,
        rounded = size,
    })
    icon:addChild({}):addAdaptedText(true, mark or "?", nil, nil, Widgets.FONT, nil, Widgets.TEXT_SCALE)
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
Widgets.INFO_HEIGHT = Widgets.px(18)
local INFO_MAX_SCALE = 0.7 * Widgets.UI_SCALE -- adapted text shrinks below this only if the line doesn't fit

---Small info text, centered unless align says otherwise, replaces the element's previous text
---@param element UIElement
---@param text string
---@param align UIElementTextAlign? default CENTERMID
function Widgets.infoText(element, text, align)
    element:addAdaptedText(true, text, nil, nil, FONTS.SMALL, align or CENTERMID, INFO_MAX_SCALE)
end

MGE.Widgets = Widgets
return Widgets
