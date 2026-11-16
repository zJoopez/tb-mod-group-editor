




local ScrollList = {

    rowHeight = MGE.Widgets and MGE.Widgets.LIST_ROW_H or 20,
    scrollBarWidth = MGE.Widgets and MGE.Widgets.px(18) or 18,

    bgColor = TB_MENU_DEFAULT_DARKER_COLOR,

    selectedColor = MGE.Widgets and MGE.Widgets.SELECTED_COLOR or TB_MENU_DEFAULT_LIGHTER_COLOR,
}




function ScrollList.getRowColor(index)
    return { 0, 0, 0, index % 2 == 0 and 0 or 0.1 }
end














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
        bgColor = TB_MENU_DEFAULT_BG_COLOR,
        hoverColor = MGE.Widgets.HOVER_COLOR,
        pressedColor = TB_MENU_DEFAULT_DARKEST_COLOR,
    }, true)
    btn:addAdaptedText(label, nil, nil, MGE.Widgets.FONT, CENTERMID, MGE.Widgets.TEXT_SCALE, nil, nil)
    btn:addMouseUpHandler(onClick)
    return btn
end








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












function ScrollList.create(parent, rect, items, buildRow, toReload, emptyText, plainRows)
    local rowHeight = ScrollList.rowHeight

    local listMainView = parent:addChild({
        pos = { rect.x, rect.y },
        size = { rect.w, rect.h },
        bgColor = ScrollList.bgColor,
    })





    listMainView.reloadListElements = function(view, holder, elements, reloadElement, enabled, orientation)
        UIElement.reloadListElements(view, holder, elements, reloadElement, enabled, orientation)
        local top = holder.shift.y + holder.size.h
        for _, row in ipairs(enabled) do
            local y = top + ((row.listIndex or 1) - 1) * rowHeight
            if y < -0.5 or y + rowHeight > view.size.h + 0.5 then row:hide(true) end
        end
    end


    local scrollableListHolder = listMainView:addChild({
        pos = { 0, 0 },
        size = { listMainView.size.w - ScrollList.scrollBarWidth, listMainView.size.h },
    })


    toReload = toReload or listMainView:addChild({ pos = { 0, 0 }, size = { 1, 1 } })

    local rows = {}
    if #items == 0 then
        if emptyText then

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
        row.listIndex = i
        buildRow(row, item, i)
        table.insert(rows, row)
    end

    local scrollBar = TBMenu:spawnScrollBar(scrollableListHolder, #rows, rowHeight)
    if #rows * rowHeight > scrollableListHolder.size.h then
        for _, row in ipairs(rows) do
            row:hide(true)
        end
        scrollableListHolder.scrollBar = scrollBar
        scrollBar:makeScrollBar(scrollableListHolder, rows, toReload)
    end

    return listMainView, rows
end

MGE.ScrollList = ScrollList
