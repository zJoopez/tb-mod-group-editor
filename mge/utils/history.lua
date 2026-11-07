-- Undo/redo for mod edits. Stores copies of ModData.parsed taken after each change (History.commit).
-- Live edits (pos/rot/scale/color) are restored directly on world objects, structural changes
-- (duplicate/delete/import/reindex) are restored by saving and reloading the mod.

---@class History
---@field states FileParserResult[]
---@field index integer current state in states
---@field limit integer max stored states
local ModData = MGE.ModData

local History = {
    states = {},
    index = 0,
    limit = 20,
}

---@param obj FileParserEnvObj|FileParserEnvObjJoint
local function copyObject(obj)
    local copy = {}
    for k, v in pairs(obj) do copy[k] = v end
    copy.props = {}
    for k, v in pairs(obj.props or {}) do copy.props[k] = v end
    -- lines, ignores and trailer are never modified after parsing, safe to share
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

---@param a FileParserResult
---@param b FileParserResult
---@return boolean
local function sameObjects(a, b)
    if #a.env_obj ~= #b.env_obj or #a.env_obj_joint ~= #b.env_obj_joint then return false end
    for i, obj in ipairs(a.env_obj) do
        if obj.id ~= b.env_obj[i].id then return false end
    end
    for i, obj in ipairs(a.env_obj_joint) do
        local other = b.env_obj_joint[i]
        if obj.id ~= other.id or obj.obj1 ~= other.obj1 or obj.obj2 ~= other.obj2 or
            obj.props.pos ~= other.props.pos then return false end
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

---Applies pos/rot/sides/color from props to the world objects, used when only live edits differ
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
                set_obj_sides(id, v[1] or cur[1], v[2] or cur[2], v[3] or cur[3])
            end
            if p.color then
                local v = parseNumbers(p.color)
                set_obj_color(id, v[1] or 1, v[2] or 1, v[3] or 1, v[4] or 1)
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
        local Main = MGE.Main -- created after this module loads
        if Main then
            Main.updateWindow()
            Main.resetEditor()
        end
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
