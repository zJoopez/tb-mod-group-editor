---@enum FLAGS
FLAGS = {
    NORMAL = 0,
    ALT = 1,
    SHIELD = 2,
    WEAPON = 6,
    STATIC = 8,
    UNGRIPPABLE = 16,
    DQ_DISABLE = 32,
    NO_DAMAGE = 64
}
---@enum SHAPE
SHAPE = {
    SPHERE = 1,
    BOX = 2,
    CAPSULE = 3,
}

---@class EnvObject
---@field id integer
---@field pos number[] --xyz
---@field rot number[] --rotation matrix
---@field color number[] --rgba
---@field sides number[] --xyz
---@field flag FLAGS
---@field bounce number
---@field mass number
---@field shape integer
---@field vis integer
---@field friction number
---@field force number[]
---@field use_model number
---@field model_name string
---@field selected boolean? --custom, tracks selected objects
---@field has_joint boolean? --custom, tracks if object is linked to joint
---@field is_static fun(self: EnvObject): boolean

---@class FreeIdHolder
---@field nonStatic integer[]
---@field static integer[]

---@class ModData
---@field objects EnvObject[]
---@field parsed FileParserResult
---@field freeIds FreeIdHolder
---@field jointIds table<integer, boolean>
---@field reloadObjects fun() --reloads objects from currently loaded mod
ModData = {}

MAX_ENV_OBJECTS = 256
MAX_NONSTATIC_OBJECTS = 48
SHAPE_NAMES = {}
for name, value in pairs(SHAPE) do
    SHAPE_NAMES[value] = name
end

local function is_static(self)
    return bit.band(self.flag, FLAGS.STATIC) ~= 0
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
    ModData.objects = {}
    ModData.freeIds = { nonStatic = {}, static = {} }
    ModData.jointIds = {}
end

function ModData.reloadObjects()
    init()

    if not MGE.modPath then
        print("Mod not found")
        return
    end

    ModData.parsed = FileHandler.ParseMod(MGE.modFolder .. MGE.modPath)
    ModData.jointIds = getJointIds(ModData.parsed.env_obj_joint)

    for i = 0, MAX_ENV_OBJECTS - 1, 1 do
        ---@type EnvObject
        local obj = {}
        obj.id = i + 1
        if get_obj_pos(i) ~= nil then
            obj.pos = { get_obj_pos(i) }
            obj.sides = { get_obj_sides(i) }
            obj.rot = get_obj_rot(i)
            obj.color = get_obj_color(i)
            obj.flag = get_obj_flag(i)
            obj.bounce = get_obj_bounce(i)
            obj.mass = get_obj_mass(i)
            obj.shape = get_obj_shape(i)
            obj.vis = get_obj_vis(i)
            obj.has_joint = ModData.jointIds[obj.id] == true

            --- imagine sir not providing all object data
            local item = ModData.parsed.env_obj[#ModData.objects + 1] or { props = {} }
            local fx, fy, fz
            if item.props.force ~= nil then fx, fy, fz = item.props.force:match("(%S+)%s+(%S+)%s+(%S+)") end
            obj.force = { tonumber(fx) or 0, tonumber(fy) or 0, tonumber(fz) or 0 }
            obj.friction = tonumber(item.props.friction) or 10000
            obj.model_name = item.props.model_name
            obj.use_model = tonumber(item.props.use_model) or 0
            obj.is_static = is_static

            table.insert(ModData.objects, obj)
        else
            if (i >= MAX_NONSTATIC_OBJECTS) then
                table.insert(ModData.freeIds.static, obj.id)
            else
                table.insert(ModData.freeIds.nonStatic, obj.id)
            end
        end
    end
    print("Mod data updated")
end

init() --initialize data on load
