








local Rows = MGE.EditorRows
local ModData = MGE.ModData
local History = MGE.History
local inputs = Rows.inputs
local sharedChoice = Rows.sharedChoice


local EDITED = { shape = true, pos = true, rot = true, sides = true, color = true, no_depth = true,
    min_level = true, max_level = true }




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
        "Lowest and highest graphics level it's drawn at\n(0-2): keeps detail off slower computers.", nil, { whole = true })

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
    }, "Lines MGE doesn't edit (count, randompos, parent...),\nsaved as they are.")
end


return {
    blocks = { { name = "atmoProps", build = buildAtmoProps, panel = "atmo", row = 0, rows = 3 } },
    inputs = { rebuilt = { "atmoLevels" } },
}
