local FileHandler = MGE.FileHandler

---@enum FLAGS
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
---Values returned by get_obj_shape
---@enum SHAPE
local SHAPE = {
    SPHERE = 0,
    BOX = 1,
    CAPSULE = 2,
}

---@class FreeIdHolder
---@field nonStatic integer[]
---@field static integer[]

---@alias IdPool "static"|"nonStatic"

---@class ModData
---@field parsed FileParserResult
---@field freeIds FreeIdHolder
---@field jointIds table<integer, boolean> object ids linked to a joint
local ModData = {}

local MAX_ENV_OBJECTS = 256
local MAX_NONSTATIC_OBJECTS = 48
local MAX_ENV_JOINTS = 24 -- env_obj_joint ids 1-24

---Shallow copy, used for props and object tables
---@generic T: table
---@param t T
---@return T
function ModData.copy(t)
    local copy = {}
    for k, v in pairs(t or {}) do copy[k] = v end
    return copy
end

---@return FileParserEnvObj[]
function ModData.getSelected()
    local selected = {}
    for _, obj in ipairs(ModData.parsed.env_obj) do
        if obj.selected then table.insert(selected, obj) end
    end
    return selected
end

---Objects are kept in id order, call after adding objects or changing ids
function ModData.sortObjects()
    table.sort(ModData.parsed.env_obj, function(a, b) return a.id < b.id end)
end

---Static objects need ids above MAX_NONSTATIC_OBJECTS. Static is the 8 bit of flag, other bits
---(ungrippable, shield...) don't make an object static.
---@param obj FileParserEnvObj
---@param loaded boolean? object is in the world, a missing flag line is read from the game
---@return boolean
function ModData.isStatic(obj, loaded)
    local flag = tonumber(obj.props.flag)
    if flag == nil and loaded then flag = get_obj_flag(obj.id - 1) end
    if flag == nil then return true end -- unknown (asset without a flag line), the safer id pool
    return bit.band(flag, FLAGS.STATIC) ~= 0
end

---Id pool an object belongs to: static objects take ids above 48, dynamic and joint-linked ones 1-48
---@param obj FileParserEnvObj
---@param loaded boolean? see isStatic
---@param jointIds table<integer, boolean>? joint-linked ids, defaults to the mod's
---@return IdPool
function ModData.idPool(obj, loaded, jointIds)
    if ModData.isStatic(obj, loaded) and not (jointIds or ModData.jointIds)[obj.id] then return "static" end
    return "nonStatic"
end

---Objects that need a dynamic id (1-MAX_NONSTATIC_OBJECTS): dynamic ones and joint-linked ones.
---Static objects on low ids aren't counted, freeDynamicIds moves them when the ids are needed.
---@return integer
function ModData.countDynamic()
    local count = 0
    for _, obj in ipairs(ModData.parsed.env_obj) do
        if ModData.idPool(obj, true) == "nonStatic" then count = count + 1 end
    end
    return count
end

---Makes room for dynamic objects: moves static objects off ids 1-MAX_NONSTATIC_OBJECTS to free
---static ids until `count` dynamic ids are free. Ids only change when needed. Objects linked to
---joints stay. Without opts.partial nothing moves unless enough ids can be freed.
---@param count integer dynamic ids needed in total (math.huge with partial = free all possible)
---@param opts { keep: table<integer, boolean>?, reserveStatic: integer?, partial: boolean? }?
---  keep: ids that must not move, reserveStatic: static ids the caller still needs
---@return boolean enough, integer moved
function ModData.freeDynamicIds(count, opts)
    opts = opts or {}
    local free = ModData.freeIds
    local missing = count - #free.nonStatic
    if missing <= 0 then return true, 0 end

    local candidates = {}
    for _, obj in ipairs(ModData.parsed.env_obj) do
        if obj.id <= MAX_NONSTATIC_OBJECTS and not (opts.keep and opts.keep[obj.id])
            and ModData.idPool(obj, true) == "static" then
            table.insert(candidates, obj)
        end
    end
    -- highest low ids first, the lowest ones are the most likely to be used as dynamic later
    table.sort(candidates, function(a, b) return a.id > b.id end)
    local available = math.min(#candidates, #free.static - (opts.reserveStatic or 0))
    if available < missing and not opts.partial then return false, 0 end

    local moved = 0
    for i = 1, math.min(available, missing) do
        local obj = candidates[i]
        -- the game flag is read by id, keep it in the file before the id changes
        if obj.props.flag == nil then obj.props.flag = tostring(get_obj_flag(obj.id - 1) or FLAGS.STATIC) end
        table.insert(free.nonStatic, obj.id)
        obj.id = table.remove(free.static, 1)
        moved = moved + 1
    end
    table.sort(free.nonStatic)
    ModData.sortObjects()
    return #free.nonStatic >= count, moved
end

local function getJointIds(joints)
    local ids = {}
    for _, joint in ipairs(joints or {}) do
        if joint.obj1 then ids[joint.obj1] = true end
        if joint.obj2 then ids[joint.obj2] = true end
    end
    return ids
end

local function init()
    ModData.parsed = { env_obj = {}, env_obj_joint = {}, ignores = {} }
    ModData.freeIds = { nonStatic = {}, static = {} }
    ModData.jointIds = {}
end

---Re-reads the loaded mod file and finds free object ids in the world
function ModData.reloadObjects()
    init()

    if MGE.modPath then
        ModData.parsed = FileHandler.ParseMod(MGE.modFolder .. MGE.modPath)
        ModData.jointIds = getJointIds(ModData.parsed.env_obj_joint)
    else
        print("Mod not found")
    end

    -- free ids come from the world, also without a mod file, otherwise imports have no ids to use
    for i = 0, MAX_ENV_OBJECTS - 1 do
        if get_obj_pos(i) == nil then
            local pool = i >= MAX_NONSTATIC_OBJECTS and ModData.freeIds.static or ModData.freeIds.nonStatic
            table.insert(pool, i + 1)
        end
    end
    print("Mod data updated")
end

init() --initialize data on load

-- shared with other modules
MGE.ModData = ModData
MGE.FLAGS = FLAGS
MGE.SHAPE = SHAPE
MGE.MAX_ENV_OBJECTS = MAX_ENV_OBJECTS
MGE.MAX_NONSTATIC_OBJECTS = MAX_NONSTATIC_OBJECTS
MGE.MAX_ENV_JOINTS = MAX_ENV_JOINTS
-- smallest object side MGE writes, zero sized objects crash the physics engine
MGE.MIN_SIDE = 0.0001
