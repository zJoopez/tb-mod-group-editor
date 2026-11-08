local obj_selector = {}

local Main = MGE.Main
local ModData = MGE.ModData
local History = MGE.History
local ScrollList = MGE.ScrollList
local Widgets = MGE.Widgets

local function create(view, fullList)

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

    ---Frames the object: same viewing direction, far enough away that it fits on screen
    ---@param obj FileParserEnvObj
    local function lookAt(obj)
        MGE.Camera.focus({ obj })
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
            Main.onSelectionChanged()
        end)
    end, toReload)

    topBar_l:addAdaptedText("Toggle All", topBar_l.size.h + 5, nil, nil, LEFTMID, 0.7, nil, nil, nil)
    TBMenu:spawnToggle2(topBar_l, toggleRect, Main.toggleAll, function(value)
        Main.toggleSelectAll(value)
    end)
    ScrollList.createPager(topBar_r, { x = 0, y = 0, w = topBar_r.size.w, h = topBar_r.size.h }, page, pageCount,
        function(newPage)
            Main.page = newPage
            Main.updateWindow()
        end)

    -- duplicate, import and the Dynamic button free ids on their own when needed,
    -- this moves every static object it can off the dynamic ids at once
    local function reindexNonDynamic()
        local _, moved = ModData.freeDynamicIds(math.huge, { partial = true })
        if moved == 0 then
            print("reindex: nothing to move")
            return
        end
        History.commit()
        MGE.save()
        print("reindex moved " .. moved .. " objects")
    end

    -- Duplicate/Delete act on selected objects, Reindex on all of them. In the list's bar so they're
    -- there on every tab. MGE.Editor loads after this module, so it's looked up on click
    Widgets.barButtons(botBar, {
        { label = "Duplicate", onClick = function() MGE.Editor.duplicate() end },
        { label = "Reindex", onClick = function() reindexNonDynamic() end },
        { label = "Delete", onClick = function() MGE.Editor.deleteSelected() end }, -- asks first
    })
end

obj_selector.create = create

return obj_selector
