-- Players panel (editor area on the Players list), Enter in a field applies it:
--   Pos / Rot:  where the picked player is (Main.selectedPlayer): its center from the dojo center and
--               its rotation, placeholders the current values also in mods without positions. Saved as
--               the engageplayerpos / engageplayerrot gamerules (utils/players.lua)
--   Scale:      a factor for the selected players' size, like the Scale gizmo's white cube
--   Density:    the picked player's average body part density, a typed value sets that average for
--               the selected players (all parts scaled together, their ratios stay)
--   Strength:   the same for the average joint strength (neck 1 / knees 4 differences stay)
--   Friction / Bounce: the same for body parts and joints together
-- With several players selected the part rows apply the picked player's factor to all of them.
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

---Applies a typed part value to the selected players: as a factor of the picked player's current
---average (ratios between parts stay), or set on every part when that average is 0
---@param inputs UIElement[]
---@param key "density"|"strength"|"friction"|"bounce"
---@param current number the picked player's average now
local function applyTyped(inputs, key, current)
    local typed = tonumber(inputs[1].textfieldstr[1])
    if not typed or typed < 0 then return end
    local Players, list = MGE.Players, MGE.Main.selectedPlayerList()
    if current <= 1e-9 then
        Players.setParts(list, key, typed)
    else
        Players.multiplyParts(list, key, typed / current)
    end
end

---Pos / Rot rows for the picked player, rebuilt when the player, the gamerules or the mod change
---(placeholders show the current values)
---@param holder UIElement
local function buildPlayer(holder)
    Rows.begin()
    local Players = MGE.Players
    local player = MGE.Main.selectedPlayer
    local pos, rot
    if Players.exists(player) then pos, rot = Players.shown(player) end
    inwuts.playerPos = createInputRow("Pos", holder, function(_, i)
        Players.setShownPos(player, readInputs(inwuts.playerPos, i))
    end, pos and formatHints(pos) or NOT_SET,
        "Player " .. player .. "'s center, from the dojo center\n" ..
        "(like objects' Pos). Saved as engageplayerpos: a mod\n" ..
        "without it gets it for every player on the first change.")
    inwuts.playerRot = createInputRow("Rot", holder, function(_, i)
        Players.setShownRot(player, readInputs(inwuts.playerRot, i))
    end, rot and formatHints(rot) or NOT_SET,
        "Player " .. player .. "'s rotation in degrees, turned around\n" ..
        "its center like the Rotate gizmo. Saved as\n" ..
        "engageplayerrot.")
end

---Scale row: multiplies the selected players' size (all of them, a factor is relative), like the
---Scale gizmo's white cube. Built once, the typed factor stays to try again
---@param holder UIElement
local function buildScale(holder)
    Rows.begin()
    inwuts.playerScale = createInputRow("Scale", holder, function()
        local factor = tonumber(inwuts.playerScale[1].textfieldstr[1])
        if not factor or factor <= 0 then return end
        MGE.Players.scaleBy(MGE.Main.selectedPlayerList(), factor)
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

---Density / Strength / Friction / Bounce rows for the picked player, rebuilt like Pos / Rot
---(placeholders show the averages)
---@param holder UIElement
local function buildParts(holder)
    Rows.begin()
    local player = MGE.Main.selectedPlayer
    for _, row in ipairs(PART_ROWS) do
        local name, key = row[1], row[3]
        local current = MGE.Players.partAverage(player, key)
        inwuts[name] = createInputRow(row[2], holder, function()
            applyTyped(inwuts[name], key, current)
        end, { hint(current) }, row[4])
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
