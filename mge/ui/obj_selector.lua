local obj_selector = {}

POS_SHIFT = POS_SHIFT or { 0 }

local function slice(arr, start, stop)
    local result = {}
    local maxIndex = math.min(stop or #arr, #arr)
    for i = start, maxIndex do
        table.insert(result, arr[i])
    end
    return result
end

---@param view UIElement
---@param fullList EnvObject[]
local function createButton(parent, pos, size, label, onClick)
    local btn = parent:addChild({
        interactive = true,
        pos = pos,
        size = size,
        bgColor = TB_MENU_DEFAULT_DARKER_COLOR,
        hoverColor = TB_MENU_DEFAULT_LIGHTER_COLOR,
        pressedColor = TB_MENU_DEFAULT_DARKEST_COLOR
    }, true)
    btn:addAdaptedText(label, nil, nil, nil, CENTERMID, 0.7, nil, nil, nil)
    if onClick then
        btn:addMouseUpHandler(onClick)
    end
    return btn
end

local function create(view, fullList)
    POS_SHIFT = POS_SHIFT or { 0 }

    local list = slice(fullList, (Main.page - 1) * Main.pageSize + 1, Main.page * Main.pageSize)
    local listElementHeight = 25
    local toggleRect = { h = listElementHeight - 4, w = listElementHeight - 4, x = 2, y = 2 }

    -- Spawning a parent element for any object that needs to be reloaded every frame
    local toReload = UIElement:new({
        parent = view,
        pos = { 0, 0 },
        size = { view.size.w, view.size.h }
    })

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
            listElement:uiText(tostring(v.id), nil, nil, nil, nil, 0.7, nil, nil, nil)
        end)
        TBMenu:spawnToggle2(listElement, toggleRect, v.selected or false, function(value)
            v.selected = value
            if value then highlight(v) end
        end)
        table.insert(listElements, listElement)
    end

    topBar_l:addAdaptedText("Toggle All", topBar_l.size.h + 5, nil, nil, LEFTMID, 0.7, nil, nil, nil)
    TBMenu:spawnToggle2(topBar_l, toggleRect, Main.toggleAll, function(value)
        Main.toggleAll = value
        for _, obj in ipairs(fullList) do
            obj.selected = value
        end
        Main.updateWindow()
    end)
    local pageBtnNext = createButton(topBar_r, { -topBar_r.size.h, 2 }, { topBar_r.size.h - 4, topBar_r.size.h - 4 }, ">",
        function()
            if Main.page * Main.pageSize < #fullList then
                Main.page = Main.page + 1
                Main.updateWindow()
            end
        end)

    local txtPage = topBar_r:addChild({
        pos = { -topBar_r.size.h - topBar_r.size.h * 3 - 2, 3 },
        size = { topBar_r.size.h * 3, topBar_r.size.h }
    })
    txtPage:addAdaptedText(Main.pageStr or "Page 1/1", nil, nil, nil, CENTER, 0.7, nil, nil)

    local pageBtnPrev = createButton(topBar_r, { topBar_r.size.w - topBar_r.size.h * 5, 2 },
        { topBar_r.size.h - 4, topBar_r.size.h - 4 }, "<", function()
        if Main.page > 1 then
            Main.page = Main.page - 1
            Main.updateWindow()
        end
    end)

    local function reindexNonDynamic()
        local taberu = ModData.parsed.env_obj
        local freeStatic = ModData.freeIds.static
        local freeNonStatic = ModData.freeIds.nonStatic
        local jointIds = ModData.jointIds

        for i = #taberu, 1, -1 do
            local obj = taberu[i]
            if obj.id < MAX_NONSTATIC_OBJECTS and obj.props.flag ~= "0" and not jointIds[obj.id] then
                local newId = table.remove(freeStatic, 1)
                if not newId then break end
                table.insert(freeNonStatic, obj.id)
                obj.id = newId
            end
        end
        table.sort(taberu, function(a, b)
            return a.id < b.id
        end)
        MGE.save()
        print("reindex done")
    end

    local reindexBtn = createButton(botBar, { 0, 2 }, { view.size.w / 2 - 2, listElementHeight - 4 }, "reindex",
        function()
            reindexNonDynamic()
        end)

    local resetUIBtn = createButton(botBar, { view.size.w - view.size.w / 2 + 2, 2 },
        { view.size.w / 2 - 2, listElementHeight - 4 }, "reset inputs", function()
        Main.resetEditor()
    end)

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
