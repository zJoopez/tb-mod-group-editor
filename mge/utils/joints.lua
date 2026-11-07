-- Helpers for env_obj_joint blocks linked to selected objects.
-- There is no API to move env joints live, changes are stored in props and applied when the mod is saved.

---@class Joints
local Joints = {}
MGE.Joints = Joints
local ModData = MGE.ModData

---@param value string?
---@return number, number, number
local function parseVector(value)
    local x, y, z = tostring(value or ""):match("(%S+)%s+(%S+)%s+(%S+)")
    return tonumber(x) or 0, tonumber(y) or 0, tonumber(z) or 0
end

---@return string
local function formatVector(x, y, z)
    return MGE.FileHandler.formatNumbers(x, y, z)
end

---@param objects { id: integer }[]
---@return table<integer, boolean>
function Joints.idSet(objects)
    local set = {}
    for _, obj in ipairs(objects) do set[obj.id] = true end
    return set
end

---Joints whose both linked objects are in ids
---@param ids table<integer, boolean>
---@param joints FileParserEnvObjJoint[]?
---@return FileParserEnvObjJoint[]
function Joints.getLinked(ids, joints)
    local linked = {}
    for _, joint in ipairs(joints or ModData.parsed.env_obj_joint) do
        if ids[joint.obj1] and ids[joint.obj2] then
            table.insert(linked, joint)
        end
    end
    return linked
end

---Object ids that are linked to any joint in the list
---@param joints FileParserEnvObjJoint[]
---@return table<integer, boolean>
function Joints.getObjectIds(joints)
    local ids = {}
    for _, joint in ipairs(joints or {}) do
        ids[joint.obj1] = true
        ids[joint.obj2] = true
    end
    return ids
end

---Unused joint ids (1-MAX_ENV_JOINTS), lowest first
---@return integer[]
function Joints.freeIds()
    local used = {}
    for _, joint in ipairs(ModData.parsed.env_obj_joint) do
        if joint.id then used[joint.id] = true end
    end
    local free = {}
    for id = 1, MGE.MAX_ENV_JOINTS do
        if not used[id] then table.insert(free, id) end
    end
    return free
end

---Lowest unused joint id, nil when all MAX_ENV_JOINTS ids are taken
---@return integer?
function Joints.nextId()
    return Joints.freeIds()[1]
end

---Number of joints that copyLinked would add (both ends in ids)
---@param joints FileParserEnvObjJoint[]
---@param ids table<integer, boolean>
---@return integer
function Joints.countLinked(joints, ids)
    return #Joints.getLinked(ids, joints)
end

---Prints a message and returns false if `count` more joints don't fit the joint limit
---@param count integer
---@return boolean
function Joints.haveRoom(count)
    local free = #Joints.freeIds()
    if count <= free then return true end
    print("Not enough joints available: " .. count .. " needed, " .. free .. " free (max " .. MGE.MAX_ENV_JOINTS .. ")")
    return false
end

---Copy of a joint with new ids, props are copied so edits don't affect the original
---@param joint FileParserEnvObjJoint
---@param id integer
---@param obj1 integer
---@param obj2 integer
---@return FileParserEnvObjJoint
function Joints.copy(joint, id, obj1, obj2)
    local props = {}
    for k, v in pairs(joint.props) do props[k] = v end
    return { kind = "env_obj_joint", id = id, obj1 = obj1, obj2 = obj2, props = props, lines = joint.lines }
end

---Copies joints linked between objects in idMap (old id -> new id) and adds them to the mod
---@param joints FileParserEnvObjJoint[]
---@param idMap table<integer, integer>
---@return integer count
function Joints.copyLinked(joints, idMap)
    local count = 0
    for _, joint in ipairs(joints) do
        local obj1, obj2 = idMap[joint.obj1], idMap[joint.obj2]
        local id = Joints.nextId() -- callers check Joints.haveRoom first, nil only guards the limit
        if obj1 and obj2 and id then
            table.insert(ModData.parsed.env_obj_joint, Joints.copy(joint, id, obj1, obj2))
            count = count + 1
        end
    end
    return count
end

---Removes joints linked to any of the ids, used when objects are deleted
---@param ids table<integer, boolean>
function Joints.removeLinkedToAny(ids)
    local joints = ModData.parsed.env_obj_joint
    for i = #joints, 1, -1 do
        if ids[joints[i].obj1] or ids[joints[i].obj2] then
            table.remove(joints, i)
        end
    end
end

---Moves joint anchor: fn receives x, y, z and returns new x, y, z
---@param joint FileParserEnvObjJoint
---@param fn fun(x: number, y: number, z: number): number, number, number
function Joints.transformPos(joint, fn)
    if not joint.props.pos then return end
    joint.props.pos = formatVector(fn(parseVector(joint.props.pos)))
end

---Rotates joint axis direction: fn receives x, y, z and returns new x, y, z
---@param joint FileParserEnvObjJoint
---@param fn fun(x: number, y: number, z: number): number, number, number
function Joints.transformAxis(joint, fn)
    if not joint.props.axis then return end
    joint.props.axis = formatVector(fn(parseVector(joint.props.axis)))
end
