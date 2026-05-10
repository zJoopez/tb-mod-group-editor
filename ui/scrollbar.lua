local scrollbar = {}
require("toriui.uielement")

POS_SHIFT = POS_SHIFT or { 0 }

local function slice(arr, start, stop)
  start = start or 1
  stop = stop or #arr
  local result = {}
  for i = start, stop do
    result[#result + 1] = arr[i]
  end
  return result
end


---@param view UIElement
---@param list EnvObject[]
function scrollbar.create(view, fullList, toggleAll)
    -- Creating a global posShift table - this will store the last scrollbar position between script runs within one game session
    POS_SHIFT = POS_SHIFT or { 0 }
    local list = slice(fullList, Main.page * 69 - 68, Main.page * 69)

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
        size = { listMainView.size.w - 25, listMainView.size.h }
    })

    -- Calculating scrollbar scale
    -- When dealing with dynamically generated tables, you may need to run additional checks.
    local scrollScale = (listMainView.size.h) / (#list * listElementHeight)

    -- Creating the scroll bar
    -- First creating a holder object, then attaching a scrollbar object to it.
    local listScrollView = UIElement:new({
        parent = listMainView,
        pos = { -25, 0 },
        size = { 25, listMainView.size.h }
    })
    local listScrollBar = UIElement:new({
        parent = listScrollView,
        pos = { 0, 0 },
        size = { listScrollView.size.w, listScrollView.size.h * scrollScale },
        interactive = true,
        bgColor = { 0, 0, 0, 0.3 },
        hoverColor = { 0, 0, 0, 0.5 },
        pressedColor = { 0, 0, 0, 0.2 },
        scrollEnabled = true
    })

    ---@param thing EnvObject
    local function highlight(thing)
        local pos = thing.pos
        set_camera_mode(4)
        set_camera_lookat(pos.x, pos.y, pos.z)
    end

    -- Populating the scrollable list with objects
    -- First, creating a table to store all list elements, then spawning them one-by-one and adding to the table
    local toggles = {}
    local listElements = {}
    for i, v in pairs(list) do
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
        table.insert(toggles, TBMenu:spawnToggle2(listElement, toggleRect, v.selected or false, function(value)
            MGE.modData.objects[v.id].selected = value
            highlight(v)
        end))

        -- Hiding every object, ones that need to be made visible will be activated upon running makeScrollBar(...)
        listElement:hide()
        table.insert(listElements, listElement)
    end

    topBar_l:addAdaptedText("Toggle All", topBar_l.size.h + 5, nil, nil, LEFTMID, 0.7, nil, nil, nil)
    TBMenu:spawnToggle2(topBar_l, toggleRect, toggleAll, function(value)
        for i, item in pairs(fullList) do
            MGE.modData.objects[item.id].selected = value
            Main.updateScroll(not toggleAll)
        end
    end)
    topBar_r:addAdaptedText(Main.pageStr, topBar_r.size.h + 5, nil, nil, RIGHTMID, 0.7, nil, nil, nil)


    -- Calling makeScrollBar() method to make scrollable list
    listScrollBar:makeScrollBar(scrollableListHolder, listElements, toReload, POS_SHIFT, 0.4)
end

return scrollbar
