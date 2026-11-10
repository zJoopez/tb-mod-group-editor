-- Players panel (editor area on the Players list): the picked player's start position and rotation,
-- the engageplayerpos / engageplayerrot gamerules (utils/players.lua), and Resize for the selected
-- players' size. Like the Core tab's rows: placeholders show the current values, Enter in a field
-- applies it. The Move / Rotate / Scale gizmos do the same in the world.
local Rows = MGE.EditorRows
local inwuts = Rows.inputs
local readInputs = Rows.readInputs
local formatHints = Rows.formatHints
local createInputRow = Rows.createInputRow

local NOT_SET = { "-", "-", "-" }

---Pos and Rot rows for the picked player, rebuilt when the player or the gamerules change
---@param holder UIElement
local function buildPlayer(holder)
    Rows.begin()
    local Players = MGE.Players
    local player = MGE.Main.selectedPlayer
    local pos, rot = Players.getPos(player), Players.getRot(player)
    inwuts.playerPos = createInputRow("Pos", holder, function(_, i)
        Players.setValues(player, readInputs(inwuts.playerPos, i), nil)
    end, pos and formatHints(pos) or NOT_SET,
        "Player " .. player .. "'s start position (engageplayerpos).\n" ..
        "-: the mod doesn't set positions, the first change\n" ..
        "fills them in for every player where they are now.")
    inwuts.playerRot = createInputRow("Rot", holder, function(_, i)
        Players.setValues(player, nil, readInputs(inwuts.playerRot, i))
    end, rot and formatHints(rot) or NOT_SET,
        "Start rotation in degrees (engageplayerrot), turns\n" ..
        "around the head. The Rotate gizmo keeps the\n" ..
        "player's center in place instead.")
end

---Resize row: multiplies the selected players' size (all of them, a factor is relative), like the
---Scale gizmo's white cube. Built once, the typed factor stays to try again
---@param holder UIElement
local function buildResize(holder)
    Rows.begin()
    inwuts.playerScale = createInputRow("Resize", holder, function()
        local factor = tonumber(inwuts.playerScale[1].textfieldstr[1])
        if not factor or factor <= 0 then return end
        MGE.Players.scaleBy(MGE.Main.selectedPlayerList(), factor)
    end, { "1.00" },
        "Multiplies the selected players' size (body parts,\n" ..
        "joints and the distances between them), around\n" ..
        "their center. Density stays: bigger is heavier.")
end

---@type EditorPanelModule
return {
    fixed = { { build = buildResize, panel = "player", row = 2, rows = 1 } },
    blocks = { { name = "player", build = buildPlayer, panel = "player", row = 0, rows = 2 } },
    inputs = { fixed = { "playerScale" }, rebuilt = { "playerPos", "playerRot" } },
}
