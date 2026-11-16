local FileHandler = MGE.FileHandler


local FLAGS = {
    NORMAL = 0,
    ALT = 1,
    SHIELD = 2,
    WEAPON = 6,
    STATIC = 8,
    UNGRIPPABLE = 16,
    DQ_DISABLE = 32,
    NO_DAMAGE = 64
}


local SHAPE = {
    SPHERE = 0,
    BOX = 1,
    CAPSULE = 2,
}











local ModData = {}

local MAX_ENV_OBJECTS = 256
local MAX_NONSTATIC_OBJECTS = 48
local MAX_ENV_JOINTS = 24





function ModData.copy(t)
    local copy = {}
    for k, v in pairs(t or {}) do copy[k] = v end
    return copy
end







function ModData.clickSelect(obj, additive)
    if additive then
        obj.selected = not obj.selected or nil
        return obj.selected == true
    end
    local onlySelected = obj.selected

    local list = obj.kind == "atmo" and (ModData.parsed.atmo or {}) or ModData.parsed.env_obj
    for _, other in ipairs(list) do
        if other ~= obj and other.selected then onlySelected = false end
        other.selected = nil
    end
    obj.selected = not onlySelected or nil
    return obj.selected == true
end




function ModData.getEditSelection()
    if MGE.Main and MGE.Main.listTab == "atmo" then return ModData.getSelectedAtmo() end
    return ModData.getSelected()
end



function ModData.getSelectedAtmo()
    local selected = {}
    for _, obj in ipairs(ModData.parsed.atmo or {}) do
        if obj.selected then table.insert(selected, obj) end
    end
    return selected
end


function ModData.getSelected()
    local selected = {}
    for _, obj in ipairs(ModData.parsed.env_obj) do
        if obj.selected then table.insert(selected, obj) end
    end
    return selected
end


function ModData.sortObjects()
    table.sort(ModData.parsed.env_obj, function(a, b) return a.id < b.id end)
end






function ModData.isStatic(obj, loaded)
    local flag = tonumber(obj.props.flag)
    if flag == nil and loaded then flag = get_obj_flag(obj.id - 1) end
    if flag == nil then return true end
    return bit.band(flag, FLAGS.STATIC) ~= 0
end






function ModData.idPool(obj, loaded, jointIds)
    if ModData.isStatic(obj, loaded) and not (jointIds or ModData.jointIds)[obj.id] then return "static" end
    return "nonStatic"
end




local function getJointIds(joints)
    local ids = {}
    for _, joint in ipairs(joints or {}) do
        if joint.obj1 then ids[joint.obj1] = true end
        if joint.obj2 then ids[joint.obj2] = true end
    end
    return ids
end









local function rangeOf(id)
    return id <= MAX_NONSTATIC_OBJECTS and "nonStatic" or "static"
end



function ModData.releaseId(id)
    local list = ModData.freeIds[rangeOf(id)]
    table.insert(list, id)
    table.sort(list)
end



function ModData.freeCount()
    return #ModData.freeIds.static + #ModData.freeIds.nonStatic
end



function ModData.countDynamic()
    local count = 0
    for _, obj in ipairs(ModData.parsed.env_obj) do
        if ModData.idPool(obj, true) == "nonStatic" then count = count + 1 end
    end
    return count
end



function ModData.countMisplaced()
    local count = 0
    for _, obj in ipairs(ModData.parsed.env_obj) do
        if obj.id > MAX_NONSTATIC_OBJECTS and ModData.idPool(obj, true) == "nonStatic" then count = count + 1 end
    end
    return count
end




local function changeId(obj, id)
    if obj.props.flag == nil then obj.props.flag = tostring(get_obj_flag(obj.id - 1) or FLAGS.STATIC) end
    obj.id = id
end





local function freeLowIds(count)
    local free = ModData.freeIds
    local missing = count - #free.nonStatic
    if missing <= 0 then return true end

    local candidates = {}
    for _, obj in ipairs(ModData.parsed.env_obj) do
        if obj.id <= MAX_NONSTATIC_OBJECTS and ModData.idPool(obj, true) == "static" then
            table.insert(candidates, obj)
        end
    end
    if math.min(#candidates, #free.static) < missing then return false end
    table.sort(candidates, function(a, b) return a.id > b.id end)
    for i = 1, missing do
        local obj = candidates[i]
        table.insert(free.nonStatic, obj.id)
        changeId(obj, table.remove(free.static, 1))
    end
    table.sort(free.nonStatic)
    ModData.sortObjects()
    return true
end






function ModData.allocateIds(plans)
    local free = ModData.freeIds
    local total = #free.nonStatic + #free.static
    if #plans > total then
        MGE.say("Not enough object ids: " .. #plans .. " needed, " .. total .. " free")
        return nil
    end
    local linkedCount = 0
    for _, plan in ipairs(plans) do
        if plan.linked then linkedCount = linkedCount + 1 end
    end
    if not freeLowIds(linkedCount) then
        MGE.say("Not enough ids 1-" .. MAX_NONSTATIC_OBJECTS .. " for objects linked by joints: " .. linkedCount ..
            " needed, " .. #free.nonStatic .. " free")
        return nil
    end

    local ids = {}
    for i, plan in ipairs(plans) do
        if plan.linked then ids[i] = table.remove(free.nonStatic, 1) end
    end
    for i, plan in ipairs(plans) do
        if not plan.linked then
            if #free[plan.pool] > 0 then
                ids[i] = table.remove(free[plan.pool], 1)
            elseif plan.pool == "static" then
                ids[i] = table.remove(free.nonStatic)
            else
                ids[i] = table.remove(free.static, 1)
            end
        end
    end
    return ids
end






function ModData.reindex()
    local free = ModData.freeIds
    local highDynamic, lowStatic = {}, {}

    for _, obj in ipairs(ModData.parsed.env_obj) do
        local pool = ModData.idPool(obj, true)
        if pool == "nonStatic" and obj.id > MAX_NONSTATIC_OBJECTS then
            table.insert(highDynamic, obj)
        elseif pool == "static" and obj.id <= MAX_NONSTATIC_OBJECTS then
            table.insert(lowStatic, obj)
        end
    end
    table.sort(highDynamic, function(a, b) return a.id < b.id end)
    table.sort(lowStatic, function(a, b) return a.id > b.id end)

    local idMap = {}
    local function move(obj, id)
        idMap[obj.id] = id
        changeId(obj, id)
    end
    local left = 0
    for _, obj in ipairs(highDynamic) do
        local oldId = obj.id
        if #free.nonStatic > 0 then
            move(obj, table.remove(free.nonStatic, 1))
            table.insert(free.static, oldId)
        elseif #lowStatic > 0 then
            local static = table.remove(lowStatic, 1)
            local lowId = static.id
            move(static, oldId)
            move(obj, lowId)
        else
            left = left + 1
        end
    end
    table.sort(free.static)
    for _, obj in ipairs(lowStatic) do
        if #free.static == 0 then break end
        table.insert(free.nonStatic, obj.id)
        move(obj, table.remove(free.static, 1))
    end
    table.sort(free.nonStatic)

    local moved = 0
    for _ in pairs(idMap) do moved = moved + 1 end
    for _, joint in ipairs(ModData.parsed.env_obj_joint) do
        joint.obj1 = idMap[joint.obj1] or joint.obj1
        joint.obj2 = idMap[joint.obj2] or joint.obj2
    end
    ModData.jointIds = getJointIds(ModData.parsed.env_obj_joint)
    ModData.sortObjects()
    return moved, left
end



function ModData.refreshJointIds()
    ModData.jointIds = getJointIds(ModData.parsed.env_obj_joint)
end







local function splitPath(path)
    local parts = {}
    for part in tostring(path or ""):gmatch("[^/\\]+") do table.insert(parts, part) end
    return parts
end







function ModData.toModelName(model, modPath)
    return string.rep("../", #splitPath(modPath) > 0 and #splitPath(modPath) or 1) .. model
end






function ModData.parsedFor(path)
    if #splitPath(path) <= 1 then return ModData.parsed end
    local copy = {}
    for k, v in pairs(ModData.parsed) do copy[k] = v end
    copy.env_obj = {}
    for i, obj in ipairs(ModData.parsed.env_obj) do
        local model = obj.props.use_model == "1" and ModData.fromModelName(obj.props.model_name, MGE.outputName)
        if model then
            local o = {}
            for k, v in pairs(obj) do o[k] = v end
            o.props = {}
            for k, v in pairs(obj.props) do o.props[k] = v end
            o.props.model_name = ModData.toModelName(model, path)
            copy.env_obj[i] = o
        else
            copy.env_obj[i] = obj
        end
    end
    return copy
end





function ModData.fromModelName(modelName, modPath)
    if not modelName or modelName == "" then return nil end

    local parts = splitPath(modPath)
    if #parts > 0 then parts[#parts] = parts[#parts]:gsub("%.tbm$", "") else parts = { "mod" } end
    for _, part in ipairs(splitPath(modelName)) do
        if part == ".." then
            if #parts == 0 then return nil end
            table.remove(parts)
        elseif part ~= "." then
            table.insert(parts, part)
        end
    end
    return table.concat(parts, "/")
end




local function rebaseModels()
    if not tostring(MGE.modPath or ""):find("[/\\]") then return end
    for _, obj in ipairs(ModData.parsed.env_obj) do
        if obj.props.use_model == "1" then
            local model = ModData.fromModelName(obj.props.model_name, MGE.modPath)
            if model then obj.props.model_name = ModData.toModelName(model) end
        end
    end
end

local function init()
    ModData.parsed = { env_obj = {}, env_obj_joint = {}, atmo = {}, ignores = {} }
    ModData.freeIds = { nonStatic = {}, static = {} }
    ModData.jointIds = {}
end




function ModData.reloadObjects()
    local atmo = ModData.parsed and ModData.parsed.atmo or {}
    init()

    if MGE.modPath then
        ModData.parsed = FileHandler.ParseMod(MGE.modFolder .. MGE.modPath)


        local rules = get_game_rules and get_game_rules() or {}
        local count = math.max(tonumber(rules.numplayers) or 2, 1)
        FileHandler.splitSharedPlayers(ModData.parsed, count)
        rebaseModels()
        ModData.jointIds = getJointIds(ModData.parsed.env_obj_joint)
    elseif tostring(MGE.modName or ""):match("%.tbm$") then
        MGE.say("Mod not found")
    end
    ModData.parsed.atmo = atmo


    for i = 0, MAX_ENV_OBJECTS - 1 do
        if get_obj_pos(i) == nil then
            local pool = i >= MAX_NONSTATIC_OBJECTS and ModData.freeIds.static or ModData.freeIds.nonStatic
            table.insert(pool, i + 1)
        end
    end
    MGE.say("Mod data updated")
end

init()


MGE.ModData = ModData
MGE.FLAGS = FLAGS
MGE.SHAPE = SHAPE
MGE.MAX_ENV_OBJECTS = MAX_ENV_OBJECTS
MGE.MAX_NONSTATIC_OBJECTS = MAX_NONSTATIC_OBJECTS
MGE.MAX_ENV_JOINTS = MAX_ENV_JOINTS

MGE.MIN_SIDE = 0.0001


MGE.POS_ORIGIN = { 1, -0.1, 0 }
