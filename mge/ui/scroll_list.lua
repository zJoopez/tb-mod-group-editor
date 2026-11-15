-- Shared scrollable list so object selector and asset list look and behave the same

---@class ScrollList
---@field rowHeight number
---@field scrollBarWidth number
local ScrollList = {
    -- MGE's overall size (Widgets.px); the offline tests load this without ui/widgets.lua
    rowHeight = MGE.Widgets and MGE.Widgets.LIST_ROW_H or 20,
    scrollBarWidth = MGE.Widgets and MGE.Widgets.px(18) or 18,
    ---@type number[] behind the rows (ui/main.lua sets a darker one)
    bgColor = TB_MENU_DEFAULT_DARKER_COLOR,
    -- a selected row (the Players list); the offline tests load this without ui/widgets.lua
    selectedColor = MGE.Widgets and MGE.Widgets.SELECTED_COLOR or TB_MENU_DEFAULT_LIGHTER_COLOR,
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
        bgColor = TB_MENU_DEFAULT_BG_COLOR, -- like the grid's cells and the editor's buttons
        hoverColor = MGE.Widgets.HOVER_COLOR,
        pressedColor = TB_MENU_DEFAULT_DARKEST_COLOR,
    }, true)
    btn:addAdaptedText(label, nil, nil, MGE.Widgets.FONT, CENTERMID, MGE.Widgets.TEXT_SCALE, nil, nil)
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
    label:addAdaptedText("Page " .. page .. "/" .. pageCount, nil, nil, MGE.Widgets.FONT, CENTERMID, MGE.Widgets.TEXT_SCALE, nil, nil)

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
---@param toReload UIElement? element redrawn on scroll (drawn over the rows), default an empty one
---@param emptyText string? shown when items is empty
---@param plainRows boolean? rows without stripes, hover or clicks of their own (the grid: its cells are
---the buttons, a row lighting up under them read like something to click)
---@return UIElement listMainView
---@return UIElement[] rows
function ScrollList.create(parent, rect, items, buildRow, toReload, emptyText, plainRows)
    local rowHeight = ScrollList.rowHeight

    local listMainView = parent:addChild({
        pos = { rect.x, rect.y },
        size = { rect.w, rect.h },
        bgColor = ScrollList.bgColor,
    })
    -- toriui shows every row that reaches into the list while scrolling, a row half out of it is drawn
    -- past its edge (there's no clipping): lists had bars above and under them to cover those. Rows not
    -- wholly inside are hidden instead, so a list needs no bars. The mouse wheel scrolls whole rows; a
    -- dragged scrollbar can leave a gap of less than a row at an edge. toriui calls this on the list's
    -- view (the holder's parent) for every scroll, the bar's and the wheel's
    listMainView.reloadListElements = function(view, holder, elements, reloadElement, enabled, orientation)
        UIElement.reloadListElements(view, holder, elements, reloadElement, enabled, orientation)
        local top = holder.shift.y + holder.size.h -- the first row's top, from the list's top
        for _, row in ipairs(enabled) do
            local y = top + ((row.listIndex or 1) - 1) * rowHeight
            if y < -0.5 or y + rowHeight > view.size.h + 0.5 then row:hide(true) end
        end
    end

    -- narrower than parent, spawnScrollBar uses the leftover width for the scrollbar
    local scrollableListHolder = listMainView:addChild({
        pos = { 0, 0 },
        size = { listMainView.size.w - ScrollList.scrollBarWidth, listMainView.size.h },
    })
    -- toriui redraws it on every scroll (hide + show): not the list itself, its show would bring back
    -- every row. An empty element after the rows does when there's nothing to draw over them
    toReload = toReload or listMainView:addChild({ pos = { 0, 0 }, size = { 1, 1 } })

    local rows = {}
    if #items == 0 then
        if emptyText then
            -- centered in the whole list, like the Misc list's note
            local empty = listMainView:addChild({
                pos = { 5, 0 },
                size = { listMainView.size.w - 10, listMainView.size.h },
            })
            empty:addAdaptedText(emptyText, nil, nil, MGE.Widgets.FONT, CENTERMID, MGE.Widgets.TEXT_SCALE_SMALL, nil, nil)
        end
        return listMainView, rows
    end

    for i, item in ipairs(items) do
        local row = scrollableListHolder:addChild({
            pos = { 0, (i - 1) * rowHeight },
            size = { scrollableListHolder.size.w, rowHeight },
            interactive = not plainRows,
            bgColor = plainRows and { 0, 0, 0, 0 } or ScrollList.getRowColor(i),
            hoverColor = not plainRows and { 0, 0, 0, 0.3 } or nil,
            pressedColor = not plainRows and { 0, 0, 0, 0.4 } or nil,
        })
        row.listIndex = i -- for hiding rows partly out of view (reloadListElements above)
        buildRow(row, item, i)
        table.insert(rows, row)
    end

    local scrollBar = TBMenu:spawnScrollBar(scrollableListHolder, #rows, rowHeight)
    if #rows * rowHeight > scrollableListHolder.size.h then
        for _, row in ipairs(rows) do
            row:hide(true) -- stays hidden when the list is shown again (F1), toriui shows the ones in view
        end
        scrollableListHolder.scrollBar = scrollBar
        scrollBar:makeScrollBar(scrollableListHolder, rows, toReload)
    end

    return listMainView, rows
end

MGE.ScrollList = ScrollList
