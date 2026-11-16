-- Players panel (editor area on the Players list), Enter in a field applies it. Every row shows and
-- changes the selected players, like the object rows a selection (with none selected: the picked
-- player, Main.selectedPlayer, the one the list shows last):
--   Pos / Rot:  the group's center from the dojo center, and the picked player's rotation (the group
--               turns as one around its center), placeholders the current values also in mods without
--               positions. Saved as the engageplayerpos / engageplayerrot gamerules (utils/players.lua)
--   Scale:      the size compared to the default body (Players.size), a typed size scales them to it
--   Density:    the average body part density of the players, a typed value sets that average (all
--               parts of all of them scaled together, their ratios stay)
--   Strength:   the same for the average joint strength (neck 1 / knees 4 differences stay)
--   Friction / Bounce: the same for body parts and joints together
--   Model:      Reset puts them back on the default body (their player sections removed)
-- The Move / Rotate / Scale gizmos do the same in the world.
local Rows = MGE.EditorRows
local inwuts = Rows.inputs
local readInputs = Rows.readInputs
local createInputRow = Rows.createInputRow

local NOT_SET = { "-", "-", "-" }

---Value as a placeholder: three significant digits, small densities like 0.0001 still readable
---@param v number
---@return string
local function hint(v)
    return string.format("%.3g", v)
end

---Angles as whole-degree placeholders: engageplayerrot keeps whole degrees (Players.wholeDegrees)
---@param values number[]
---@return string[]
local function wholeHints(values)
    local hints = {}
    for i = 1, 3 do hints[i] = tostring(MGE.Players.wholeDegrees(values[i])) end
    return hints
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

-- Pos / Rot / Scale names by gizmo tool, the active one lit like the Core tab's (rebuilt with the rows)
local gizmoLabels, highlightGizmoLabels = Rows.gizmoLabels()

---Pos / Rot / Scale rows for the players, rebuilt when the selection, the gamerules or the mod change
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
        posHelp = "Center of " .. whom(list) .. " from the\ndojo center, they move together."
        rotHelp = "Player " .. list[1] .. "'s rotation, the others turn\nwith it around the group's center."
    else
        posHelp = "Center of " .. whom(list) .. " from the dojo center."
        rotHelp = "Rotation of " .. whom(list) .. " in whole degrees."
    end
    local _
    inwuts.playerPos, _, gizmoLabels.move = createInputRow("Pos", holder, function(_, i)
        if #list > 0 then Players.setShownPos(list, readInputs(inwuts.playerPos, i)) end
    end, pos or NOT_SET, posHelp) -- numbers: shown rounded, the wheel steps from the exact center
    inwuts.playerRot, _, gizmoLabels.rotate = createInputRow("Rot", holder, function(_, i)
        if #list > 0 then Players.setShownRot(list, readInputs(inwuts.playerRot, i)) end
    end, rot and wholeHints(rot) or NOT_SET, rotHelp, nil, { whole = true, angle = true })
    -- Scale: the size compared to the default body (Players.size), a typed size scales to it (several
    -- players: their average, the differences stay). Rebuilt with Pos / Rot so it shows the new size
    local size = #list > 0 and Players.groupSize(list) or nil
    inwuts.playerScale, _, gizmoLabels.scale = createInputRow("Scale", holder, function()
        local typed = tonumber(inwuts.playerScale[1].textfieldstr[1])
        if not typed or typed <= 0 or not size or size <= 0 then return end
        Players.scaleBy(list, typed / size)
    end, { size or "-" }, "Size of " .. whom(list) .. " (default body 1).\nBigger is heavier.")
    highlightGizmoLabels()
end

-- part rows: input name, label, mod line, help
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
        -- 3 significant digits (small densities stay readable), the wheel steps from the exact average
        end, { #list > 0 and { text = hint(current), value = current } or "-" }, row[4])
    end
end

---Model row, built once: Reset puts the panel's players back on the default body
---@param holder UIElement
local function buildModel(holder)
    Rows.begin()
    Rows.createToggleButtonRow("Model", holder, {
        { label = "Reset", active = false, onClick = function() MGE.PlayerList.resetModels(panelPlayers()) end },
    }, "Back to the default body (one undo step).")
end

---@type EditorPanelModule
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
