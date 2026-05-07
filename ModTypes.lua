local Types = {}

---@class ModGamerules
---@field matchframes number?
---@field turnframes number?
---@field flags number?
---@field grip number?
---@field dismemberment number?
---@field fracture number?
---@field disqualification number?
---@field dqtimeout number?
---@field dqflag number?
---@field dismemberthreshold number?
---@field fracturethreshold number?
---@field pointthreshold number?
---@field winpoint number?
---@field dojotype number?
---@field dojosize number?
---@field engagedistance number?
---@field engageheight number?
---@field engagerotation number?
---@field engagespace number?
---@field engageplayerpos number[]?
---@field engageplayerrot number[]?
---@field damage number?
---@field gravity number[]?
---@field sumo number?
---@field reactiontime number?
---@field drawwinner number?
---@field maxcontacts number?
---@field ghostlength number?
---@field ghostspeed number?
---@field ghostcustom number?
---@field grabmode number?
---@field tearthreshold number?
---@field numplayers number?
local ModGamerules = {}
ModGamerules.__index = ModGamerules

function ModGamerules:new()
    return setmetatable({}, self)
end

---@class ModEnvObj
---@field id number
---@field shape string?
---@field pos number[]?
---@field mass number?
---@field color number[]?
---@field rot number[]?
---@field sides number[]?
---@field force number[]?
---@field flag number?
---@field bounce number?
---@field friction number?
---@field hardness number?
---@field use_model number?
---@field model_name string?
local ModEnvObj = {}
ModEnvObj.__index = ModEnvObj

function ModEnvObj:new(id)
    return setmetatable({ id = id }, self)
end

---@class ModEnvObjJoint
---@field id number
---@field obj1 number
---@field obj2 number
---@field pos number[]?
---@field axis number[]?
---@field range number[]?
---@field strength number?
---@field velocity number?
---@field visible number?
local ModEnvObjJoint = {}
ModEnvObjJoint.__index = ModEnvObjJoint

function ModEnvObjJoint:new(id, obj1, obj2)
    return setmetatable({
        id = id,
        obj1 = obj1,
        obj2 = obj2
    }, self)
end

---@class ModPlayerBody
---@field name string
---@field alt_sides number[]?
---@field pos number[]?
local ModPlayerBody = {}
ModPlayerBody.__index = ModPlayerBody

function ModPlayerBody:new(name)
    return setmetatable({ name = name }, self)
end

---@class ModPlayer
---@field id number
---@field bodies table
---@field bodyOrder table
---@field joints table
---@field jointOrder table
local ModPlayer = {}
ModPlayer.__index = ModPlayer

---@class ModPlayerJoint
---@field name string
local ModPlayerJoint = {}
ModPlayerJoint.__index = ModPlayerJoint

function ModPlayerJoint:new(name)
    return setmetatable({ name = name }, self)
end

function ModPlayer:new(id)
    return setmetatable({
        id = id,
        bodies = {},
        bodyOrder = {},
        joints = {},
        jointOrder = {}
    }, self)
end

function ModPlayer:addBody(name)
    if self.bodies[name] then
        return self.bodies[name]
    end
    local body = ModPlayerBody:new(name)
    self.bodies[name] = body
    self.bodyOrder[#self.bodyOrder + 1] = name
    return body
end

function ModPlayer:addJoint(name)
    if self.joints[name] then
        return self.joints[name]
    end
    local joint = ModPlayerJoint:new(name)
    self.joints[name] = joint
    self.jointOrder[#self.jointOrder + 1] = name
    return joint
end

---@class Mod
---@field version number?
---@field message string?
---@field world_shader string?
---@field use_model number?
---@field model_name string?
---@field gamerule ModGamerules?
---@field envObjects ModEnvObj[]
---@field envObjectsById table
---@field envObjJoints ModEnvObjJoint[]
---@field envObjJointsById table
---@field players ModPlayer[]
---@field playersById table
local Mod = {}
Mod.__index = Mod

function Mod:new()
    return setmetatable({
        envObjects = {},
        envObjectsById = {},
        envObjJoints = {},
        envObjJointsById = {},
        players = {},
        playersById = {}
    }, self)
end

function Mod:addEnvObj(obj)
    self.envObjects[#self.envObjects + 1] = obj
    self.envObjectsById[obj.id] = obj
end

function Mod:addEnvObjJoint(joint)
    self.envObjJoints[#self.envObjJoints + 1] = joint
    self.envObjJointsById[joint.id] = joint
end

function Mod:addPlayer(player)
    self.players[#self.players + 1] = player
    self.playersById[player.id] = player
end

Types.ModGamerules = ModGamerules
Types.ModEnvObj = ModEnvObj
Types.ModEnvObjJoint = ModEnvObjJoint
Types.ModPlayerBody = ModPlayerBody
Types.ModPlayer = ModPlayer
Types.Mod = Mod

return Types
