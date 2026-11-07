FileHandler = {}

---One line inside an object block: a property (key, value in props) or a raw line kept as is (comments)
---@class FileParserLine
---@field key string?
---@field raw string?

---@class FileParserEnvObj
---@field id integer
---@field props table<string, string>
---@field lines FileParserLine[]? original line order, nil for objects created in the editor
---@field selected boolean?
---@field kind string

---@class FileParserEnvObjJoint
---@field id integer
---@field obj1 integer
---@field obj2 integer
---@field props table<string, string>
---@field lines FileParserLine[]?
---@field selected boolean?
---@field kind string

---@class FileParserResult
---@field env_obj FileParserEnvObj[]
---@field env_obj_joint FileParserEnvObjJoint[]
---@field ignores string[] lines before the first object (header comments, gamerule, body, joint...)
---@field trailer string[]? non object lines after the first object (usually player sections)

local indent = "   "

-- first word of a line that starts a new section, indentation is ignored as some mods indent headers
local SECTION_WORDS = {
    gamerule = true,
    body = true,
    joint = true,
    player = true,
    env_obj = true,
    env_obj_joint = true,
}

-- write order for properties that aren't in an object's original lines (new objects, added props)
local KEY_ORDER = {
    "shape", "pos", "rot", "sides", "color", "flag", "material", "mass", "bounce", "friction",
    "force", "visible", "thrust", "model_name", "use_model",
}
local KEY_RANK = {}
for i, key in ipairs(KEY_ORDER) do KEY_RANK[key] = i end

---@param line string
---@return string?
local function firstWord(line)
    return line:match("^%s*(%S+)")
end

---@param line string
---@return "env_obj"|"env_obj_joint"|nil
local function getBlockKind(line)
    local word = firstWord(line)
    if (word == "env_obj" or word == "env_obj_joint") and line:match("^%s*%S+%s+%d") then
        return word
    end
end

---@param line string
---@return boolean
local function isSectionHeader(line)
    return SECTION_WORDS[firstWord(line) or ""] == true
end

---Removes trailing blank lines, otherwise every save drops one (readAll ignores the last empty line)
---@param list string[]
local function trimTrailingBlank(list)
    while #list > 0 and list[#list]:match("^%s*$") do
        table.remove(list)
    end
end

---@param path string
---@return FileParserResult
function FileHandler.ParseMod(path)
    local file = Files.Open(path, FILES_MODE_READONLY)

    ---@type FileParserResult
    local parser = {
        env_obj = {},
        env_obj_joint = {},
        ignores = {},
        trailer = {},
    }

    if not file or not file.data then return parser end -- Files.Open sets data to nil on failure

    local lines = file:readAll()
    file:close()

    local seenObject = false
    local i = 1
    while i <= #lines do
        local line = lines[i]
        local kind = getBlockKind(line)

        if kind then
            seenObject = true
            local block = { kind = kind, header = line, lines = {} }
            i = i + 1

            while i <= #lines and not isSectionHeader(lines[i]) do
                if not lines[i]:match("^%s*$") then
                    table.insert(block.lines, lines[i])
                end
                i = i + 1
            end

            local obj = FileHandler.parseBlock(block)
            if kind == "env_obj" then
                table.insert(parser.env_obj, obj)
            else
                table.insert(parser.env_obj_joint, obj)
            end
        else
            -- keep sections after objects (player 0/1...) after them on write
            table.insert(seenObject and parser.trailer or parser.ignores, line)
            i = i + 1
        end
    end

    trimTrailingBlank(parser.trailer)
    if #parser.env_obj == 0 and #parser.env_obj_joint == 0 then trimTrailingBlank(parser.ignores) end
    return parser
end

function FileHandler.parseBlock(block)
    ---@type FileParserEnvObj|FileParserEnvObjJoint
    local obj = { kind = block.kind, props = {}, lines = {} }

    if block.kind == "env_obj" then
        obj.id = tonumber(block.header:match("env_obj%s+(%d+)")) or 0
    elseif block.kind == "env_obj_joint" then
        local a, b, c = block.header:match("env_obj_joint%s+(%d+)%s+(%d+)%s+(%d+)")
        obj.id = tonumber(a) or 0
        obj.obj1 = tonumber(b) or 0
        obj.obj2 = tonumber(c) or 0
    end

    for _, line in ipairs(block.lines or {}) do
        local key, value = line:match("^%s*(%S+)%s*(.-)%s*$")
        if key and key:match("^[%a_]") then
            -- duplicate keys: later value wins, line stays at its first position
            if obj.props[key] == nil then table.insert(obj.lines, { key = key }) end
            obj.props[key] = value
        else
            -- comments (#..., //...) and other non property lines are kept in place
            table.insert(obj.lines, { raw = (line:gsub("^%s+", ""):gsub("%s+$", "")) })
        end
    end

    return obj
end

---@param obj FileParserEnvObj|FileParserEnvObjJoint
local function buildHeader(obj)
    if not obj then return "" end
    if obj.kind == "env_obj_joint" then
        return string.format("%s %d %d %d", obj.kind, obj.id or 0, obj.obj1 or 0, obj.obj2 or 0)
    end
    return string.format("%s %d", obj.kind, obj.id or 0)
end

---Writes properties in original order, then props not in the original lines in KEY_ORDER
---@param file File
---@param obj FileParserEnvObj|FileParserEnvObjJoint
local function writeObjectLines(file, obj)
    local props = obj.props or {}
    local written = {}

    for _, entry in ipairs(obj.lines or {}) do
        if entry.raw then
            file:writeLine(indent .. entry.raw)
        elseif props[entry.key] ~= nil and not written[entry.key] then
            written[entry.key] = true
            file:writeLine(indent .. entry.key .. " " .. props[entry.key])
        end
    end

    local rest = {}
    for key in pairs(props) do
        if not written[key] then table.insert(rest, key) end
    end
    table.sort(rest, function(a, b)
        local ra, rb = KEY_RANK[a] or math.huge, KEY_RANK[b] or math.huge
        if ra ~= rb then return ra < rb end
        return a < b
    end)
    for _, key in ipairs(rest) do
        file:writeLine(indent .. key .. " " .. props[key])
    end
end

---@param file File
---@param objects FileParserEnvObj[] | FileParserEnvObjJoint[]
local function writeParsedEnvObj(file, objects)
    for _, obj in ipairs(objects or {}) do
        local header = buildHeader(obj)
        if header ~= "" then
            file:writeLine(header)
        end
        writeObjectLines(file, obj)
        file:writeLine("")
    end
end

---@param parser FileParserResult
---@param path string
---@return boolean
function FileHandler.WriteMod(parser, path)
    local file = Files.Open(path, FILES_MODE_WRITE)
    if not file or not file.data then return false end

    -- Write ignored lines first (headers, gamerules, etc.)
    for _, line in ipairs(parser.ignores or {}) do
        file:writeLine(line)
    end

    -- Write env_obj and env_obj_joint blocks in order
    writeParsedEnvObj(file, parser.env_obj or {})
    writeParsedEnvObj(file, parser.env_obj_joint or {})

    -- sections that came after objects in the original file
    for _, line in ipairs(parser.trailer or {}) do
        file:writeLine(line)
    end

    file:close()
    return true
end
