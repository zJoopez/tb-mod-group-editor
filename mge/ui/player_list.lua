-- Players tab of the list area: one row per player. Click picks the player the players panel works on
-- (Main.selectedPlayer), Shift + click adds more players (Main.selectedPlayers): the gizmo, the
-- highlight and Import (the bottom bar) work on all of them, Export on the first selected one

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
    MGE.confirm(message, function()
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
    end)
end

---Export (the bottom bar): saves one player's model, the first selected player's (lowest number).
---Players on the default body have nothing to save, Assets says so
function player_list.exportFirst()
    local first = Main.selectedPlayerList()[1]
    if not first then
        TBMenu:showStatusMessage("Select the player to export the model of first")
        return
    end
    MGE.Assets.exportPlayer(first)
end

---Reset model (the Players Core tab's Model row): the selected players with a model of their own (a
---`player N` section) back on the default body. One undo step, the mod reloads
---@param players integer[]
function player_list.resetModels(players)
    local map, any = {}, false
    for _, id in ipairs(players) do
        if FileHandler.getPlayerLines(ModData.parsed, id) then map[id], any = false, true end
    end
    if not any then return end
    FileHandler.renumberPlayers(ModData.parsed, map) -- false: the section goes, the other players keep theirs
    MGE.History.commit()
    MGE.apply() -- body changes need a reload
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
    -- the object list's buttons under the list, same order: Select all, New, Duplicate, Import (gives every
    -- selected player the picked model), Export (one model: the first selected player's), Delete.
    -- New / Duplicate change numplayers (at most Players.MAX), Delete keeps one player
    local barIcons = Main.setListActions({
        { label = "Select / deselect all players (Ctrl + A)", icon = MGE.scriptPath .. "textures/selectall.tga", wide = true,
            onClick = function() Main.toggleSelectAllPlayers() end },
        { label = "New player (Ctrl + N), at most " .. MGE.Players.MAX, icon = "../textures/menu/general/buttons/addsign.tga", wide = true,
            onClick = player_list.newPlayer },
        { label = "Duplicate selected players (Ctrl + D)", icon = MGE.scriptPath .. "textures/duplicate.tga", wide = true,
            onClick = player_list.duplicate },
        { label = "Import model to the selected players", icon = MGE.scriptPath .. "textures/import.tga", wide = true,
            onClick = function() MGE.Assets.openImport() end },
        { label = "Export the first selected player's model", icon = MGE.scriptPath .. "textures/export.tga", wide = true,
            onClick = player_list.exportFirst },
        { label = "Delete selected players (Del)", icon = "../textures/menu/general/buttons/trash.tga", wide = true,
            onClick = player_list.deleteSelected }, -- asks first
    })
    -- lit while every player is selected, like the object list's (after the hover popup, same slot)
    local selectAllButton = barIcons[1] --[[@as UIElement]]
    MGE.Widgets.addDrawBefore(selectAllButton, function()
        selectAllButton.bgColor = allSelected() and MGE.Widgets.ACTIVE_COLOR or Main.ACTIONS_BG
    end)

    local ids = {}
    for i = 0, Main.getPlayerCount() - 1 do table.insert(ids, i) end

    ScrollList.create(view, { x = 0, y = 0, w = view.size.w, h = view.size.h }, ids, function(row, id)
        row:addAdaptedText("Player " .. id, 8, nil, MGE.Widgets.FONT, LEFTMID, MGE.Widgets.TEXT_SCALE, nil, nil)
        local info = row:addChild({
            pos = { row.size.w / 2, 0 },
            size = { row.size.w / 2 - 8, row.size.h },
        })
        info:addAdaptedText(describeModel(id), nil, nil, MGE.Widgets.FONT, RIGHTMID, MGE.Widgets.TEXT_SCALE_SMALL, nil, nil)
        if Main.selectedPlayers[id] then row.bgColor = ScrollList.selectedColor end
        -- click picks the player, Shift + click adds / removes it (Main.selectPlayer rebuilds the list)
        row:addMouseUpHandler(function() Main.selectPlayer(id, get_keyboard_shift() ~= 0) end)
    end)
end

return player_list
