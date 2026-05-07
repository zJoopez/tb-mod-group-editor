local Types = dofile(MgePath .. "ModTypes.lua")

local Parser = {}

local rawStringKeys = {
    message = true,
    world_shader = true,
    model_name = true,
    shape = true,
    material = true
}

local vectorKeys = {
    gravity = true,
    pos = true,
    rot = true,
    color = true,
    sides = true,
    force = true,
    axis = true,
    range = true,
    alt_sides = true
}

local csvVectorKeys = {
    engageplayerpos = true,
    engageplayerrot = true
}

local function trim(s)
    return s:match("^%s*(.-)%s*$")
end

local function splitWords(s)
    local t = {}
    for part in s:gmatch("%S+") do
        t[#t + 1] = part
    end
    return t
end

local function parseNumberList(s)
    local out = {}
    for part in s:gmatch("[^,%s]+") do
        out[#out + 1] = tonumber(part) or part
    end
    return out
end

local function parseValue(key, value)
    value = trim(value or "")

    if value == "" then
        return true
    end

    if rawStringKeys[key] then
        return value
    end

    if vectorKeys[key] or csvVectorKeys[key] then
        return parseNumberList(value)
    end

    local n = tonumber(value)
    if n ~= nil then
        return n
    end

    return value
end

local function getIndentLevel(rawline)
    local indent = rawline:match("^(%s*)") or ""
    indent = indent:gsub("\t", "    ")
    local count = #indent

    if count == 0 then
        return 0
    elseif count <= 4 then
        return 1
    else
        return 2
    end
end

---@param path string
---@return Mod
function Parser.ParseFile(path)
    local file = Files.Open(path, FILES_MODE_READONLY)
    if not file or not file.data then
        return nil
    end

    local mod = Types.Mod:new()
    local currentBlock = nil
    local currentBlockType = nil
    local currentPlayer = nil
    local currentSubBlock = nil
    local currentSubBlockType = nil

    for _, rawline in ipairs(file:readAll()) do
        if rawline and not rawline:match("^%s*$") then
            local line = trim(rawline)

            if not line:match("^#!") and not line:match("^#") then
                local level = getIndentLevel(rawline)
                local key, rest = line:match("^(%S+)%s*(.-)$")

                if level == 0 then
                    currentBlock = nil
                    currentBlockType = nil
                    currentPlayer = nil
                    currentSubBlock = nil
                    currentSubBlockType = nil

                    if key == "gamerule" then
                        mod.gamerule = Types.ModGamerules:new()
                        currentBlock = mod.gamerule
                        currentBlockType = "gamerule"

                    elseif key == "env_obj" then
                        local args = splitWords(rest)
                        local obj = Types.ModEnvObj:new(tonumber(args[1]) or 0)
                        mod:addEnvObj(obj)
                        currentBlock = obj
                        currentBlockType = "env_obj"

                    elseif key == "env_obj_joint" then
                        local args = splitWords(rest)
                        local joint = Types.ModEnvObjJoint:new(
                            tonumber(args[1]) or 0,
                            tonumber(args[2]) or 0,
                            tonumber(args[3]) or 0
                        )
                        mod:addEnvObjJoint(joint)
                        currentBlock = joint
                        currentBlockType = "env_obj_joint"

                    elseif key == "player" then
                        local args = splitWords(rest)
                        local player = Types.ModPlayer:new(tonumber(args[1]) or 0)
                        mod:addPlayer(player)
                        currentBlock = player
                        currentBlockType = "player"
                        currentPlayer = player

                    else
                        mod[key] = parseValue(key, rest)
                    end

                elseif level == 1 then
                    if currentBlockType == "player" and key == "body" then
                        currentSubBlock = currentPlayer:addBody(trim(rest))
                        currentSubBlockType = "body"

                    elseif currentBlockType == "player" and key == "joint" then
                        currentSubBlock = currentPlayer:addJoint(trim(rest))
                        currentSubBlockType = "joint"

                    elseif currentBlock then
                        currentBlock[key] = parseValue(key, rest)
                        currentSubBlock = nil
                        currentSubBlockType = nil
                    end

                elseif level == 2 then
                    if currentSubBlock then
                        currentSubBlock[key] = parseValue(key, rest)
                    end
                end
            end
        end
    end

    file:close()
    return mod
end

return Parser