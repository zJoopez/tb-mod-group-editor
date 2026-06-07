FileHandler = {}

---@class FileParserEnvObj
---@field id integer
---@field props table<string, string>
---@field selected boolean?
---@field kind string

---@class FileParserEnvObjJoint
---@field id integer
---@field obj1 integer
---@field obj2 integer
---@field props table<string, string>
---@field selected boolean?
---@field kind string

---@class FileParserResult
---@field env_obj FileParserEnvObj[]
---@field env_obj_joint FileParserEnvObjJoint[]
---@field ignores string[]

local indent = "   "

---@param path string
---@return FileParserResult
function FileHandler.ParseMod(path)
    local file = Files.Open(path, FILES_MODE_READONLY)

    ---@type FileParserResult
    local parser = {
        env_obj = {},
        env_obj_joint = {},
        ignores = {}
    }

    if not file then return parser end

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
                table.insert(block.lines, lines[i])
                i = i + 1
            end

            local obj = FileHandler.parseBlock(block)
            if kind == "env_obj" then
                table.insert(parser.env_obj, obj)
            else
                table.insert(parser.env_obj_joint, obj)
            end
        else
            table.insert(parser.ignores, line)
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
---@param objects FileParserEnvObj[] | FileParserEnvObjJoint[]
local function writeParsedEnvObj(file, objects)
    for _, obj in ipairs(objects) do
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
