-- Players tab of the list area: one row per player, its export icon saves that player's model. Click
-- picks the player the players panel works on (Main.selectedPlayer), Shift + click adds more players
-- (Main.selectedPlayers): the gizmo, the highlight and Import (the bottom bar) work on all of them

local player_list = {}

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

---@param view UIElement list area, emptied by the caller
function player_list.create(view)
    local toReload = view:addChild({
        pos = { 0, 0 },
        size = { view.size.w, view.size.h },
    })
    -- same bottom bar as the object list: Import gives every selected player the picked model. Export is
    -- one model, so it's on each player's row instead
    local barH = ScrollList.rowHeight
    local botBar = toReload:addChild({
        pos = { 0, -barH },
        size = { view.size.w, barH },
        bgColor = MGE.Widgets.TAB_PANEL_SOLID, -- list bars match the tab panel they sit in
        interactive = true,
    })
    MGE.Widgets.barButtons(botBar, {
        { label = "Import model to the selected players", icon = MGE.scriptPath .. "textures/import.tga", wide = true,
            onClick = function() MGE.Assets.openImport() end },
    })

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
