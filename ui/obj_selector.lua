local obj_selector = {}
require("toriui.uielement")

POS_SHIFT = POS_SHIFT or { 0 }

local function slice(arr, start, stop)
    local result = {}
    for i = start, stop do
        table.insert(result, arr[i])
    end
    return result
end

---@param view UIElement
---@param fullList EnvObject[]
---@param toggleAll boolean
local function create(view, fullList, toggleAll)
    -- Creating a global posShift table - this will store the last scrollbar position between script runs within one game session
    POS_SHIFT = POS_SHIFT or { 0 }
    ---@type EnvObject[]
    local list = slice(fullList, (Main.page - 1) * Main.pageSize + 1, Main.page * Main.pageSize)

    -- Spawning a parent element for any object that needs to be reloaded every frame
    local toReload = UIElement:new({
        parent = view,
        pos = { 0, 0 },
        size = { view.size.w, view.size.h }
    })

    -- Adding toReload children objects which will overlay scrollable list elements on top and bottom.
    -- In case any of the scrollable list elements are interactive, these should be interactive aswell to prevent accidental clicking.
    -- Bars' height should be at least same as scrollable list's elements' height.
    local listElementHeight = 25
    local toggleRect = { h = listElementHeight - 4, w = listElementHeight - 4, x = 2, y = 2 }

    local topBar_l = UIElement:new({
        parent = toReload,
        pos = { 0, 0 },
        size = { view.size.w / 2, listElementHeight },
        bgColor = TB_MENU_DEFAULT_BG_COLOR,
        interactive = true
    })

    local topBar_r = UIElement:new({
        parent = toReload,
        pos = { view.size.w / 2, 0 },
        size = { view.size.w / 2, listElementHeight },
        bgColor = TB_MENU_DEFAULT_BG_COLOR,
        interactive = true
    })

    local botBar = UIElement:new({
        parent = toReload,
        pos = { 0, -listElementHeight },
        size = { view.size.w, listElementHeight },
        bgColor = TB_MENU_DEFAULT_BG_COLOR,
        interactive = true
    })

    -- Spawning main view for the scrollable list.
    -- Height should be equal to parent element's height minus the sum of bars' height.
    local listMainView = UIElement:new({
        parent = view,
        pos = { 0, topBar_l.size.h },
        size = { view.size.w, view.size.h - topBar_l.size.h - botBar.size.h }
    })

    -- Spawning scrollable list holder element.
    -- Can have same size as its' parent, in this example width is smaller to leave place for a scrollbar.
    local scrollableListHolder = UIElement:new({
        parent = listMainView,
        pos = { 0, 0 },
        size = { listMainView.size.w - listElementHeight, listMainView.size.h }
    })

    ---@param obj EnvObject
    local function highlight(obj)
        set_camera_mode(4)
        local pos = { get_obj_pos(obj.id - 1) }
        set_camera_lookat(pos[1], pos[2], pos[3])
    end

    -- Populating the scrollable list with objects
    -- First, creating a table to store all list elements, then spawning them one-by-one and adding to the table
    local listElements = {}
    for i, v in ipairs(list) do
        local listElement = UIElement:new({
            parent = scrollableListHolder,
            pos = { 0, (i - 1) * listElementHeight },
            size = { scrollableListHolder.size.w, listElementHeight },
            interactive = true,
            bgColor = { 0, 0, 0, i % 2 == 0 and 0 or 0.1 },
            hoverColor = { 0, 0, 0, 0.3 },
            pressedColor = { 0, 0, 0, 0.4 },
        })
        listElement:addCustomDisplay(false, function()
            listElement:uiText(v.id, nil, nil, nil, nil, 0.7, nil, nil, nil)
        end)
        TBMenu:spawnToggle2(listElement, toggleRect, v.selected or false, function(value)
            v.selected = value
            if value then highlight(v) end
        end)
        table.insert(listElements, listElement)
    end

    topBar_l:addAdaptedText("Toggle All", topBar_l.size.h + 5, nil, nil, LEFTMID, 0.7, nil, nil, nil)
    TBMenu:spawnToggle2(topBar_l, toggleRect, toggleAll, function(value)
        for _, obj in ipairs(fullList) do
            obj.selected = value
        end
        Main.updateWindow(value)
    end)
    local pageBtnNext = topBar_r:addChild({
        interactive = true,
        pos = { -topBar_r.size.h, 2 },
        size = { topBar_r.size.h - 4, topBar_r.size.h - 4 },
        bgColor = TB_MENU_DEFAULT_DARKER_COLOR,
        hoverColor = TB_MENU_DEFAULT_BG_COLOR,
        pressedColor = TB_MENU_DEFAULT_DARKEST_COLOR
    })
    pageBtnNext:addAdaptedText(">", nil, nil, nil, CENTER, 0.7, nil, nil, nil)
    local txtPage = topBar_r:addChild({
        pos = { -topBar_r.size.h - topBar_r.size.h * 3 - 2, 3 },
        size = { topBar_r.size.h * 3, topBar_r.size.h }
    })
    pageBtnNext:addMouseUpHandler(function()
        if Main.page * Main.pageSize < #fullList then
            Main.page = Main.page + 1
            Main.updateWindow(toggleAll)
        end
    end)
    txtPage:addAdaptedText(Main.pageStr, nil, nil, nil, CENTER, 0.7, nil, nil)
    local pageBtnPrev = topBar_r:addChild({
        interactive = true,
        pos = { topBar_r.size.w - topBar_r.size.h * 5, 2 },
        size = { topBar_r.size.h - 4, topBar_r.size.h - 4 },
        bgColor = TB_MENU_DEFAULT_DARKER_COLOR,
        hoverColor = TB_MENU_DEFAULT_BG_COLOR,
        pressedColor = TB_MENU_DEFAULT_DARKEST_COLOR
    })
    pageBtnPrev:addAdaptedText("<", nil, nil, nil, CENTER, 0.7, nil, nil, nil)
    pageBtnPrev:addMouseUpHandler(function()
        if Main.page > 1 then
            Main.page = Main.page - 1
            Main.updateWindow(toggleAll)
        end
    end)

    --Creatig scrollbar
    local scrollBar = TBMenu:spawnScrollBar(scrollableListHolder, #listElements, listElementHeight)
    if (#listElements * listElementHeight > scrollableListHolder.size.h) then
        for _, v in pairs(listElements) do
            v:hide()
        end
        scrollableListHolder.scrollBar = scrollBar
        scrollBar:makeScrollBar(scrollableListHolder, listElements, toReload)
    end
end

obj_selector.create = create

return obj_selector
