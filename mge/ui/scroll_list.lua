-- Shared scrollable list so object selector and asset list look and behave the same

---@class ScrollList
---@field rowHeight number
---@field scrollBarWidth number
ScrollList = {
    rowHeight = 25,
    scrollBarWidth = 18,
    selectedColor = TB_MENU_DEFAULT_LIGHTER_COLOR,
}

---Default striped background for a row, use to restore a row after it was highlighted
---@param index integer
---@return number[]
function ScrollList.getRowColor(index)
    return { 0, 0, 0, index % 2 == 0 and 0 or 0.1 }
end

---@class ScrollListRect
---@field x number
---@field y number
---@field w number
---@field h number

---Returns items on the given page, page is clamped to a valid range
---@param items any[]
---@param page integer 1-based
---@param pageSize integer
---@return any[] pageItems
---@return integer page clamped page
---@return integer pageCount
function ScrollList.paginate(items, page, pageSize)
    local pageCount = math.max(math.ceil(#items / pageSize), 1)
    page = math.max(math.min(page, pageCount), 1)
    local first = (page - 1) * pageSize + 1
    local pageItems = {}
    for i = first, math.min(first + pageSize - 1, #items) do
        table.insert(pageItems, items[i])
    end
    return pageItems, page, pageCount
end

local function createPagerButton(parent, x, size, label, enabled, onClick)
    local btn = parent:addChild({
        pos = { x, 2 },
        size = { size, size },
        interactive = enabled,
        bgColor = TB_MENU_DEFAULT_DARKER_COLOR,
        hoverColor = TB_MENU_DEFAULT_LIGHTER_COLOR,
        pressedColor = TB_MENU_DEFAULT_DARKEST_COLOR,
    }, true)
    btn:addAdaptedText(label, nil, nil, nil, CENTERMID, 0.7, nil, nil)
    btn:addMouseUpHandler(onClick)
    return btn
end

---Creates "< Page x/y >" controls filling rect, buttons are disabled at first/last page
---@param parent UIElement
---@param rect ScrollListRect
---@param page integer
---@param pageCount integer
---@param onPageChange fun(newPage: integer) caller stores the page and rebuilds its list
---@return UIElement pager
function ScrollList.createPager(parent, rect, page, pageCount, onPageChange)
    local pager = parent:addChild({
        pos = { rect.x, rect.y },
        size = { rect.w, rect.h },
    })
    local btnSize = rect.h - 4

    createPagerButton(pager, 2, btnSize, "<", page > 1, function()
        if page > 1 then onPageChange(page - 1) end
    end)

    local label = pager:addChild({
        pos = { btnSize + 4, 0 },
        size = { rect.w - (btnSize + 4) * 2, rect.h },
    })
    label:addAdaptedText("Page " .. page .. "/" .. pageCount, nil, nil, nil, CENTERMID, 0.7, nil, nil)

    createPagerButton(pager, -btnSize - 2, btnSize, ">", page < pageCount, function()
        if page < pageCount then onPageChange(page + 1) end
    end)

    return pager
end

---Creates a scrollable list area with striped rows and a scrollbar when content overflows
---@param parent UIElement element the list area is added to
---@param rect ScrollListRect list area inside parent
---@param items any[] items to create rows for
---@param buildRow fun(row: UIElement, item: any, index: integer) fills a row, row is already interactive
---@param toReload UIElement element redrawn on scroll, should hold bars that cover overflowing rows (create it before calling this)
---@param emptyText string? shown when items is empty
---@return UIElement listMainView
---@return UIElement[] rows
function ScrollList.create(parent, rect, items, buildRow, toReload, emptyText)
    local rowHeight = ScrollList.rowHeight

    local listMainView = parent:addChild({
        pos = { rect.x, rect.y },
        size = { rect.w, rect.h },
        bgColor = TB_MENU_DEFAULT_DARKER_COLOR,
    })

    -- narrower than parent, spawnScrollBar uses the leftover width for the scrollbar
    local scrollableListHolder = listMainView:addChild({
        pos = { 0, 0 },
        size = { listMainView.size.w - ScrollList.scrollBarWidth, listMainView.size.h },
    })

    local rows = {}
    if #items == 0 then
        if emptyText then
            local empty = scrollableListHolder:addChild({
                pos = { 5, 0 },
                size = { scrollableListHolder.size.w - 5, rowHeight },
            })
            empty:addAdaptedText(emptyText, nil, nil, nil, LEFTMID, 0.65, nil, nil)
        end
        return listMainView, rows
    end

    for i, item in ipairs(items) do
        local row = scrollableListHolder:addChild({
            pos = { 0, (i - 1) * rowHeight },
            size = { scrollableListHolder.size.w, rowHeight },
            interactive = true,
            bgColor = ScrollList.getRowColor(i),
            hoverColor = { 0, 0, 0, 0.3 },
            pressedColor = { 0, 0, 0, 0.4 },
        })
        buildRow(row, item, i)
        table.insert(rows, row)
    end

    local scrollBar = TBMenu:spawnScrollBar(scrollableListHolder, #rows, rowHeight)
    if #rows * rowHeight > scrollableListHolder.size.h then
        for _, row in ipairs(rows) do
            row:hide()
        end
        scrollableListHolder.scrollBar = scrollBar
        scrollBar:makeScrollBar(scrollableListHolder, rows, toReload)
    end

    return listMainView, rows
end
