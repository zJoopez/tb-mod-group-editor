
local Rows = MGE.EditorRows
local ModData = MGE.ModData
local History = MGE.History
local FileHandler = MGE.FileHandler
local getSelected = ModData.getSelected
local inwuts = Rows.inputs
local sharedChoice = Rows.sharedChoice
local createInputRow = Rows.createInputRow
local createChoiceRow = Rows.createChoiceRow












local THRUST_SPACES = {
    { label = "World", value = 0 },
    { label = "Object", value = 1 },
}

local THRUST_DEFAULT = { frames = 1, dir = { 0, 0, 0 }, space = 0 }



local function parseThrust(line)
    if not line then return nil end
    local n = {}
    for v in line:gmatch("%S+") do table.insert(n, tonumber(v) or 0) end
    return {
        frames = math.floor(n[1] or THRUST_DEFAULT.frames),
        dir = { n[2] or 0, n[3] or 0, n[4] or 0 },
        space = (n[5] or THRUST_DEFAULT.space) ~= 0 and 1 or 0,
    }
end



local function getThrust(obj)
    return parseThrust(obj.props.thrust)
end







local thrustBeforeOff = {}



local function rememberedThrust(obj)
    local kept = thrustBeforeOff[obj.id]
    if kept and kept.pos == obj.props.pos and kept.sides == obj.props.sides then return kept.thrust end
    return nil
end



local function formatThrust(thrust)
    return thrust.frames .. " " .. FileHandler.formatNumbers(thrust.dir[1], thrust.dir[2], thrust.dir[3]) ..
        " " .. thrust.space
end



local function editThrust(edit)
    local changed = false
    for _, v in ipairs(getSelected()) do
        local had = getThrust(v)

        local current = had or parseThrust(rememberedThrust(v)) or THRUST_DEFAULT
        local thrust = edit({ frames = current.frames, dir = { current.dir[1], current.dir[2], current.dir[3] },
            space = current.space })
        local value = thrust and formatThrust(thrust) or nil

        if value ~= (had and formatThrust(had) or nil) then
            if not value and had then
                thrustBeforeOff[v.id] = { thrust = formatThrust(had), pos = v.props.pos, sides = v.props.sides }
            elseif value then
                thrustBeforeOff[v.id] = nil
            end
            v.props.thrust = value
            changed = true
        end
    end
    if not changed then return end
    History.commit()
    MGE.apply()
end



local function setThrustField(index)
    local input = (inwuts.thrust or {})[index]
    local value = input and tonumber(input.textfieldstr[1])
    if not value then return end
    editThrust(function(thrust)
        if index == 1 then
            thrust.frames = math.max(1, math.floor(value + 0.5))
        else
            thrust.dir[index - 1] = value
        end
        return thrust
    end)
end





local function buildThrust(holder, selected)
    Rows.begin()
    local function shown(read)
        return sharedChoice(selected, function(obj) return read(getThrust(obj) or THRUST_DEFAULT) end)
    end
    local frames = shown(function(t) return tostring(t.frames) end) or tostring(THRUST_DEFAULT.frames)
    local dir = {}
    for i = 1, 3 do
        dir[i] = shown(function(t) return Rows.formatHint(t.dir[i]) end) or "0.00"
    end
    local framesInputs = createInputRow("Frames", holder, function() setThrustField(1) end, { frames },
        "Pushes every N frames, 1: every frame.", nil, { whole = true })
    local dirInputs = createInputRow("Direction", holder, function(_, i) setThrustField(i + 1) end, dir,
        "Push along the axes below. Turns thrust on if it's off.")
    inwuts.thrust = { framesInputs[1], dirInputs[1], dirInputs[2], dirInputs[3] }


    local choices = { { label = "Off", value = "off" } }
    for _, space in ipairs(THRUST_SPACES) do table.insert(choices, space) end
    local current = sharedChoice(selected, function(obj)
        local thrust = getThrust(obj)
        return thrust and thrust.space or "off"
    end)
    createChoiceRow("Axes", holder, choices, current, function(space)
        editThrust(function(thrust)
            if space == "off" then return nil end
            thrust.space = space
            return thrust
        end)
    end, "Off: no thrust. World: world axes.\nObject: turns with the object.")
end



return {
    blocks = { { name = "thrust", build = buildThrust, panel = "thrust", row = 0, rows = 3 } },
    inputs = { rebuilt = { "thrust" } },
}
