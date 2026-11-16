












local Rows = MGE.EditorRows
local inwuts = Rows.inputs
local readInputs = Rows.readInputs
local createInputRow = Rows.createInputRow

local NOT_SET = { "-", "-", "-" }




local function hint(v)
    return string.format("%.3g", v)
end




local function wholeHints(values)
    local hints = {}
    for i = 1, 3 do hints[i] = tostring(MGE.Players.wholeDegrees(values[i])) end
    return hints
end




local function panelPlayers()
    local Main, Players = MGE.Main, MGE.Players
    local selected = Main.selectedPlayerList()
    local list = {}
    if Players.exists(Main.selectedPlayer) and (#selected == 0 or Main.selectedPlayers[Main.selectedPlayer]) then
        table.insert(list, Main.selectedPlayer)
    end
    for _, id in ipairs(selected) do
        if id ~= Main.selectedPlayer and Players.exists(id) then table.insert(list, id) end
    end
    return list
end




local function whom(list)
    if #list == 1 then return "player " .. list[1] end
    return "the " .. #list .. " selected players"
end







local function applyTyped(inputs, key, list, current)
    local typed = tonumber(inputs[1].textfieldstr[1])
    if not typed or typed < 0 or #list == 0 then return end
    local Players = MGE.Players
    if current <= 1e-9 then
        Players.setParts(list, key, typed)
    else
        Players.multiplyParts(list, key, typed / current)
    end
end


local gizmoLabels, highlightGizmoLabels = Rows.gizmoLabels()




local function buildPlayer(holder)
    Rows.begin()
    local Players = MGE.Players
    local list = panelPlayers()
    local pos, rot
    if #list > 0 then pos, rot = Players.shown(list) end
    local posHelp, rotHelp
    if #list > 1 then
        posHelp = "Center of " .. whom(list) .. " from the\ndojo center, they move together."
        rotHelp = "Player " .. list[1] .. "'s rotation, the others turn\nwith it around the group's center."
    else
        posHelp = "Center of " .. whom(list) .. " from the dojo center."
        rotHelp = "Rotation of " .. whom(list) .. " in whole degrees."
    end
    local _
    inwuts.playerPos, _, gizmoLabels.move = createInputRow("Pos", holder, function(_, i)
        if #list > 0 then Players.setShownPos(list, readInputs(inwuts.playerPos, i)) end
    end, pos or NOT_SET, posHelp)
    inwuts.playerRot, _, gizmoLabels.rotate = createInputRow("Rot", holder, function(_, i)
        if #list > 0 then Players.setShownRot(list, readInputs(inwuts.playerRot, i)) end
    end, rot and wholeHints(rot) or NOT_SET, rotHelp, nil, { whole = true, angle = true })


    local size = #list > 0 and Players.groupSize(list) or nil
    inwuts.playerScale, _, gizmoLabels.scale = createInputRow("Scale", holder, function()
        local typed = tonumber(inwuts.playerScale[1].textfieldstr[1])
        if not typed or typed <= 0 or not size or size <= 0 then return end
        Players.scaleBy(list, typed / size)
    end, { size or "-" }, "Size of " .. whom(list) .. " (default body 1).\nBigger is heavier.")
    highlightGizmoLabels()
end


local PART_ROWS = {
    { "playerDensity", "Density", "density",
        "Average body part density (default 0.25),\nall parts scaled together." },
    { "playerStrength", "Strength", "strength",
        "Average joint strength (default 1-4),\nall joints scaled together." },
    { "playerFriction", "Friction", "friction",
        "Average friction of parts and joints\n(default 0.3), all scaled together." },
    { "playerBounce", "Bounce", "bounce",
        "Average bounce of parts and joints\n(default 0.1), all scaled together." },
}




local function buildParts(holder)
    Rows.begin()
    local list = panelPlayers()
    for _, row in ipairs(PART_ROWS) do
        local name, key = row[1], row[3]
        local current = MGE.Players.groupPartAverage(list, key)
        inwuts[name] = createInputRow(row[2], holder, function()
            applyTyped(inwuts[name], key, list, current)

        end, { #list > 0 and { text = hint(current), value = current } or "-" }, row[4])
    end
end



local function buildModel(holder)
    Rows.begin()
    Rows.createToggleButtonRow("Model", holder, {
        { label = "Reset", active = false, onClick = function() MGE.PlayerList.resetModels(panelPlayers()) end },
    }, "Back to the default body (one undo step).")
end


return {
    fixed = {
        { build = buildModel, panel = "player", row = 3 + #PART_ROWS, rows = 1 },
    },
    blocks = {
        { name = "player", build = buildPlayer, panel = "player", row = 0, rows = 3 },
        { name = "playerParts", build = buildParts, panel = "player", row = 3, rows = #PART_ROWS },
    },
    inputs = {
        rebuilt = { "playerPos", "playerRot", "playerScale", "playerDensity", "playerStrength", "playerFriction", "playerBounce" },
    },
}
