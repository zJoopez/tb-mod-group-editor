-- Undo/redo for mod edits. Stores copies of ModData.parsed taken after each change (History.commit).
-- Live edits (pos/rot/scale/color) are restored directly on world objects, structural changes
-- (duplicate/delete/import/reindex) are restored by saving and reloading the mod.

local ModData = MGE.ModData

---@class History
---@field states FileParserResult[]
---@field index integer current state in states
---@field limit integer max stored states
local History = {
    states = {},
    index = 0,
    limit = 20,
}

---@param obj FileParserEnvObj|FileParserEnvObjJoint
local function copyObject(obj)
    local copy = ModData.copy(obj)
    copy.props = ModData.copy(obj.props)
    -- lines, ignores and trailer are never modified after parsing (only replaced), safe to share
    return copy
end

---@param parsed FileParserResult
---@return FileParserResult
local function copyParsed(parsed)
    local copy = { ignores = parsed.ignores, trailer = parsed.trailer, env_obj = {}, env_obj_joint = {} }
    for i, obj in ipairs(parsed.env_obj or {}) do copy.env_obj[i] = copyObject(obj) end
    for i, obj in ipairs(parsed.env_obj_joint or {}) do copy.env_obj_joint[i] = copyObject(obj) end
    return copy
end

-- object props applyLive can set on world objects, any other prop difference needs a save.
-- flag is live except for the static bit (see sameObjects)
local LIVE_KEYS = {
    pos = true, rot = true, sides = true, color = true, mass = true, bounce = true, flag = true, visible = true,
}

---@param props table<string, string>
---@return boolean
local function isStaticFlag(props)
    return bit.band(tonumber(props.flag) or 0, MGE.FLAGS.STATIC) ~= 0
end

---Same keys, and same values except for keys in `live` (those can be set on world objects).
---A live key that exists on one side only still counts as a difference: applyLive can only set
---values, it can't take a prop away (e.g. bounce added to an object that had none would stay on
---the world object after undo, leaving the world out of sync with the mod file)
---@param a table<string, string>
---@param b table<string, string>
---@param live table<string, boolean>?
local function sameProps(a, b, live)
    for key, value in pairs(a) do
        if b[key] == nil then return false end
        if not (live and live[key]) and b[key] ~= value then return false end
    end
    for key in pairs(b) do
        if a[key] == nil then return false end
    end
    return true
end

---True when only live-applicable changes differ, so undo can skip saving
---@param a FileParserResult
---@param b FileParserResult
---@return boolean
local function sameObjects(a, b)
    if #a.env_obj ~= #b.env_obj or #a.env_obj_joint ~= #b.env_obj_joint then return false end
    -- player model replaced (FileHandler.setPlayerLines swaps these tables), needs a reload
    if a.ignores ~= b.ignores or a.trailer ~= b.trailer then return false end
    for i, obj in ipairs(a.env_obj) do
        local other = b.env_obj[i]
        if obj.id ~= other.id or not sameProps(obj.props, other.props, LIVE_KEYS) then return false end
        -- tested in game: set_obj_flag doesn't switch static/dynamic, only a reload does
        if isStaticFlag(obj.props) ~= isStaticFlag(other.props) then return false end
    end
    -- joints can't be changed live, any difference in them needs a save
    for i, obj in ipairs(a.env_obj_joint) do
        local other = b.env_obj_joint[i]
        if obj.id ~= other.id or obj.obj1 ~= other.obj1 or obj.obj2 ~= other.obj2 or
            not sameProps(obj.props, other.props) then return false end
    end
    return true
end

---@param value string?
---@return number[]
local function parseNumbers(value)
    local numbers = {}
    for n in tostring(value or ""):gmatch("%S+") do table.insert(numbers, tonumber(n) or 0) end
    return numbers
end

---Applies pos/rot/sides/color/mass/bounce/flag/visible from props to the world objects, used when only
---live edits differ
---@param parsed FileParserResult
local function applyLive(parsed)
    for _, obj in ipairs(parsed.env_obj) do
        local id = obj.id - 1
        if get_obj_pos(id) ~= nil then
            local p = obj.props
            if p.pos then
                local v = parseNumbers(p.pos)
                set_obj_pos(id, v[1] or 0, v[2] or 0, v[3] or 0)
            end
            if p.rot then
                local v = parseNumbers(p.rot)
                set_obj_rot(id, math.rad(v[1] or 0), math.rad(v[2] or 0), math.rad(v[3] or 0))
            end
            if p.sides then
                local cur = { get_obj_sides(id) }
                local v = parseNumbers(p.sides)
                local s = {}
                for i = 1, 3 do
                    -- zero sides crash physics (old saves wrote 0.0001 as 0.00)
                    s[i] = math.max(math.abs(v[i] or cur[i] or 1), MGE.MIN_SIDE)
                end
                set_obj_sides(id, s[1], s[2], s[3])
            end
            if p.color then
                local v = parseNumbers(p.color)
                set_obj_color(id, v[1] or 1, v[2] or 1, v[3] or 1, v[4] or 1)
            end
            if p.mass then
                set_obj_mass(id, math.max(tonumber(p.mass) or 1, 0.0001)) -- zero mass breaks physics
            end
            if p.bounce then
                set_obj_bounce(id, math.max(tonumber(p.bounce) or 0, 0))
            end
            if p.flag then
                set_obj_flag(id, tonumber(p.flag) or 0)
            end
            if p.visible then
                set_obj_vis(id, tonumber(p.visible) or 1)
            end
        end
    end
end

---Starts a new history from the current mod data, call after loading a mod
function History.reset()
    History.states = { copyParsed(ModData.parsed) }
    History.index = 1
end

---Stores the current mod data as a new state, call after each change
function History.commit()
    for i = #History.states, History.index + 1, -1 do
        table.remove(History.states, i) -- new change drops redo states
    end
    table.insert(History.states, copyParsed(ModData.parsed))
    if #History.states > History.limit then
        table.remove(History.states, 1)
    end
    History.index = #History.states
end

---@param index integer
local function restore(index)
    local state = History.states[index]
    if not state then return end
    History.index = index
    local current = ModData.parsed
    ModData.parsed = copyParsed(state) -- copy so later edits don't change the stored state

    -- selection isn't part of history, keep what is selected now
    local selected = {}
    for _, obj in ipairs(current.env_obj) do selected[obj.id] = obj.selected end
    for _, obj in ipairs(ModData.parsed.env_obj) do obj.selected = selected[obj.id] end

    if sameObjects(current, ModData.parsed) then
        applyLive(ModData.parsed)
        -- refreshes the list and the editor's current values, typed inputs stay for the next edit
        local Main = MGE.Main -- created after this module loads
        if Main then Main.updateWindow() end
    else
        MGE.save() -- object list changed, rewrite file and reload
    end
end

function History.canUndo() return History.index > 1 end
function History.canRedo() return History.index < #History.states end

function History.undo()
    if not History.canUndo() then
        print("nothing to undo")
        return
    end
    restore(History.index - 1)
end

function History.redo()
    if not History.canRedo() then
        print("nothing to redo")
        return
    end
    restore(History.index + 1)
end

MGE.History = History
