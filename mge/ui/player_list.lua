-- Players tab of the list area: one row per player, click picks the player Export saves and
-- Import replaces (Main.selectedPlayer)

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
    -- same bottom bar as the object list: Import opens the player model list, Export saves the picked player
    local barH = ScrollList.rowHeight
    local botBar = toReload:addChild({
        pos = { 0, -barH },
        size = { view.size.w, barH },
        bgColor = MGE.Widgets.TAB_PANEL_SOLID, -- list bars match the tab panel they sit in
        interactive = true,
    })
    MGE.Widgets.barButtons(botBar, {
        { label = "Import", icon = MGE.scriptPath .. "textures/import.tga", wide = true,
            onClick = function() MGE.Assets.openImport() end },
        { label = "Export", icon = MGE.scriptPath .. "textures/export.tga", wide = true,
            onClick = function() MGE.Assets.export() end },
    })

    local ids = {}
    for i = 0, Main.getPlayerCount() - 1 do table.insert(ids, i) end

    local rows = {}
    ScrollList.create(view, { x = 0, y = 0, w = view.size.w, h = view.size.h - barH }, ids, function(row, id, index)
        rows[id] = { row = row, index = index }
        row:addAdaptedText("Player " .. id, 8, nil, nil, LEFTMID, 0.7, nil, nil)
        local info = row:addChild({
            pos = { row.size.w / 2, 0 },
            size = { row.size.w / 2 - 8, row.size.h },
        })
        info:addAdaptedText(describeModel(id), nil, nil, nil, RIGHTMID, 0.6, nil, nil)
        if id == Main.selectedPlayer then row.bgColor = ScrollList.selectedColor end
        row:addMouseUpHandler(function()
            local previous = rows[Main.selectedPlayer]
            if previous then previous.row.bgColor = ScrollList.getRowColor(previous.index) end
            Main.selectedPlayer = id
            row.bgColor = ScrollList.selectedColor
        end)
    end, toReload)
end

return player_list
