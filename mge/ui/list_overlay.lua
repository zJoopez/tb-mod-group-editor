-- Popup list over the window: title, optional search + pager, rows, Cancel / confirm buttons.
-- Used by the asset import (ui/assets.lua) and the model picker (ui/model_picker.lua).
-- Rows either pick (click selects, double click confirms) or act (onClick, e.g. open a folder,
-- the list is rebuilt after it)

---@class ListOverlayItem
---@field label string
---@field value any? passed to onConfirm for picking rows
---@field onClick function? acting row: called instead of selecting, the list is rebuilt after

---@class ListOverlayOptions
---@field title string|fun(): string read again on every rebuild (e.g. the current folder)
---@field getItems fun(searchText: string): ListOverlayItem[] called on every rebuild
---@field onConfirm fun(value: any) called with the picked row's value, the overlay is closed first
---@field confirmLabel string?
---@field search boolean? show the search field (searchText is "" without it)
---@field emptyText (string|fun(searchText: string): string)?
---@field selected any? value selected when the overlay opens

local ListOverlay = {}
MGE.ListOverlay = ListOverlay

local ScrollList = MGE.ScrollList

local OVERLAY_W = 420
local OVERLAY_H = 460
local PADDING = 10
local TITLE_H = 44
local BUTTON_H = 40
local PAGE_SIZE = 64
local DOUBLE_CLICK_TIME = 0.35

---Opens the overlay, does nothing while another MGE overlay is open
---@param options ListOverlayOptions
function ListOverlay.open(options)
    if MGE.listOverlay or MGE.saveOverlay then return end
    local selectedValue = options.selected
    local searchText = ""
    local page = 1

    local overlay = TBMenu:spawnWindowOverlay()
    MGE.listOverlay = overlay -- lets MGE.quit close it
    local defaultKillAction = overlay.killAction
    overlay.killAction = function()
        if defaultKillAction then defaultKillAction() end
        -- the search field would otherwise stay in toriui's keyboard list (see Widgets.releaseKeyboard)
        if MGE and MGE.Widgets then MGE.Widgets.releaseKeyboard(overlay) end
        if MGE then MGE.listOverlay = nil end
        enable_camera_movement()
    end
    local function close() overlay:kill() end

    local w = math.min(OVERLAY_W, WIN_W - 20)
    local h = math.min(OVERLAY_H, WIN_H - 20)
    local box = overlay:addChild({
        pos = { (WIN_W - w) / 2, (WIN_H - h) / 2 },
        size = { w, h },
        bgColor = TB_MENU_DEFAULT_BG_COLOR,
        shapeType = ROUNDED,
        rounded = 5,
        interactive = true,
    })
    -- the overlay blocks list scrolling (UIScrollbarIgnore), allow it while the mouse is over the box,
    -- like the game's replay comments. Checked by position: hovering a row takes the box's hover state
    box:addCustomDisplay(function()
        UIScrollbarIgnore = not (MOUSE_X >= box.pos.x and MOUSE_X <= box.pos.x + box.size.w and
            MOUSE_Y >= box.pos.y and MOUSE_Y <= box.pos.y + box.size.h)
    end)

    local barH = ScrollList.rowHeight
    local innerW = w - PADDING * 2
    local listY = TITLE_H + barH
    local listH = h - listY - BUTTON_H - PADDING * 2

    -- redrawn on scroll: covers rows that scroll past the list edges, holds everything around the list
    local toReload = box:addChild({
        pos = { 0, 0 },
        size = { w, h },
    })
    local header = toReload:addChild({
        pos = { 0, 0 },
        size = { w, listY },
        bgColor = TB_MENU_DEFAULT_BG_COLOR,
    })
    local title = header:addChild({
        pos = { PADDING, 0 },
        size = { innerW, TITLE_H },
    })
    ---@param text string
    local function setTitle(text)
        -- rebuilt so long titles (folder paths) are scaled down to fit, like the save overlay's title
        title:kill(true)
        title:addChild({ pos = { 0, 0 }, size = { title.size.w, title.size.h } })
            :addAdaptedText(true, text, nil, nil, FONTS.BIG, nil, 0.6)
    end
    local topBar = header:addChild({
        pos = { PADDING, TITLE_H },
        size = { innerW, barH },
        bgColor = TB_MENU_DEFAULT_DARKER_COLOR,
    })
    local footer = toReload:addChild({
        pos = { 0, listY + listH },
        size = { w, h - listY - listH },
        bgColor = TB_MENU_DEFAULT_BG_COLOR,
    })

    -- search on the left half, pager on the right half (same split as the object list);
    -- without search the pager takes the whole bar
    local searchW = options.search and innerW / 2 or 0
    local searchHolder = topBar:addChild({ pos = { 0, 0 }, size = { math.max(searchW, 1), barH } })
    local pagerHolder = topBar:addChild({ pos = { searchW, 0 }, size = { innerW - searchW, barH } })
    local rowsHolder = box:addChild({
        pos = { PADDING, listY },
        size = { innerW, listH },
    })

    local function confirm()
        if selectedValue == nil then
            TBMenu:showStatusMessage("Select an item from the list")
            return
        end
        close()
        options.onConfirm(selectedValue)
    end

    local rebuild
    ---@type { value: any, time: number }?
    local lastClick = nil -- a double click on a picking row confirms

    rebuild = function()
        local titleOption = options.title
        setTitle(type(titleOption) == "function" and titleOption() or tostring(titleOption))
        local items = options.getItems(searchText)
        local pageItems, clamped, pageCount = ScrollList.paginate(items, page, PAGE_SIZE)
        page = clamped

        -- kill(true) keeps the holders, kill() would leave destroyed elements in the parent's child list
        pagerHolder:kill(true)
        rowsHolder:kill(true)
        ScrollList.createPager(pagerHolder, { x = 0, y = 0, w = pagerHolder.size.w, h = barH }, page, pageCount,
            function(newPage)
                page = newPage
                rebuild()
            end)

        ---@type { row: UIElement, index: integer }?
        local selectedRow = nil
        local emptyText = options.emptyText
        if type(emptyText) == "function" then emptyText = emptyText(searchText) end
        ScrollList.create(rowsHolder, { x = 0, y = 0, w = innerW, h = listH }, pageItems, function(row, item, index)
            ---@cast item ListOverlayItem
            row:addAdaptedText(item.label, 5, nil, nil, LEFTMID, 0.6, nil, nil)
            if item.onClick then
                row:addMouseUpHandler(function()
                    item.onClick()
                    page = 1
                    lastClick = nil
                    rebuild()
                end)
                return
            end
            local function select()
                if selectedRow then
                    selectedRow.row.bgColor = ScrollList.getRowColor(selectedRow.index)
                end
                selectedRow = { row = row, index = index }
                selectedValue = item.value
                row.bgColor = ScrollList.selectedColor
            end
            if item.value == selectedValue then select() end
            row:addMouseUpHandler(function()
                local now = UIElement.clock or os.clock()
                local double = lastClick ~= nil and lastClick.value == item.value and
                    now - lastClick.time <= DOUBLE_CLICK_TIME
                lastClick = { value = item.value, time = now }
                select()
                if double then confirm() end
            end)
        end, toReload, emptyText)
    end

    if options.search then
        local search = TBMenu:spawnTextField2(searchHolder, {
            x = 2, y = 2,
            w = searchHolder.size.w - 4, h = barH - 4
        }, nil, "Search", {
            fontId = 4,
            textScale = 0.65,
            textAlign = LEFTMID,
            keepFocusOnHide = true, -- toReload is hidden/shown on scroll
        })
        search:addInputCallback(function()
            searchText = tostring(search.textfieldstr[1] or "")
            page = 1
            rebuild()
        end)
    end

    local buttonW = (innerW - PADDING) / 2
    for i, info in ipairs({
        { label = TB_MENU_LOCALIZED.BUTTONCANCEL, onClick = close },
        { label = options.confirmLabel or "OK", onClick = confirm },
    }) do
        local btn = footer:addChild({
            pos = { PADDING + (i - 1) * (buttonW + PADDING), PADDING },
            size = { buttonW, BUTTON_H },
            interactive = true,
            bgColor = { 0, 0, 0, 0.1 },
            hoverColor = { 0, 0, 0, 0.3 },
            pressedColor = { 1, 1, 1, 0.2 },
            shapeType = ROUNDED,
            rounded = 4,
        }, true)
        btn:addAdaptedText(false, info.label)
        btn:addMouseHandlers(nil, info.onClick)
    end

    rebuild()
end

return ListOverlay
