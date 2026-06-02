local FileHandler = {}

---@class FileParserEnvObj
---@field id number
---@field props table<string, string>
---@field selected boolean?
---@field kind string

---@class FileParserEnvObjJoint
---@field id number
---@field obj1 number
---@field obj2 number
---@field props table<string, string>
---@field selected boolean?
---@field kind string

---@class FileParserResult
---@field env_obj table<integer, FileParserEnvObj>
---@field env_obj_joint table<integer, FileParserEnvObjJoint>
---@field ignores string[]

local indent = "   "

function FileHandler.ParseMod(path)
    local file = Files.Open(path, FILES_MODE_READONLY)
    if not file then return nil end

    ---@type FileParserResult
    local parser = {
        env_obj = {},
        env_obj_joint = {},
        ignores = {}
    }

    local lines = file:readAll()
    file:close()

    local i = 1
    while i <= #lines do
        local kind, line
        line = lines[i]

        if line:match("^env_obj%s+%d+") then
            kind = "env_obj"
        elseif line:match("^env_obj_joint%s+") then
            kind = "env_obj_joint"
        end

        if kind then
            local block = { kind = kind, header = line, lines = {} }
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
        else
            parser.ignores[#parser.ignores + 1] = line
            i = i + 1
        end
    end
    return parser
end

function FileHandler.parseBlock(block)
    ---@type FileParserEnvObj|FileParserEnvObjJoint
    local obj = { kind = block.kind, props = {} }

    if block.kind == "env_obj" then
        obj.id = tonumber(block.header:match("env_obj%s+(%d+)")) or 0
    elseif block.kind == "env_obj_joint" then
        local a, b, c = block.header:match("env_obj_joint%s+(%d+)%s+(%d+)%s+(%d+)")
        obj.id = tonumber(a) or 0
        obj.obj1 = tonumber(b) or 0
        obj.obj2 = tonumber(c) or 0
    end

    for _, line in ipairs(block.lines) do
        local key, value = line:match("^%s*(%S+)%s*(.-)%s*$")
        if key then
            obj.props[key] = value
        end
    end

    return obj
end

---@param file File
---@param objects table<number, FileParserEnvObj | FileParserEnvObjJoint>
local function writeParsedEnvObj(file, objects)
    for _, obj in pairs(objects) do
        local header = table.concat({ obj.kind, obj.id, obj.obj1, obj.obj2 }, " ")
        file:writeLine(header)
        for key, value in pairs(obj.props) do
            file:writeLine(indent .. key .. " " .. value)
        end
    end
end

---@param parser FileParserResult
---@param path string
---@return boolean
function FileHandler.WriteMod(parser, path)
    local file = Files.Open(path, FILES_MODE_WRITE)
    if not file then return false end

    -- Write ignored lines first (headers, gamerules, etc.)
    for _, line in ipairs(parser.ignores) do
        file:writeLine(line)
    end

    -- Write env_obj and env_obj_joint blocks in order
    writeParsedEnvObj(file, parser.env_obj or {})
    writeParsedEnvObj(file, parser.env_obj_joint or {})

    file:close()
    return true
end

return FileHandler
