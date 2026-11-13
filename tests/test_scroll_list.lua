-- ui/scroll_list.lua: paging (the object list and the Link tab's grid)
local T = ...
local ScrollList = MGE.ScrollList

local function range(n)
    local list = {}
    for i = 1, n do list[i] = i end
    return list
end

T.test("paginate", function()
    local items, page, count = ScrollList.paginate(range(10), 1, 4)
    T.eq(count, 3, "page count")
    T.eq(page, 1, "page")
    T.eq(#items, 4, "full page")
    T.eq(items[1], 1, "first item")

    items, page = ScrollList.paginate(range(10), 3, 4)
    T.eq(#items, 2, "last page is partial")
    T.eq(items[1], 9, "last page starts after the others")

    items, page = ScrollList.paginate(range(10), 9, 4)
    T.eq(page, 3, "too high a page is clamped (a mod with fewer objects)")
    T.eq(items[1], 9, "items of the clamped page")

    _, page = ScrollList.paginate(range(10), 0, 4)
    T.eq(page, 1, "too low a page is clamped")

    items, page, count = ScrollList.paginate({}, 2, 4)
    T.eq(count, 1, "an empty list still has one page")
    T.eq(page, 1, "on it")
    T.eq(#items, 0, "with nothing")

    -- the Link grid's case: 57 objects don't fit its 7 rows of 8, with the pager row 6 rows of 8 a page
    items, _, count = ScrollList.paginate(range(57), 2, 48)
    T.eq(count, 2, "57 objects: 2 grid pages")
    T.eq(#items, 9, "the rest on the second")
end)
