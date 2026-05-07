local Writer = {}

local csvVectorKeys = {
    engageplayerpos = true,
    engageplayerrot = true
}

local gameruleOrder = {
    "matchframes", "turnframes", "flags", "grip", "dismemberment", "fracture",
    "disqualification", "dqtimeout", "dqflag", "dismemberthreshold",
    "fracturethreshold", "pointthreshold", "winpoint", "dojotype", "dojosize",
    "engagedistance", "engageheight", "engagerotation", "engagespace",
    "engageplayerpos", "engageplayerrot", "damage", "gravity", "sumo",
    "reactiontime", "drawwinner", "maxcontacts", "ghostlength", "ghostspeed",
    "ghostcustom", "grabmode", "tearthreshold", "numplayers"
}

local envObjOrder = {
    "shape", "pos", "mass", "color", "rot", "sides", "force", "flag",
    "bounce", "friction", "hardness", "use_model", "model_name"
}

local envObjJointOrder = {
    "pos", "axis", "range", "strength", "velocity", "visible"
}

local playerBodyOrder = {
    "alt_sides", "pos"
}

local function formatNumber(n)
    if n == math.floor(n) then
        return string.format("%.0f", n)
    end
    return string.format("%.4f", n):gsub("0+$", ""):gsub("%.$", "")
end

local function formatList(list, sep)
    local out = {}
    local i
    for i = 1, #list do
        if type(list[i]) == "number" then
            out[i] = formatNumber(list[i])
        else
            out[i] = tostring(list[i])
        end
    end
    return table.concat(out, sep or " ")
end

local function writeKeyValue(file, indent, key, value)
    if value == nil then
        return
    end

    local prefix = string.rep(" ", indent) .. key .. " "

    if type(value) == "table" then
        local sep = csvVectorKeys[key] and "," or " "
        file:write(prefix .. formatList(value, sep) .. "\n")
    elseif type(value) == "number" then
        file:write(prefix .. formatNumber(value) .. "\n")
    elseif type(value) == "boolean" then
        file:write(prefix .. (value and "1" or "0") .. "\n")
    else
        file:write(prefix .. tostring(value) .. "\n")
    end
end

function Writer.WriteGamerule(file, gamerule)
    local _, key
    file:write("gamerule\n")
    for _, key in ipairs(gameruleOrder) do
        writeKeyValue(file, 3, key, gamerule[key])
    end
end

function Writer.WriteEnvObj(file, obj)
    local _, key
    file:write("env_obj " .. formatNumber(obj.id) .. "\n")
    for _, key in ipairs(envObjOrder) do
        writeKeyValue(file, 3, key, obj[key])
    end
end

function Writer.WriteEnvObjJoint(file, joint)
    local _, key
    file:write(
        "env_obj_joint " ..
        formatNumber(joint.id) .. " " ..
        formatNumber(joint.obj1) .. " " ..
        formatNumber(joint.obj2) .. "\n"
    )
    for _, key in ipairs(envObjJointOrder) do
        writeKeyValue(file, 3, key, joint[key])
    end
end

function Writer.WritePlayerBody(file, body)
    local _, key
    file:write("   body " .. body.name .. "\n")
    for _, key in ipairs(playerBodyOrder) do
        writeKeyValue(file, 6, key, body[key])
    end
end

function Writer.WritePlayer(file, player)
    local _, bodyName
    file:write("player " .. formatNumber(player.id) .. "\n")
    for _, bodyName in ipairs(player.bodyOrder or {}) do
        Writer.WritePlayerBody(file, player.bodies[bodyName])
    end
end

function Writer.Save(path, mod)
    local _, obj, joint, player
    local file, err = io.open(path, "w+")
    if not file then
        return false, err
    end

    file:write("#!/usr/bin/toribash\n")
    writeKeyValue(file, 0, "version", mod.version)
    writeKeyValue(file, 0, "message", mod.message)
    writeKeyValue(file, 0, "world_shader", mod.world_shader)

    if mod.gamerule then
        Writer.WriteGamerule(file, mod.gamerule)
    end

    writeKeyValue(file, 0, "use_model", mod.use_model)
    writeKeyValue(file, 0, "model_name", mod.model_name)

    for _, obj in ipairs(mod.envObjects) do
        Writer.WriteEnvObj(file, obj)
    end

    for _, joint in ipairs(mod.envObjJoints) do
        Writer.WriteEnvObjJoint(file, joint)
    end

    for _, player in ipairs(mod.players) do
        Writer.WritePlayer(file, player)
    end

    file:close()
    return true
end

return Writer
