-- Atmo tab of the Atmo list (the atmo objects, utils/atmo_layer.lua and utils/atmo.lua): the lines atmos have
-- and objects don't, the lines MGE keeps without editing them, and the buttons:
--   Depth:    drawn over everything (no_depth 1), or normally
--   Graphics: the game's graphics levels it's drawn at, min and max (0 lowest - 2 highest)
--   Kept:     how many other lines the selected ones keep (count, randompos, rotate, parent...): written
--             back as they are, MGE draws such objects as their plain shape
--   To objects: the selected ones back into the game, ids allowing. Save atmo: writes the mod's .atmo now
-- The Atmo list's Core tab is the objects' Core (ui/editor_core.lua), on the selected atmo objects.
-- Atmo objects aren't in the .tbm: changes here are an undo step, no reload.
local Rows = MGE.EditorRows
local ModData = MGE.ModData
local History = MGE.History
local inputs = Rows.inputs
local sharedChoice = Rows.sharedChoice

-- the lines atmo objects use that MGE edits (the Core tab and this one): every other one is kept as it is
local EDITED = { shape = true, pos = true, rot = true, sides = true, color = true, no_depth = true,
    min_level = true, max_level = true }

---Writes a line on the selected atmo objects (nil: removes it), one undo step when one changed
---@param key string
---@param value string?
local function setLine(key, value)
    local changed = false
    for _, obj in ipairs(ModData.getSelectedAtmo()) do
        if obj.props[key] ~= value then
            obj.props[key] = value
            changed = true
        end
    end
    if not changed then return end
    History.commit()
    Rows.refreshProperties()
end

---Graphics row: the typed min / max levels (0-2), an empty field keeps each object's own. The game's
---defaults (0 and 2) aren't written
local function setLevels()
    local typed = Rows.readInputs(inputs.atmoLevels)
    local changed = false
    for _, obj in ipairs(ModData.getSelectedAtmo()) do
        for i, key in ipairs({ "min_level", "max_level" }) do
            local value = typed[i]
            if value then
                value = math.max(0, math.min(2, math.floor(value + 0.5)))
                local line = (value ~= (i == 1 and 0 or 2)) and tostring(value) or nil
                if obj.props[key] ~= line then
                    obj.props[key] = line
                    changed = true
                end
            end
        end
    end
    if not changed then return end
    History.commit()
    Rows.refreshProperties()
end

---Depth, Graphics and Kept rows, rebuilt with the selection
---@param holder UIElement
---@param selected FileParserEnvObj[] the selected atmo objects (ModData.getEditSelection on the Atmo list)
local function buildAtmoProps(holder, selected)
    Rows.begin()
    Rows.createChoiceRow("Depth", holder, {
        { label = "Normal", value = false },
        { label = "On top", value = true },
    }, sharedChoice(selected, function(obj) return obj.props.no_depth == "1" end),
        function(onTop) setLine("no_depth", onTop and "1" or nil) end,
        "On top: drawn over everything, even what's in front\n(no_depth 1).")
    local function level(key, default)
        return sharedChoice(selected, function(obj) return tostring(tonumber(obj.props[key]) or default) end)
            or tostring(default)
    end
    inputs.atmoLevels = Rows.createInputRow("Graphics", holder, setLevels, { level("min_level", 0), level("max_level", 2) },
        "The game's graphics levels it's drawn at, lowest\nand highest: 0 lowest, 2 highest. Players on other\n" ..
        "settings don't see it: a way to keep detail off\nslower computers.")
    -- the other lines (count, randompos, rotate, parent...): kept, not edited, not drawn as the game does
    local kept, keys = 0, {}
    for _, obj in ipairs(selected) do
        for key in pairs(obj.props) do
            if not EDITED[key] then
                kept = kept + 1
                keys[key] = true
            end
        end
    end
    local names = {}
    for key in pairs(keys) do names[#names + 1] = key end
    table.sort(names)
    Rows.createToggleButtonRow("Kept", holder, {
        { label = kept == 0 and "no other lines" or (kept .. " lines: " .. table.concat(names, ", ")), active = false,
            onClick = function() end },
    }, "Lines the selected ones have that MGE doesn't edit\n(count, randompos, rotate, parent...), and the\n" ..
        "object lines atmos skip (flag, mass...). Written back\nas they are; MGE draws such objects as their shape.")
end

---To objects and Save atmo, built once
---@param holder UIElement
local function buildButtons(holder)
    Rows.begin()
    Rows.createToggleButtonRow("", holder, {
        { label = "To objects", active = false, onClick = function() MGE.AtmoLayer.toObjects() end },
        { label = "Save atmo", active = false, onClick = function() MGE.AtmoLayer.exportAtmo() end },
    }, "To objects: the selected ones back into the game as\nobjects, as many as there are free ids.\n" ..
        "Save atmo: writes data/atmospheres/MGE - <mod>.atmo\nnow, without saving the mod (Save does both).")
end

---@type EditorPanelModule
return {
    fixed = { { build = buildButtons, panel = "atmo", row = 4, rows = 1 } },
    blocks = { { name = "atmoProps", build = buildAtmoProps, panel = "atmo", row = 0, rows = 3 } },
    inputs = { rebuilt = { "atmoLevels" } },
}
