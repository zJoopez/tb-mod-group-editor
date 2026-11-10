-- Players panel (editor area on the Players list), Enter in a field applies it. Every row shows and
-- changes the selected players, like the object rows a selection (with none selected: the picked
-- player, Main.selectedPlayer, the one the list shows last):
--   Pos / Rot:  the group's center from the dojo center, and the picked player's rotation (the group
--               turns as one around its center), placeholders the current values also in mods without
--               positions. Saved as the engageplayerpos / engageplayerrot gamerules (utils/players.lua)
--   Scale:      a factor for the size, like the Scale gizmo's white cube
--   Density:    the average body part density of the players, a typed value sets that average (all
--               parts of all of them scaled together, their ratios stay)
--   Strength:   the same for the average joint strength (neck 1 / knees 4 differences stay)
--   Friction / Bounce: the same for body parts and joints together
-- The Move / Rotate / Scale gizmos do the same in the world.
local Rows = MGE.EditorRows
local inwuts = Rows.inputs
local readInputs = Rows.readInputs
local formatHints = Rows.formatHints
local createInputRow = Rows.createInputRow

local NOT_SET = { "-", "-", "-" }

---Value as a placeholder: three significant digits, small densities like 0.0001 still readable
---@param v number
---@return string
local function hint(v)
    return string.format("%.3g", v)
end

---Players the panel works on: the selected ones with the picked player first (its rotation is the
---one shown), or only the picked player when none are selected. Players not in the world left out
---@return integer[]
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

---"player 2" or "the 3 selected players", for the help texts
---@param list integer[]
---@return string
local function whom(list)
    if #list == 1 then return "player " .. list[1] end
    return "the " .. #list .. " selected players"
end

---Applies a typed part value to the players: as a factor of their current average (ratios between
---parts and players stay), or set on every part when that average is 0
---@param inputs UIElement[]
---@param key "density"|"strength"|"friction"|"bounce"
---@param list integer[] the players
---@param current number their average now
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

---Pos / Rot rows for the players, rebuilt when the selection, the gamerules or the mod change
---(placeholders show the current values)
---@param holder UIElement
local function buildPlayer(holder)
    Rows.begin()
    local Players = MGE.Players
    local list = panelPlayers()
    local pos, rot
    if #list > 0 then pos, rot = Players.shown(list) end
    local posHelp, rotHelp
    if #list > 1 then
        posHelp = "Center of " .. whom(list) .. ", from the\n" ..
            "dojo center (like objects' Pos), they move together.\n"
        rotHelp = "Player " .. list[1] .. "'s rotation in degrees, the others\n" ..
            "turn with it as one group around their center,\n"
    else
        posHelp = "Center of " .. whom(list) .. ", from the dojo center\n" ..
            "(like objects' Pos). "
        rotHelp = "Rotation of " .. whom(list) .. " in degrees, turned around\n" ..
            "its center, "
    end
    inwuts.playerPos = createInputRow("Pos", holder, function(_, i)
        if #list > 0 then Players.setShownPos(list, readInputs(inwuts.playerPos, i)) end
    end, pos and formatHints(pos) or NOT_SET,
        posHelp .. "Saved as engageplayerpos: a mod\n" ..
        "without it gets it for every player on the first change.")
    inwuts.playerRot = createInputRow("Rot", holder, function(_, i)
        if #list > 0 then Players.setShownRot(list, readInputs(inwuts.playerRot, i)) end
    end, rot and formatHints(rot) or NOT_SET,
        rotHelp .. "like the Rotate gizmo. Saved as engageplayerrot.")
end

---Scale row: multiplies the selected players' size (all of them, a factor is relative), like the
---Scale gizmo's white cube. Built once, the typed factor stays to try again
---@param holder UIElement
local function buildScale(holder)
    Rows.begin()
    inwuts.playerScale = createInputRow("Scale", holder, function()
        local factor = tonumber(inwuts.playerScale[1].textfieldstr[1])
        if not factor or factor <= 0 then return end
        MGE.Players.scaleBy(panelPlayers(), factor)
    end, { "1.00" },
        "Multiplies the selected players' size (body parts,\n" ..
        "joints and the distances between them), around\n" ..
        "their center. Density stays: bigger is heavier.")
end

-- part rows: input name, label, mod line, help
local PART_ROWS = {
    { "playerDensity", "Density", "density",
        "Average body part density (default 0.25). A typed\n" ..
        "value sets it for the selected players, every part\n" ..
        "scaled together: heavier or lighter, the size stays." },
    { "playerStrength", "Strength", "strength",
        "Average joint strength (the game's defaults are\n" ..
        "1-4 per joint). A typed value sets it for the selected\n" ..
        "players, every joint scaled together." },
    { "playerFriction", "Friction", "friction",
        "Average friction of body parts and joints (default\n" ..
        "0.3). A typed value sets it for the selected players,\n" ..
        "every part scaled together." },
    { "playerBounce", "Bounce", "bounce",
        "Average bounce of body parts and joints (default\n" ..
        "0.1). A typed value sets it for the selected players,\n" ..
        "every part scaled together." },
}

---Density / Strength / Friction / Bounce rows for the players, rebuilt like Pos / Rot (placeholders
---show their averages)
---@param holder UIElement
local function buildParts(holder)
    Rows.begin()
    local list = panelPlayers()
    for _, row in ipairs(PART_ROWS) do
        local name, key = row[1], row[3]
        local current = MGE.Players.groupPartAverage(list, key)
        inwuts[name] = createInputRow(row[2], holder, function()
            applyTyped(inwuts[name], key, list, current)
        end, { #list > 0 and hint(current) or "-" }, row[4])
    end
end

---@type EditorPanelModule
return {
    fixed = { { build = buildScale, panel = "player", row = 2, rows = 1 } },
    blocks = {
        { name = "player", build = buildPlayer, panel = "player", row = 0, rows = 2 },
        { name = "playerParts", build = buildParts, panel = "player", row = 3, rows = #PART_ROWS },
    },
    inputs = {
        fixed = { "playerScale" },
        rebuilt = { "playerPos", "playerRot", "playerDensity", "playerStrength", "playerFriction", "playerBounce" },
    },
}
