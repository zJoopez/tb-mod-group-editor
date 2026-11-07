local obj_selector = {}

POS_SHIFT = POS_SHIFT or { 0 }

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

    local list, page, pageCount = ScrollList.paginate(fullList, Main.page, Main.pageSize)
    Main.page = page -- clamped, e.g. after deleting objects on last page
    local listElementHeight = ScrollList.rowHeight
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

    ---@param obj EnvObject
    local function lookAt(obj)
        set_camera_mode(4)
        local pos = { get_obj_pos(obj.id - 1) }
        set_camera_lookat(pos[1], pos[2], pos[3])
    end

    -- list area between top and bottom bars
    ScrollList.create(view, {
        x = 0,
        y = topBar_l.size.h,
        w = view.size.w,
        h = view.size.h - topBar_l.size.h - botBar.size.h
    }, list, function(listElement, v)
        listElement:addCustomDisplay(false, function()
            listElement:uiText(tostring(v.id), nil, nil, nil, nil, 0.7, nil, nil, nil)
        end)
        -- clicking the row focuses the camera, the toggle on top only changes selection
        listElement:addMouseUpHandler(function()
            lookAt(v)
        end)
        TBMenu:spawnToggle2(listElement, toggleRect, v.selected or false, function(value)
            v.selected = value
        end)
    end, toReload)

    topBar_l:addAdaptedText("Toggle All", topBar_l.size.h + 5, nil, nil, LEFTMID, 0.7, nil, nil, nil)
    TBMenu:spawnToggle2(topBar_l, toggleRect, Main.toggleAll, function(value)
        Main.toggleAll = value
        for _, obj in ipairs(fullList) do
            obj.selected = value
        end
        Main.updateWindow()
    end)
    ScrollList.createPager(topBar_r, { x = 0, y = 0, w = topBar_r.size.w, h = topBar_r.size.h }, page, pageCount,
        function(newPage)
            Main.page = newPage
            Main.updateWindow()
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
end

obj_selector.create = create

return obj_selector
