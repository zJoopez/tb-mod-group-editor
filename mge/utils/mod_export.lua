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

---Usual click selection, for the object list and clicks in the world: a click selects only the
---clicked object (clicking the only selected one deselects it), Shift + click adds it to or removes
---it from the selection
---@param obj FileParserEnvObj
---@param additive boolean Shift held: toggle only this object
---@return boolean selected whether the clicked object ended up selected
function ModData.clickSelect(obj, additive)
    if additive then
        obj.selected = not obj.selected or nil
        return obj.selected == true
    end
    local onlySelected = obj.selected
    -- only the object's own layer: the objects and the atmo objects (the Atmo list) are selected apart
    local list = obj.kind == "atmo" and (ModData.parsed.atmo or {}) or ModData.parsed.env_obj
    for _, other in ipairs(list) do
        if other ~= obj and other.selected then onlySelected = false end
        other.selected = nil
    end
    obj.selected = not onlySelected or nil
    return obj.selected == true
end

---What the editor's rows, the gizmo and the transforms work on: the selected atmo objects while the
---Atmo list shows, otherwise the selected objects
---@return FileParserEnvObj[]
function ModData.getEditSelection()
    if MGE.Main and MGE.Main.listTab == "atmo" then return ModData.getSelectedAtmo() end
    return ModData.getSelected()
end

---Selected atmo objects (utils/atmo_layer.lua). getSelected has only the objects in the game
---@return FileParserEnvObj[]
function ModData.getSelectedAtmo()
    local selected = {}
    for _, obj in ipairs(ModData.parsed.atmo or {}) do
        if obj.selected then table.insert(selected, obj) end
    end
    return selected
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

---Object ids linked to any of the joints
---@param joints FileParserEnvObjJoint[]?
---@return table<integer, boolean>
local function getJointIds(joints)
    local ids = {}
    for _, joint in ipairs(joints or {}) do
        if joint.obj1 then ids[joint.obj1] = true end
        if joint.obj2 then ids[joint.obj2] = true end
    end
    return ids
end

-- Id rules: only joints strictly need ids 1-MAX_NONSTATIC_OBJECTS (the game ignores joints to higher
-- ids). Dynamic objects can sit on any id, above 48 the game treats them partly as static, so they
-- only prefer low ids and the window warns until Reindex moves them down. Ids only change on
-- Reindex, or when joint-linked copies need low ids that static objects hold.

---Free id list an id belongs to
---@param id integer
---@return IdPool
local function rangeOf(id)
    return id <= MAX_NONSTATIC_OBJECTS and "nonStatic" or "static"
end

---Returns an id to the free lists, e.g. after deleting its object
---@param id integer
function ModData.releaseId(id)
    local list = ModData.freeIds[rangeOf(id)]
    table.insert(list, id)
    table.sort(list)
end

---Objects that should be on ids 1-MAX_NONSTATIC_OBJECTS: dynamic ones and joint-linked ones
---@return integer
function ModData.countDynamic()
    local count = 0
    for _, obj in ipairs(ModData.parsed.env_obj) do
        if ModData.idPool(obj, true) == "nonStatic" then count = count + 1 end
    end
    return count
end

---Dynamic objects above id MAX_NONSTATIC_OBJECTS, treated partly as static by the game until Reindex
---@return integer
function ModData.countMisplaced()
    local count = 0
    for _, obj in ipairs(ModData.parsed.env_obj) do
        if obj.id > MAX_NONSTATIC_OBJECTS and ModData.idPool(obj, true) == "nonStatic" then count = count + 1 end
    end
    return count
end

---Gives obj a new id. The game flag is read by id, so a missing flag line is written first
---@param obj FileParserEnvObj
---@param id integer
local function changeId(obj, id)
    if obj.props.flag == nil then obj.props.flag = tostring(get_obj_flag(obj.id - 1) or FLAGS.STATIC) end
    obj.id = id
end

---Frees ids 1-MAX_NONSTATIC_OBJECTS for joint-linked objects by moving static objects on low ids to
---free high ids (highest low ids first). Nothing moves unless `count` low ids can be freed
---@param count integer low ids needed in total
---@return boolean enough
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

---Picks ids for new objects (duplicate, import), all or nothing. Joint-linked objects get ids
---1-MAX_NONSTATIC_OBJECTS (static objects are moved up when needed), the others take their preferred
---range when it has free ids, otherwise any free id. Prints why when they don't fit
---@param plans { pool: IdPool, linked: boolean }[] one per new object, pool is the preferred range
---@return integer[]? ids same order as plans
function ModData.allocateIds(plans)
    local free = ModData.freeIds
    local total = #free.nonStatic + #free.static
    if #plans > total then
        print("Not enough object ids: " .. #plans .. " needed, " .. total .. " free")
        return nil
    end
    local linkedCount = 0
    for _, plan in ipairs(plans) do
        if plan.linked then linkedCount = linkedCount + 1 end
    end
    if not freeLowIds(linkedCount) then
        print("Not enough ids 1-" .. MAX_NONSTATIC_OBJECTS .. " for objects linked by joints: " .. linkedCount ..
            " needed, " .. #free.nonStatic .. " free")
        return nil
    end

    local ids = {}
    for i, plan in ipairs(plans) do -- joint-linked first, they can't use the other range
        if plan.linked then ids[i] = table.remove(free.nonStatic, 1) end
    end
    for i, plan in ipairs(plans) do
        if not plan.linked then
            if #free[plan.pool] > 0 then
                ids[i] = table.remove(free[plan.pool], 1)
            elseif plan.pool == "static" then
                ids[i] = table.remove(free.nonStatic) -- highest low id, keeps the lowest ones free
            else
                ids[i] = table.remove(free.static, 1)
            end
        end
    end
    return ids
end

---Puts dynamic and joint-linked objects on ids 1-MAX_NONSTATIC_OBJECTS and static ones above, as far
---as ids allow: dynamic objects above take free low ids or swap with static objects on low ids, then
---the remaining static objects on low ids move to free high ids. Joints follow the new ids.
---@return integer moved objects that got a new id
---@return integer left dynamic objects still above (more need low ids than there are)
function ModData.reindex()
    local free = ModData.freeIds
    local highDynamic, lowStatic = {}, {}
    -- pools are read before any id changes, a missing flag line is read from the game by id
    for _, obj in ipairs(ModData.parsed.env_obj) do
        local pool = ModData.idPool(obj, true)
        if pool == "nonStatic" and obj.id > MAX_NONSTATIC_OBJECTS then
            table.insert(highDynamic, obj)
        elseif pool == "static" and obj.id <= MAX_NONSTATIC_OBJECTS then
            table.insert(lowStatic, obj)
        end
    end
    table.sort(highDynamic, function(a, b) return a.id < b.id end)
    table.sort(lowStatic, function(a, b) return a.id > b.id end) -- highest low ids move first

    local idMap = {} -- old id -> new id, every object moves at most once
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
    ModData.jointIds = getJointIds(ModData.parsed.env_obj_joint) -- ids changed, the old set is stale
    ModData.sortObjects()
    return moved, left
end

---Reads the joint-linked object ids again (ModData.jointIds is set when the mod loads): a new link
---made in the editor counts before the reload, e.g. for a Reindex right away (utils/joints.lua)
function ModData.refreshJointIds()
    ModData.jointIds = getJointIds(ModData.parsed.env_obj_joint)
end

-- model_name is relative to mod_assets/<the mod file's folders>/<mod name>/, as used by the game's own
-- mods: mod/owo.tbm uses ../Noki/PinTori for mod_assets/Noki/PinTori.obj, mod/Fun/HoleInTheWall/
-- holeinthewall6.tbm uses ../../../events/sakura for mod_assets/events/sakura.obj

---@param path string? "" for the root
---@return string[]
local function splitPath(path)
    local parts = {}
    for part in tostring(path or ""):gmatch("[^/\\]+") do table.insert(parts, part) end
    return parts
end

---model_name for a model: MGE's data keeps them for a file in data/mod itself (the working copies are
---there), whose model folder is mod_assets/<mod name>/, so models are one folder up from it. With
---modPath, for a mod file there instead: one more folder up per folder it's in
---@param model string model path in mod_assets without .obj, e.g. "Noki/PinTori"
---@param modPath string? mod file path relative to data/mod, default a file in data/mod itself
---@return string
function ModData.toModelName(model, modPath)
    return string.rep("../", #splitPath(modPath) > 0 and #splitPath(modPath) or 1) .. model
end

---The mod data as a file at path (under data/mod) needs it: model_name lines point from that file's
---model folder. MGE's data has them for data/mod itself (toModelName), a mod saved into a subfolder
---gets a copy with them rewritten. The data itself isn't changed
---@param path string
---@return FileParserResult
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

---Model path in mod_assets (without .obj) that a model_name points to, for the mod file at modPath
---@param modelName string?
---@param modPath string? mod file path relative to data/mod, e.g. "Fun/HoleInTheWall/holeinthewall6.tbm"
---@return string? nil when it points outside mod_assets
function ModData.fromModelName(modelName, modPath)
    if not modelName or modelName == "" then return nil end
    -- the mod's model folder: its folders, then a folder named like the mod
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

---MGE's working copies are in data/mod itself, so models of a mod loaded from a subfolder would point
---to the wrong folder after the first apply: rewrite them relative to data/mod (Save into a subfolder
---writes them back for its folder, ModData.parsedFor)
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

---Re-reads the loaded mod file and finds free object ids in the world. The atmo layer (parsed.atmo)
---isn't in the file (utils/atmo.lua): the one there is kept. Opening another mod replaces it (Atmo.load,
---main.lua's start and match_begin)
function ModData.reloadObjects()
    local atmo = ModData.parsed and ModData.parsed.atmo or {}
    init()

    if MGE.modPath then
        ModData.parsed = FileHandler.ParseMod(MGE.modFolder .. MGE.modPath)
        rebaseModels()
        ModData.jointIds = getJointIds(ModData.parsed.env_obj_joint)
    else
        print("Mod not found")
    end
    ModData.parsed.atmo = atmo

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
-- the dojo center (middle between the players) in mod file / world coordinates. The Pos row shows
-- positions relative to it, exported assets and generated shapes are centered on it
MGE.POS_ORIGIN = { 1, -0.1, 0 }
-- a line before the first object of an asset file: Import keeps the objects where the file has them
-- instead of moving them in front of the camera (maps from tools/mapconv.lua)
MGE.KEEP_POSITION_TAG = "#mge_keep_position"
