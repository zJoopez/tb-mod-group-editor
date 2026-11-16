local obj_selector = {}
MGE.ObjSelector = obj_selector

local Main = MGE.Main
local ModData = MGE.ModData
local ScrollList = MGE.ScrollList
local Widgets = MGE.Widgets

local GRID_COLUMNS = 6
local GRID_GAP = MGE.Widgets.GAP


local CELL_TEXT = { 1, 1, 1, 1 }
local CELL_SELECTED_TEXT = CELL_TEXT
local CELL_DIMMED_TEXT = { 1, 1, 1, 0.35 }
local CELL_DIMMED_BG = { 0, 0, 0, 0.15 }




local function styleCell(cell, selected, dimmed)
    if selected then
        cell.bgColor = Widgets.SELECTED_COLOR
        cell.hoverColor = Widgets.SELECTED_COLOR
        cell.uiColor = CELL_SELECTED_TEXT
    else
        cell.bgColor = dimmed and CELL_DIMMED_BG or TB_MENU_DEFAULT_BG_COLOR
        cell.hoverColor = Widgets.HOVER_COLOR
        cell.uiColor = dimmed and CELL_DIMMED_TEXT or CELL_TEXT
    end
    cell.pressedColor = TB_MENU_DEFAULT_DARKEST_COLOR
end




















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

                pos = { GRID_GAP + (c - 1) * (cellW + GRID_GAP), GRID_GAP / 2 },
                size = { cellW, rowElement.size.h - GRID_GAP },
                interactive = true,

                bgColor = TB_MENU_DEFAULT_BG_COLOR,
                hoverColor = Widgets.HOVER_COLOR,
                pressedColor = TB_MENU_DEFAULT_DARKEST_COLOR,
            }, true)
            cells[item] = cell
            restyle(item, cell)
            cell:addAdaptedText(opts.label(item), nil, nil, MGE.Widgets.FONT, CENTERMID, MGE.Widgets.TEXT_SCALE, nil, nil)
            local text = opts.popup and opts.popup(item)
            if text then Widgets.popupBelow(cell, text) end
            cell:addMouseUpHandler(function()
                opts.onClick(item, get_keyboard_shift() ~= 0)
                restyleAll()
            end)
        end
    end, toReload, opts.emptyText, true)
    return restyleAll
end






local function create(view, fullList, mode)
    local atmo = mode == "atmo"

    local list, page, pageCount = ScrollList.paginate(fullList, Main.page, Main.pageSize)
    Main.page = page
    local listElementHeight = ScrollList.rowHeight


    local pagerH = pageCount > 1 and listElementHeight or 0
    if pageCount > 1 then
        local pagerRow = view:addChild({
            pos = { 0, 0 },
            size = { view.size.w, pagerH },
        })
        ScrollList.createPager(pagerRow, { x = 0, y = 0, w = pagerRow.size.w, h = pagerRow.size.h }, page, pageCount,
            function(newPage)
                Main.page = newPage
                Main.updateWindow()
            end)
    end



    obj_selector.grid(view, {
        x = 0,
        y = pagerH,
        w = view.size.w,
        h = view.size.h - pagerH
    }, list, {
        label = function(obj) return (atmo and "A" or "") .. tostring(obj.id) end,

        emptyText = atmo and "Atmo has no objects\nTry adding some"
            or "Mod has no objects\nTry adding some",
        isSelected = function(obj) return obj.selected end,
        onClick = function(obj, additive)
            local selected = ModData.clickSelect(obj, additive)
            Main.onSelectionChanged()
            if selected then Main.selectionMade() end
        end,
    })


    local function allSelected()
        if #fullList == 0 then return false end
        for _, obj in ipairs(fullList) do
            if not obj.selected then return false end
        end
        return true
    end






    local barIcons = Main.setListActions({

        { label = "Select / deselect all (Ctrl + A)", icon = MGE.scriptPath .. "textures/selectall.tga", wide = true,
            onClick = function() if atmo then Main.toggleSelectAllAtmo() else Main.toggleSelectAll() end end },
        { label = atmo and "New atmo box (Ctrl + N)" or "New (Ctrl + N)", icon = "../textures/menu/general/buttons/addsign.tga",
            wide = true, onClick = function() if atmo then MGE.Assets.newAtmo() else MGE.Assets.newObject() end end },
        { label = "Duplicate (Ctrl + D)", icon = MGE.scriptPath .. "textures/duplicate.tga", wide = true,
            onClick = function() MGE.Editor.duplicate() end },
        { label = atmo and "Import an .atmo" or "Import", icon = MGE.scriptPath .. "textures/import.tga", wide = true,
            onClick = function() if atmo then MGE.Assets.openAtmoImport() else MGE.Assets.openImport() end end },
        { label = atmo and "Export the selected as an .atmo" or "Export", icon = MGE.scriptPath .. "textures/export.tga",
            wide = true, onClick = function() if atmo then MGE.Assets.exportAtmo() else MGE.Assets.export() end end },

        { label = "Delete (Del)", icon = "../textures/menu/general/buttons/trash.tga", wide = true,
            onClick = function() MGE.Editor.deleteSelected() end },
    })



    local selectAllButton = barIcons[1]
    Widgets.addDrawBefore(selectAllButton, function()
        selectAllButton.bgColor = allSelected() and MGE.Widgets.ACTIVE_COLOR or Main.ACTIONS_BG
    end)
end

obj_selector.create = create

return obj_selector
