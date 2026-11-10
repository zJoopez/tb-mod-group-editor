-- Thrust tab: Frames, Direction, Axes (World / Object / Off)
local Rows = MGE.EditorRows
local ModData = MGE.ModData
local History = MGE.History
local FileHandler = MGE.FileHandler
local getSelected = ModData.getSelected
local inwuts = Rows.inputs
local sharedChoice = Rows.sharedChoice
local createInputRow = Rows.createInputRow
local createChoiceRow = Rows.createChoiceRow

-- Thrust: "thrust <frames> <x> <y> <z> <space>" pushes the object along x y z every <frames> frames.
-- <space> picks the axes the direction uses. No line means no thrust. The game has no live thrust
-- setter, changes are applied by saving
---@class Thrust
---@field frames integer
---@field dir number[] x y z
---@field space integer see THRUST_SPACES

-- values of <space>
local THRUST_SPACES = {
    { label = "World", value = 1 },
    { label = "Object", value = 0 }, -- turns with the object
}
-- used for the parts of a thrust that an object doesn't have yet (turning it on, typing one field)
local THRUST_DEFAULT = { frames = 1, dir = { 0, 0, 0 }, space = 0 }

---@param obj FileParserEnvObj
---@return Thrust? nil when the object has no thrust
local function getThrust(obj)
    if not obj.props.thrust then return nil end
    local n = {}
    for v in obj.props.thrust:gmatch("%S+") do table.insert(n, tonumber(v) or 0) end
    return {
        frames = math.floor(n[1] or THRUST_DEFAULT.frames),
        dir = { n[2] or 0, n[3] or 0, n[4] or 0 },
        space = (n[5] or THRUST_DEFAULT.space) ~= 0 and 1 or 0,
    }
end

---@param thrust Thrust
---@return string
local function formatThrust(thrust)
    return thrust.frames .. " " .. FileHandler.formatNumbers(thrust.dir[1], thrust.dir[2], thrust.dir[3]) ..
        " " .. thrust.space
end

---Changes the thrust of every selected object and saves when any of them changed
---@param edit fun(thrust: Thrust): Thrust? gets a copy of the object's thrust (defaults when it has none), nil removes it
local function editThrust(edit)
    local changed = false
    for _, v in ipairs(getSelected()) do
        local had = getThrust(v)
        local current = had or THRUST_DEFAULT
        local thrust = edit({ frames = current.frames, dir = { current.dir[1], current.dir[2], current.dir[3] },
            space = current.space })
        local value = thrust and formatThrust(thrust) or nil
        -- compared as values, the file may write the same thrust differently ("1.00" / "1")
        if value ~= (had and formatThrust(had) or nil) then
            v.props.thrust = value
            changed = true
        end
    end
    if not changed then return end
    History.commit()
    MGE.apply()
end

---Applies a typed thrust field: 1 frames, 2-4 direction x y z
---@param index integer
local function setThrustField(index)
    local input = (inwuts.thrust or {})[index]
    local value = input and tonumber(input.textfieldstr[1])
    if not value then return end
    editThrust(function(thrust)
        if index == 1 then
            thrust.frames = math.max(1, math.floor(value + 0.5)) -- whole frames, 0 would never fire
        else
            thrust.dir[index - 1] = value
        end
        return thrust
    end)
end

---Thrust panel: frames, direction and its axes (or Off). Placeholders and highlights show the selection's
---values ("mixed" when they differ), objects without thrust show the defaults that typing a value gives
---@param holder UIElement
---@param selected FileParserEnvObj[]
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
        "Pushes every N frames, 1: every frame.")
    local dirInputs = createInputRow("Direction", holder, function(_, i) setThrustField(i + 1) end, dir,
        "Push along the axes below. Turns thrust on if it's off.")
    inwuts.thrust = { framesInputs[1], dirInputs[1], dirInputs[2], dirInputs[3] }

    -- the axes choices plus Off, objects without thrust count as Off
    local choices = {}
    for i, space in ipairs(THRUST_SPACES) do choices[i] = space end
    table.insert(choices, { label = "Off", value = "off" })
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
    end, "World: world axes. Object: turns with the object.\nOff: no thrust.")
end


---@type EditorPanelModule
return {
    blocks = { { name = "thrust", build = buildThrust, panel = "thrust", row = 0, rows = 3 } },
    inputs = { rebuilt = { "thrust" } },
}
