local obj_selector = {}
MGE.ObjSelector = obj_selector -- its grid is also the joint list's (ui/joint_list.lua)

local Main = MGE.Main
local ModData = MGE.ModData
local ScrollList = MGE.ScrollList
local Widgets = MGE.Widgets

local GRID_COLUMNS = 6
local GRID_GAP = MGE.Widgets.GAP -- the number fields' gap

-- cell colors: selected cells are lighter (Widgets.SELECTED_COLOR), the text stays white
local CELL_TEXT = { 1, 1, 1, 1 }
local CELL_SELECTED_TEXT = CELL_TEXT
local CELL_DIMMED_TEXT = { 1, 1, 1, 0.35 } -- e.g. an empty joint slot
local CELL_DIMMED_BG = { 0, 0, 0, 0.15 }

---@param cell UIElement
---@param selected boolean?
---@param dimmed boolean?
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

---@class GridListOptions
---@field label fun(item: any): string cell text
---@field isSelected fun(item: any): boolean?
---@field onClick fun(item: any, additive: boolean) changes the selection, the cells are restyled after
---@field popup (fun(item: any): string?)? hover text of a cell
---@field isDimmed (fun(item: any): boolean?)? drawn faint while not selected
---@field columns integer? cells per row, default GRID_COLUMNS
---@field emptyText string? shown when there are no items

---Grid list: one button per item, GRID_COLUMNS per row, selected ones pale (the object list, the joint
---list). A click calls onClick with Shift as additive, then restyles the cells in place: rebuilding the
---list would reset its scroll position
---@param view UIElement
---@param rect { x: number, y: number, w: number, h: number }
---@param items any[]
---@param opts GridListOptions
---@param toReload UIElement? see ScrollList.create
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
                -- GRID_GAP between cells and between rows (half of it above and under each cell)
                pos = { GRID_GAP + (c - 1) * (cellW + GRID_GAP), GRID_GAP / 2 },
                size = { cellW, rowElement.size.h - GRID_GAP },
                interactive = true,
                -- colors given on creation too, toriui sets up the hover animation from them
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
    end, toReload, opts.emptyText, true) -- plain rows: the cells are the buttons
    return restyleAll
end

---The object list, or with mode "atmo" the Atmo list (the atmo objects, A1, A2..., utils/atmo_layer.lua):
---the same grid and bar, the bar's buttons work on what the list shows
---@param view UIElement
---@param fullList FileParserEnvObj[] the objects, or the atmo objects (ui/main.lua)
---@param mode "atmo"?
local function create(view, fullList, mode)
    local atmo = mode == "atmo"

    local list, page, pageCount = ScrollList.paginate(fullList, Main.page, Main.pageSize)
    Main.page = page -- clamped, e.g. after deleting objects on last page
    local listElementHeight = ScrollList.rowHeight

    -- pages (Main.pageSize objects each) only when there's more than one: a row above the grid
    local pagerH = pageCount > 1 and listElementHeight or 0
    if pageCount > 1 then
        local pagerRow = view:addChild({
            pos = { 0, 0 },
            size = { view.size.w, pagerH }, -- no color of its own: the list's, the grid goes on under it
        })
        ScrollList.createPager(pagerRow, { x = 0, y = 0, w = pagerRow.size.w, h = pagerRow.size.h }, page, pageCount,
            function(newPage)
                Main.page = newPage
                Main.updateWindow()
            end)
    end

    -- the grid, one cell per object, the whole list area (its buttons are in the bar under it). Click selects only
    -- that object, Shift + click adds / removes it (ModData.clickSelect, same as clicking objects in the world)
    obj_selector.grid(view, {
        x = 0,
        y = pagerH,
        w = view.size.w,
        h = view.size.h - pagerH
    }, list, {
        label = function(obj) return (atmo and "A" or "") .. tostring(obj.id) end,
        -- an empty mod / atmo: what adds some (the buttons under the list)
        emptyText = atmo and "Atmo has no objects\nTry adding some"
            or "Mod has no objects\nTry adding some",
        isSelected = function(obj) return obj.selected end,
        onClick = function(obj, additive)
            local selected = ModData.clickSelect(obj, additive)
            Main.onSelectionChanged()
            if selected then Main.selectionMade() end -- Generate back to Core, camera follow
        end,
    })

    -- lit while everything the list shows is selected
    local function allSelected()
        if #fullList == 0 then return false end
        for _, obj in ipairs(fullList) do
            if not obj.selected then return false end
        end
        return true
    end

    -- New adds the default object, Duplicate/Delete/Export act on selected objects, Import opens the
    -- asset list (ui/assets.lua), Select All is Ctrl + A. In the bar under the list (Main.setListActions) so they're
    -- there on every tab (Reindex is in the editor's Advanced panel), their names show on hover.
    -- On the Atmo list they're the atmo objects': New adds a default box to the atmo, Import / Export read
    -- and write .atmo files. MGE.Editor loads after this module, so it's looked up on click
    local barIcons = Main.setListActions({
        -- selects all, or deselects all when everything is selected
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
        -- last, away from the others
        { label = "Delete (Del)", icon = "../textures/menu/general/buttons/trash.tga", wide = true,
            onClick = function() MGE.Editor.deleteSelected() end }, -- asks first
    })
    -- lit while everything is selected (the next click deselects). Checked every frame before the button
    -- draws, so it follows clicks on single cells too (those don't rebuild the list). Added after the
    -- button's hover popup, which uses the same per-frame slot
    local selectAllButton = barIcons[1] --[[@as UIElement]]
    Widgets.addDrawBefore(selectAllButton, function()
        selectAllButton.bgColor = allSelected() and MGE.Widgets.ACTIVE_COLOR or Main.ACTIONS_BG
    end)
end

obj_selector.create = create

return obj_selector
