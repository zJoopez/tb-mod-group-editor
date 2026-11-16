



local player_list = {}
MGE.PlayerList = player_list

local Main = MGE.Main
local ModData = MGE.ModData
local FileHandler = MGE.FileHandler
local ScrollList = MGE.ScrollList



local function countParts(lines)
    local count = 0
    for _, line in ipairs(lines) do
        if line:match("^%s*body%s") or line:match("^%s*joint%s") then count = count + 1 end
    end
    return count
end




local function describeModel(id)
    local own = FileHandler.getPlayerLines(ModData.parsed, id)
    if own then return countParts(own) .. " parts changed" end
    local shared = FileHandler.getSharedPlayerLines(ModData.parsed)
    if shared then return countParts(shared) .. " parts changed (all players)" end
    return "default body"
end



local function selectOnly(ids)
    Main.selectedPlayers = {}
    for _, id in ipairs(ids) do Main.selectedPlayers[id] = true end
    if ids[1] then Main.selectedPlayer = ids[1] end
end


function player_list.newPlayer()
    local Players = MGE.Players
    local point = Players.exists(0) and MGE.Camera.spawnPoint(Players.bounds(0)) or nil
    Players.addNew(point, selectOnly)
end


function player_list.duplicate()
    MGE.Players.duplicate(Main.selectedPlayerList(), selectOnly)
end


function player_list.deleteSelected()
    local list = Main.selectedPlayerList()
    local count = #list
    if count == 0 or (MGE.confirmOverlay and not MGE.confirmOverlay.destroyed) then return end
    if count >= Main.getPlayerCount() then
        MGE.say("a mod needs at least one player")
        return
    end
    local message = "Delete " .. (count == 1 and "player " .. list[1] or count .. " selected players") ..
        "?\nLater players move down to fill the numbers.\nUndo can bring them back."
    MGE.confirm(message, function()
        MGE.Players.remove(list, function(map)
            Main.selectedPlayers = {}

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



function player_list.exportFirst()
    local first = Main.selectedPlayerList()[1]
    if not first then
        TBMenu:showStatusMessage("Select the player to export the model of first")
        return
    end
    MGE.Assets.exportPlayer(first)
end




function player_list.resetModels(players)
    local map, any = {}, false
    for _, id in ipairs(players) do
        if FileHandler.getPlayerLines(ModData.parsed, id) then map[id], any = false, true end
    end
    if not any then return end
    FileHandler.renumberPlayers(ModData.parsed, map)
    MGE.History.commit()
    MGE.apply()
end


local function allSelected()
    for id = 0, Main.getPlayerCount() - 1 do
        if not Main.selectedPlayers[id] then return false end
    end
    return true
end


function player_list.create(view)



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
            onClick = player_list.deleteSelected },
    })

    local selectAllButton = barIcons[1]
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

        row:addMouseUpHandler(function() Main.selectPlayer(id, get_keyboard_shift() ~= 0) end)
    end)
end

return player_list
