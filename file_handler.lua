local FileHandler = {}

---@class FileParserBlock
---@field kind "env_obj"|"env_obj_joint"
---@field header string
---@field lines string[]

---@class FileParserEnvObj
---@field id number
---@field header string
---@field props table<string, string>

---@class FileParserEnvObjJoint
---@field id number
---@field obj1 number
---@field obj2 number
---@field header string
---@field props table<string, string>

---@class FileParserResult
---@field env_obj table<number, FileParserEnvObj>?
---@field env_obj_joint table<number, FileParserEnvObjJoint>
---@field blocks FileParserBlock[]
---@field ignores string[]

function FileHandler.ParseMod(path)
    local file = Files.Open(path, FILES_MODE_READONLY)
    if not file then
        return nil
    end

    local data = file:readAll()
    file:close()

    local lines = {}
    if type(data) == "string" then
        for line in (data .. "\n"):gmatch("(.-)\n") do
            lines[#lines + 1] = line
        end
    else
        lines = data
    end

    ---@type FileParserResult
    local parser = {
        env_obj = {},
        env_obj_joint = {},
        blocks = {},
        ignores = {}
    }

    local i = 1
    while i <= #lines do
        local line = lines[i]
        local kind, header

        if line:match("^env_obj%s+%d+") then
            kind = "env_obj"
            header = line
        elseif line:match("^env_obj_joint%s+") then
            kind = "env_obj_joint"
            header = line
        end

        if kind then
            local block = { kind = kind, header = header, lines = { header } }
            i = i + 1
            while i <= #lines and lines[i]:match("^%s+") do
                block.lines[#block.lines + 1] = lines[i]
                i = i + 1
            end

            local obj = FileHandler.parseBlock(block)
            if kind == "env_obj" then
                parser.env_obj[obj.id] = obj
            else
                parser.env_obj_joint[obj.id] = obj
            end

            parser.blocks[#parser.blocks + 1] = block
        else
            parser.ignores[#parser.ignores + 1] = line
            i = i + 1
        end
    end

    return parser
end

function FileHandler.parseBlock(block)
    ---@type FileParserEnvObj|FileParserEnvObjJoint
    local obj = { header = block.header, props = {} }

    if block.kind == "env_obj" then
        obj.id = tonumber(block.header:match("env_obj%s+(%d+)"))
    elseif block.kind == "env_obj_joint" then
        local a, b, c = block.header:match("env_obj_joint%s+(%d+)%s+(%d+)%s+(%d+)")
        obj.id = tonumber(a)
        obj.obj1 = tonumber(b)
        obj.obj2 = tonumber(c)
    end

    for j = 2, #block.lines do -- first line handled above
        local key, value = block.lines[j]:match("^%s*(%S+)%s*(.-)%s*$")
        if key then
            obj.props[key] = value
        end
    end

    return obj
end

function FileHandler.WriteMod(parser, path)
    local file = Files.Open(path, FILES_MODE_WRITE)
    if not file then
        return false
    end

    -- Write ignored lines first (headers, gamerules, etc.)
    for _, line in ipairs(parser.ignores) do
        file:writeLine(line)
    end

    -- Write env_obj and env_obj_joint blocks in order
    for _, block in ipairs(parser.blocks) do
        for _, line in ipairs(block.lines) do
            file:writeLine(line)
        end
    end

    file:close()
    return true
end

return FileHandler