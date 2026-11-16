




local ModData = MGE.ModData





local History = {
    states = {},
    index = 0,
    limit = 20,
}


local function copyObject(obj)
    local copy = ModData.copy(obj)
    copy.props = ModData.copy(obj.props)

    return copy
end



local function copyParsed(parsed)
    local copy = { ignores = parsed.ignores, trailer = parsed.trailer, env_obj = {}, env_obj_joint = {}, atmo = {},
        sharedPlayers = parsed.sharedPlayers }
    for i, obj in ipairs(parsed.env_obj or {}) do copy.env_obj[i] = copyObject(obj) end
    for i, obj in ipairs(parsed.env_obj_joint or {}) do copy.env_obj_joint[i] = copyObject(obj) end
    for i, obj in ipairs(parsed.atmo or {}) do copy.atmo[i] = copyObject(obj) end
    return copy
end



local LIVE_KEYS = {
    pos = true, rot = true, sides = true, color = true, mass = true, bounce = true, flag = true, visible = true,
}



local function isStaticFlag(props)
    return bit.band(tonumber(props.flag) or 0, MGE.FLAGS.STATIC) ~= 0
end








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





local function sameObjects(a, b)
    if #a.env_obj ~= #b.env_obj or #a.env_obj_joint ~= #b.env_obj_joint then return false end

    if a.ignores ~= b.ignores or a.trailer ~= b.trailer then return false end
    for i, obj in ipairs(a.env_obj) do
        local other = b.env_obj[i]
        if obj.id ~= other.id or not sameProps(obj.props, other.props, LIVE_KEYS) then return false end

        if isStaticFlag(obj.props) ~= isStaticFlag(other.props) then return false end
    end

    for i, obj in ipairs(a.env_obj_joint) do
        local other = b.env_obj_joint[i]
        if obj.id ~= other.id or obj.obj1 ~= other.obj1 or obj.obj2 ~= other.obj2 or
            not sameProps(obj.props, other.props) then return false end
    end


    return true
end
History.sameObjects = sameObjects



local function parseNumbers(value)
    local numbers = {}
    for n in tostring(value or ""):gmatch("%S+") do table.insert(numbers, tonumber(n) or 0) end
    return numbers
end




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

                    s[i] = math.max(math.abs(v[i] or cur[i] or 1), MGE.MIN_SIDE)
                end
                set_obj_sides(id, s[1], s[2], s[3])
            end
            if p.color then
                local v = parseNumbers(p.color)
                set_obj_color(id, v[1] or 1, v[2] or 1, v[3] or 1, v[4] or 1)
            end
            if p.mass then
                set_obj_mass(id, math.max(tonumber(p.mass) or 1, 0.0001))
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






History.mergeKey = nil

History.lastMerge = nil



function History.endMerge(key)
    if History.lastMerge == key then History.lastMerge = nil end
end


function History.reset()
    History.states = { copyParsed(ModData.parsed) }
    History.index = 1
    History.lastMerge = nil
end


function History.commit()
    local key = History.mergeKey
    if key and key == History.lastMerge and History.index == #History.states and History.index > 1 then
        History.states[History.index] = copyParsed(ModData.parsed)
        return
    end
    History.lastMerge = key
    for i = #History.states, History.index + 1, -1 do
        table.remove(History.states, i)
    end
    table.insert(History.states, copyParsed(ModData.parsed))
    if #History.states > History.limit then
        table.remove(History.states, 1)
    end
    History.index = #History.states
end


local function restore(index)
    local state = History.states[index]
    if not state then return end
    History.index = index
    History.lastMerge = nil
    local current = ModData.parsed
    ModData.parsed = copyParsed(state)


    local selected = {}
    for _, obj in ipairs(current.env_obj) do selected[obj.id] = obj.selected end
    for _, obj in ipairs(ModData.parsed.env_obj) do obj.selected = selected[obj.id] end
    local atmoSelected = {}
    for i, obj in ipairs(current.atmo or {}) do atmoSelected[i] = obj.selected end
    for i, obj in ipairs(ModData.parsed.atmo) do obj.selected = atmoSelected[i] end

    if sameObjects(current, ModData.parsed) then
        applyLive(ModData.parsed)

        local Main = MGE.Main
        if Main then Main.updateWindow() end
    else
        MGE.apply()
    end
end

function History.canUndo() return History.index > 1 end
function History.canRedo() return History.index < #History.states end

function History.undo()
    if not History.canUndo() then
        MGE.say("nothing to undo")
        return
    end
    restore(History.index - 1)
end

function History.redo()
    if not History.canRedo() then
        MGE.say("nothing to redo")
        return
    end
    restore(History.index + 1)
end

MGE.History = History
