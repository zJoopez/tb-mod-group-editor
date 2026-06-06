ModEnvObjects = {}
---@class XYZ
---@field x number
---@field y number
---@field z number

---@class RGBA
---@field r number
---@field g number
---@field b number
---@field a number

---@class EnvObject
---@field id integer
---@field pos number[]
---@field rot number[]
---@field color number[]
---@field sides number[]
---@field flag FLAGS
---@field bounce number
---@field mass number
---@field shape integer
---@field vis integer
---@field friction number
---@field force XYZ
---@field use_model number
---@field model_name string
---@field selected boolean? --custom
---@field is_static fun(self: EnvObject): boolean

---@class ModExport
---@field objects EnvObject[]
---@field parsed FileParserResult
---@field freeIds FreeIdHolder

---@class FreeIdHolder
---@field dynamic integer[]
---@field static integer[]

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

require('toriui.uielement3d')
MAX_ENV_OBJECTS = 256
MAX_NONSTATIC_OBJECTS = 48

SHAPE_NAMES = {}
for name, value in pairs(SHAPE) do
    SHAPE_NAMES[value] = name
end

local function is_static(self)
    return bit.band(self.flag, FLAGS.STATIC) ~= 0
end

function ModEnvObjects:reloadObjects()
    ---@type FileParserResult
    ModEnvObjects.parsed = FileHandler.ParseMod(MGE.modFolder .. MGE.modPath)
    ModEnvObjects.objects = {}
    ModEnvObjects.freeIds = { nonStatic = {}, static = {} }

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

            --- imagine sir not providing all object data
            local item = ModEnvObjects.parsed.env_obj[obj.id]
            local fx, fy, fz
            if item.props.force ~= nil then fx, fy, fz = item.props.force:match("(%S+)%s+(%S+)%s+(%S+)") end
            obj.force = { x = tonumber(fx) or 0, y = tonumber(fy) or 0, z = tonumber(fz) or 0 }
            obj.friction = tonumber(item.props.friction) or 10000
            obj.model_name = item.props.model_name
            obj.use_model = tonumber(item.props.use_model) or 0

            obj.is_static = is_static

            ModEnvObjects.objects[obj.id] = obj
        else
            if (i >= MAX_NONSTATIC_OBJECTS) then
                ModEnvObjects.freeIds.static[#ModEnvObjects.freeIds.static + 1] = obj.id
            else
                ModEnvObjects.freeIds.nonStatic[#ModEnvObjects.freeIds.nonStatic + 1] = obj.id
            end
        end
    end
end

ModEnvObjects:reloadObjects()

return ModEnvObjects
