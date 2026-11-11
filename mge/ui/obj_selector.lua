local obj_selector = {}
MGE.ObjSelector = obj_selector -- its grid is also the joint list's (ui/joint_list.lua)

local Main = MGE.Main
local ModData = MGE.ModData
local ScrollList = MGE.ScrollList
local Widgets = MGE.Widgets

local GRID_COLUMNS = 6
local GRID_GAP = 3

-- cell colors: selected cells are pale with dark text so the state reads at a glance
local CELL_TEXT = { 1, 1, 1, 1 }
local CELL_SELECTED_TEXT = { 0.35, 0.05, 0.05, 1 }
local CELL_DIMMED_TEXT = { 1, 1, 1, 0.35 } -- e.g. an empty joint slot
local CELL_DIMMED_BG = { 0, 0, 0, 0.15 }

---@param cell UIElement
---@param selected boolean?
---@param dimmed boolean?
local function styleCell(cell, selected, dimmed)
    if selected then
        cell.bgColor = TB_MENU_DEFAULT_LIGHTEST_COLOR
        cell.hoverColor = TB_MENU_DEFAULT_LIGHTEST_COLOR
        cell.uiColor = CELL_SELECTED_TEXT
    else
        cell.bgColor = dimmed and CELL_DIMMED_BG or TB_MENU_DEFAULT_BG_COLOR
        cell.hoverColor = TB_MENU_DEFAULT_LIGHTER_COLOR
        cell.uiColor = dimmed and CELL_DIMMED_TEXT or CELL_TEXT
    end
    cell.pressedColor = TB_MENU_DEFAULT_DARKEST_COLOR
end

---@class GridListOptions
---@field label fun(item: any): string cell text
---@field isSelected fun(item: any): boolean?
---@field onClick fun(item: any, additive: boolean) changes the selection, the cells are restyled after
---@field popup (fun(item: any): string?)? hover text of a cell
---@field isDimmed (fun(item: any): boolean?)? drawn faint while not selected
---@field columns integer? cells per row, default GRID_COLUMNS

---Grid list: one button per item, GRID_COLUMNS per row, selected ones pale (the object list, the joint
---list). A click calls onClick with Shift as additive, then restyles the cells in place: rebuilding the
---list would reset its scroll position
---@param view UIElement
---@param rect { x: number, y: number, w: number, h: number }
---@param items any[]
---@param opts GridListOptions
---@param toReload UIElement
---@return fun() restyle the cells from opts.isSelected / isDimmed again, for selections changed elsewhere
---(the Link tab's grid after a world click), keeps the scroll position a rebuild would reset
function obj_selector.grid(view, rect, items, opts, toReload)
    local columns = opts.columns or GRID_COLUMNS
    local gridRows = {}
    for i, item in ipairs(items) do
        local r = math.ceil(i / columns)
        gridRows[r] = gridRows[r] or {}
        table.insert(gridRows[r], item)
    end
    local function restyle(item, cell)
        styleCell(cell, opts.isSelected(item), opts.isDimmed and opts.isDimmed(item))
    end

    ---@type table<any, UIElement> cells on this page, restyled when a click changes others
    local cells = {}
    local function restyleAll()
        for item, cell in pairs(cells) do
            if not cell.destroyed then restyle(item, cell) end
        end
    end
    ScrollList.create(view, rect, gridRows, function(rowElement, rowItems)
        local cellW = (rowElement.size.w - GRID_GAP * (columns + 1)) / columns
        for c, item in ipairs(rowItems) do
            local cell = rowElement:addChild({
                pos = { GRID_GAP + (c - 1) * (cellW + GRID_GAP), 2 },
                size = { cellW, rowElement.size.h - 4 },
                interactive = true,
                -- colors given on creation too, toriui sets up the hover animation from them
                bgColor = TB_MENU_DEFAULT_BG_COLOR,
                hoverColor = TB_MENU_DEFAULT_LIGHTER_COLOR,
                pressedColor = TB_MENU_DEFAULT_DARKEST_COLOR,
            }, true)
            cells[item] = cell
            restyle(item, cell)
            cell:addAdaptedText(opts.label(item), nil, nil, nil, CENTERMID, 0.7, nil, nil)
            local text = opts.popup and opts.popup(item)
            if text then TBMenu:displayPopup(cell, text) end
            cell:addMouseUpHandler(function()
                opts.onClick(item, get_keyboard_shift() ~= 0)
                restyleAll()
            end)
        end
    end, toReload)
    return restyleAll
end

local function create(view, fullList)

    local list, page, pageCount = ScrollList.paginate(fullList, Main.page, Main.pageSize)
    Main.page = page -- clamped, e.g. after deleting objects on last page
    local listElementHeight = ScrollList.rowHeight

    -- Spawning a parent element for any object that needs to be reloaded every frame
    local toReload = UIElement:new({
        parent = view,
        pos = { 0, 0 },
        size = { view.size.w, view.size.h }
    })

    -- pages, Select All is an icon in the bottom bar
    local topBar = UIElement:new({
        parent = toReload,
        pos = { 0, 0 },
        size = { view.size.w, listElementHeight },
        bgColor = Widgets.TAB_PANEL_SOLID, -- list bars match the tab panel they sit in
        interactive = true
    })

    local botBar = UIElement:new({
        parent = toReload,
        pos = { 0, -listElementHeight },
        size = { view.size.w, listElementHeight },
        bgColor = Widgets.TAB_PANEL_SOLID, -- list bars match the tab panel they sit in
        interactive = true
    })

    -- grid between top and bottom bars, one cell per object. Click selects only that object, Shift +
    -- click adds / removes it (ModData.clickSelect, same as clicking objects in the world)
    obj_selector.grid(view, {
        x = 0,
        y = topBar.size.h,
        w = view.size.w,
        h = view.size.h - topBar.size.h - botBar.size.h
    }, list, {
        label = function(obj) return tostring(obj.id) end,
        isSelected = function(obj) return obj.selected end,
        onClick = function(obj, additive)
            local selected = ModData.clickSelect(obj, additive)
            -- the selection is framed when the Camera button is on
            if selected then MGE.Camera.followSelection() end
            Main.onSelectionChanged()
        end,
    }, toReload)

    ScrollList.createPager(topBar, { x = 0, y = 0, w = topBar.size.w, h = topBar.size.h }, page, pageCount,
        function(newPage)
            Main.page = newPage
            Main.updateWindow()
        end)

    local function allSelected()
        if #fullList == 0 then return false end
        for _, obj in ipairs(fullList) do
            if not obj.selected then return false end
        end
        return true
    end

    -- New adds the default object, Duplicate/Delete/Export act on selected objects, Import opens the
    -- asset list (ui/assets.lua), Select All is Ctrl + A. In the list's bar so they're there on every tab
    -- (Reindex is in the editor's Advanced panel). Icons share the width, their names show on hover.
    -- MGE.Editor loads after this module, so it's looked up on click
    local barIcons = Widgets.barButtons(botBar, {
        -- selects all, or deselects all when everything is selected
        { label = "Select / deselect all (Ctrl + A)", icon = MGE.scriptPath .. "textures/selectall.tga", wide = true,
            onClick = function() Main.toggleSelectAll() end },
        { label = "New (Ctrl + N)", icon = "../textures/menu/general/buttons/addsign.tga", wide = true,
            onClick = function() MGE.Assets.newObject() end },
        { label = "Duplicate (Ctrl + D)", icon = MGE.scriptPath .. "textures/duplicate.tga", wide = true,
            onClick = function() MGE.Editor.duplicate() end },
        { label = "Import", icon = MGE.scriptPath .. "textures/import.tga", wide = true,
            onClick = function() MGE.Assets.openImport() end },
        { label = "Export", icon = MGE.scriptPath .. "textures/export.tga", wide = true,
            onClick = function() MGE.Assets.export() end },
        -- last, away from the others
        { label = "Delete (Del)", icon = "../textures/menu/general/buttons/trash.tga", wide = true,
            onClick = function() MGE.Editor.deleteSelected() end }, -- asks first
    })
    -- lit while everything is selected (the next click deselects). Checked every frame before the button
    -- draws, so it follows clicks on single cells too (those don't rebuild the list). Added after the
    -- button's hover popup, which uses the same per-frame slot
    local selectAllButton = barIcons[1] --[[@as UIElement]]
    Widgets.addDrawBefore(selectAllButton, function()
        selectAllButton.bgColor = allSelected() and TB_MENU_DEFAULT_LIGHTER_COLOR or Widgets.STYLE.bg
    end)
end

obj_selector.create = create

return obj_selector
