ModEnvObjects = { objects = {} }
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
---@field color RGBA
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

---@class ModExport
---@field objects EnvObject[]
---@field parsed FileParserResult

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
MAX_DYNAMIC_ENV_OBJECTS = 48
EnvObject = {}
EnvObject.__index = EnvObject

function ModEnvObjects:reloadObjects()
    ---@type FileParserResult
    ModEnvObjects.parsed = FileHandler.ParseMod(MGE.modFolder .. MGE.modPath)

    for i = 0, MAX_ENV_OBJECTS - 1, 1 do
        -- for i = 1, 10 - 1, 1 do
        if get_obj_pos(i) ~= nil then
            local obj = {}
            local color = get_obj_color(i)
            obj.id = i + 1
            obj.pos = { get_obj_pos(i) }
            obj.sides = { get_obj_sides(i) }
            obj.rot = get_obj_rot(i)
            obj.color = {
                r = math.floor((color[1] or 0) * 255),
                g = math.floor((color[2] or 0) * 255),
                b = math.floor((color[3] or 0) * 255),
                a = math.floor((color[4] or 0) * 255),
            }
            obj.flag = get_obj_flag(i)
            obj.bounce = get_obj_bounce(i)
            obj.mass = get_obj_mass(i)
            obj.shape = get_obj_shape(i)
            obj.vis = get_obj_vis(i)

            --- imagine sir not providing all object data
            if  ModEnvObjects.parsed.env_obj[obj.id] then
                local item = ModEnvObjects.parsed.env_obj[obj.id]
                if item.props.force ~= nil then
                    local fx, fy, fz = item.props.force:match("(%S+)%s+(%S+)%s+(%S+)")
                    obj.force = { x = tonumber(fx), y = tonumber(fy), z = tonumber(fz) }
                end
                obj.friction = tonumber(item.props.friction)
                obj.model_name = item.props.model_name
                obj.use_model = tonumber(item.props.use_model)
            end

            setmetatable(obj, EnvObject)
            ModEnvObjects.objects[#ModEnvObjects.objects + 1] = obj
        end
    end
end

function EnvObject:is_static()
    return bit.band(self.flag, FLAGS.STATIC) ~= 0
end

SHAPE_NAMES = {}
for name, value in pairs(SHAPE) do
    SHAPE_NAMES[value] = name
end

ModEnvObjects:reloadObjects()

return ModEnvObjects
