-- Players tab of the list area: one row per player, its export icon saves that player's model. Click
-- picks the player the players panel works on (Main.selectedPlayer), Shift + click adds more players
-- (Main.selectedPlayers): the gizmo, the highlight and Import (the bottom bar) work on all of them

local player_list = {}
MGE.PlayerList = player_list -- the shortcuts (main.lua) use its New / Duplicate / Delete

local Main = MGE.Main
local ModData = MGE.ModData
local FileHandler = MGE.FileHandler
local ScrollList = MGE.ScrollList

---@param lines string[]
---@return integer body and joint parts in a player section
local function countParts(lines)
    local count = 0
    for _, line in ipairs(lines) do
        if line:match("^%s*body%s") or line:match("^%s*joint%s") then count = count + 1 end
    end
    return count
end

---Where the player's model comes from in the mod file
---@param id integer
---@return string
local function describeModel(id)
    local own = FileHandler.getPlayerLines(ModData.parsed, id)
    if own then return countParts(own) .. " parts changed" end
    local shared = FileHandler.getSharedPlayerLines(ModData.parsed)
    if shared then return countParts(shared) .. " parts changed (all players)" end
    return "default body"
end

---Selects players (the new ones after New / Duplicate), the panel shows the first
---@param ids integer[]
local function selectOnly(ids)
    Main.selectedPlayers = {}
    for _, id in ipairs(ids) do Main.selectedPlayers[id] = true end
    if ids[1] then Main.selectedPlayer = ids[1] end
end

---New player (Ctrl + N on the Players list): the default body, standing in front of the camera
function player_list.newPlayer()
    local Players = MGE.Players
    local point = Players.exists(0) and MGE.Camera.spawnPoint(Players.bounds(0)) or nil
    Players.addNew(point, selectOnly)
end

---Duplicate (Ctrl + D on the Players list): copies of the selected players next to them, selected
function player_list.duplicate()
    MGE.Players.duplicate(Main.selectedPlayerList(), selectOnly)
end

---Delete (Del on the Players list): asks first, like objects. A mod keeps at least one player
function player_list.deleteSelected()
    local list = Main.selectedPlayerList()
    local count = #list
    if count == 0 or (MGE.confirmOverlay and not MGE.confirmOverlay.destroyed) then return end
    if count >= Main.getPlayerCount() then
        echo("^04[MGE] a mod needs at least one player")
        return
    end
    local message = "Delete " .. (count == 1 and "player " .. list[1] or count .. " selected players") ..
        "?\nLater players move down to fill the numbers.\nUndo can bring them back."
    MGE.confirmOverlay = TBMenu:showConfirmationWindow(message, function()
        MGE.confirmOverlay = nil
        MGE.Players.remove(list, function(map)
            Main.selectedPlayers = {} -- like objects: nothing selected after a delete
            -- the panel stays on the same player when it's kept, else the one now at its number
            local picked = map[Main.selectedPlayer]
            Main.selectedPlayer = picked or 0
            if not picked then
                for old, new in pairs(map) do
                    if new and old > Main.selectedPlayer then Main.selectedPlayer = new break end
                end
            end
        end)
    end, function()
        MGE.confirmOverlay = nil
    end)
end

---@return boolean every player is selected
local function allSelected()
    for id = 0, Main.getPlayerCount() - 1 do
        if not Main.selectedPlayers[id] then return false end
    end
    return true
end

---@param view UIElement list area, emptied by the caller
function player_list.create(view)
    local toReload = view:addChild({
        pos = { 0, 0 },
        size = { view.size.w, view.size.h },
    })
    -- same bottom bar as the object list, same order: Select all, New, Duplicate, Import (gives every
    -- selected player the picked model), Delete. Export is one model, so it's on each player's row
    -- instead. New / Duplicate change numplayers (at most Players.MAX), Delete keeps one player
    local barH = ScrollList.rowHeight
    local botBar = toReload:addChild({
        pos = { 0, -barH },
        size = { view.size.w, barH },
        bgColor = MGE.Widgets.TAB_PANEL_SOLID, -- list bars match the tab panel they sit in
        interactive = true,
    })
    local barIcons = MGE.Widgets.barButtons(botBar, {
        { label = "Select / deselect all players (Ctrl + A)", icon = MGE.scriptPath .. "textures/selectall.tga", wide = true,
            onClick = function() Main.toggleSelectAllPlayers() end },
        { label = "New player (Ctrl + N), at most " .. MGE.Players.MAX, icon = "../textures/menu/general/buttons/addsign.tga", wide = true,
            onClick = player_list.newPlayer },
        { label = "Duplicate selected players (Ctrl + D)", icon = MGE.scriptPath .. "textures/duplicate.tga", wide = true,
            onClick = player_list.duplicate },
        { label = "Import model to the selected players", icon = MGE.scriptPath .. "textures/import.tga", wide = true,
            onClick = function() MGE.Assets.openImport() end },
        { label = "Delete selected players (Del)", icon = "../textures/menu/general/buttons/trash.tga", wide = true,
            onClick = player_list.deleteSelected }, -- asks first
    })
    -- lit while every player is selected, like the object list's (after the hover popup, same slot)
    local selectAllButton = barIcons[1] --[[@as UIElement]]
    MGE.Widgets.addDrawBefore(selectAllButton, function()
        selectAllButton.bgColor = allSelected() and TB_MENU_DEFAULT_LIGHTER_COLOR or MGE.Widgets.STYLE.bg
    end)

    local ids = {}
    for i = 0, Main.getPlayerCount() - 1 do table.insert(ids, i) end

    ScrollList.create(view, { x = 0, y = 0, w = view.size.w, h = view.size.h - barH }, ids, function(row, id)
        row:addAdaptedText("Player " .. id, 8, nil, nil, LEFTMID, 0.7, nil, nil)
        -- export icon at the row's end, players with a model only (the default body has nothing to save)
        local iconSize = row.size.h - 4
        local exportW = 0
        if MGE.Assets.playerParts(id) then
            exportW = iconSize + 6
            local export = MGE.Widgets.iconButton(row, { x = row.size.w - iconSize - 4, y = 2, w = iconSize, h = iconSize },
                MGE.scriptPath .. "textures/export.tga", function() MGE.Assets.exportPlayer(id) end)
            TBMenu:displayPopup(export, "Export player " .. id .. "'s model")
        end
        local info = row:addChild({
            pos = { row.size.w / 2, 0 },
            size = { row.size.w / 2 - 8 - exportW, row.size.h },
        })
        info:addAdaptedText(describeModel(id), nil, nil, nil, RIGHTMID, 0.6, nil, nil)
        if Main.selectedPlayers[id] then row.bgColor = ScrollList.selectedColor end
        -- click picks the player, Shift + click adds / removes it (Main.selectPlayer rebuilds the list)
        row:addMouseUpHandler(function() Main.selectPlayer(id, get_keyboard_shift() ~= 0) end)
    end, toReload)
end

return player_list
