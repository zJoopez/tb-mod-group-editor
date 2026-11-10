local FileHandler = {}
MGE.FileHandler = FileHandler

-- decimals written for numbers MGE computes. The game reads long decimals fine (mods ship values with
-- 16+ decimals, its modmaker writes 8). 10 keeps small sides precise and stops rounding from adding
-- up when edits go through several save / reload rounds. Never an exponent: "%f", not "%g"
local DECIMALS = 10

---Formats a number for mod files: up to DECIMALS decimals, trailing zeros removed.
---Keeps small values like 0.0001 that a fixed 2 decimal format would round to 0.
---@param value number
---@return string
function FileHandler.formatNumber(value)
    local s = string.format("%." .. DECIMALS .. "f", value):gsub("0+$", ""):gsub("%.$", "")
    if s == "-0" then s = "0" end
    return s
end

---@param ... number
---@return string space separated numbers
function FileHandler.formatNumbers(...)
    local parts = {}
    for i, v in ipairs({ ... }) do parts[i] = FileHandler.formatNumber(v) end
    return table.concat(parts, " ")
end

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
    "force", "hardness", "visible", "thrust", "model_name", "use_model",
}
local KEY_RANK = {}
for i, key in ipairs(KEY_ORDER) do KEY_RANK[key] = i end

-- comment line older MGE versions wrote with the rotation they applied. Orientation now comes from
-- the rot line, so these are dropped when reading and left out of the next save
local FRAME_TAG = "#mge_frame"

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
        elseif key == FRAME_TAG then
            -- old rotation record, not kept
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

-- section words that belong inside a player section (player 0 > body head, joint neck)
local PLAYER_PART_WORDS = { body = true, joint = true }

---Line range of a `player N` section: its header to its last non blank line. The section ends at an
---unindented line or another section header (player 1, env_obj...), indented body/joint lines are its parts
---@param lines string[]
---@param playerId integer? nil finds the first player section
---@return integer? first header line
---@return integer? last
---@return integer? playerId of the found section
local function findPlayerSection(lines, playerId)
    for i, line in ipairs(lines) do
        local id = tonumber(line:match("^%s*player%s+(%d+)%s*$"))
        if id and (playerId == nil or id == playerId) then
            local last = i
            for j = i + 1, #lines do
                local l = lines[j]
                if not l:match("^%s*$") then
                    local word = firstWord(l) or ""
                    if not l:match("^%s") or (SECTION_WORDS[word] and not PLAYER_PART_WORDS[word]) then break end
                    last = j
                end
            end
            return i, last, id
        end
    end
    return nil, nil, nil
end

---Player sections can be before the first object (ignores) or after the objects (trailer)
local PLAYER_LISTS = { "ignores", "trailer" }

---Lines of a player section without its header (the body/joint parts, indentation kept)
---@param parser FileParserResult
---@param playerId integer? nil takes the first player section
---@return string[]? nil when there's no such section (the game uses its default body)
---@return integer? playerId of the found section
function FileHandler.getPlayerLines(parser, playerId)
    for _, key in ipairs(PLAYER_LISTS) do
        local list = parser[key] or {}
        local first, last, id = findPlayerSection(list, playerId)
        if first then
            local lines = {}
            for i = first + 1, last do table.insert(lines, list[i]) end
            return lines, id
        end
    end
    return nil, nil
end

---Body/joint parts outside player sections (e.g. fatkido.tbm), the game applies them to all players.
---Indentation is normalized to player section layout, some mods write these unindented
---@param parser FileParserResult
---@return string[]? nil when there are none
function FileHandler.getSharedPlayerLines(parser)
    local parts = {}
    for _, key in ipairs(PLAYER_LISTS) do
        local inPlayer, inPart = false, false
        for _, line in ipairs(parser[key] or {}) do
            local word = firstWord(line)
            if word then
                -- same end rule as findPlayerSection
                if inPlayer and (not line:match("^%s") or (SECTION_WORDS[word] and not PLAYER_PART_WORDS[word])) then
                    inPlayer = false
                end
                if word == "player" then
                    inPlayer, inPart = true, false
                elseif not inPlayer and PLAYER_PART_WORDS[word] then
                    inPart = true
                    table.insert(parts, indent .. (line:gsub("^%s+", "")))
                elseif SECTION_WORDS[word] or inPlayer then
                    inPart = false
                elseif inPart then
                    table.insert(parts, indent .. indent .. (line:gsub("^%s+", "")))
                end
            end
        end
    end
    return #parts > 0 and parts or nil
end

---Replaces a player section's parts, or adds the section after the objects when the mod has none.
---ignores/trailer are replaced with new tables, not modified: history states share them
---@param parser FileParserResult
---@param playerId integer
---@param parts string[] lines after the header
function FileHandler.setPlayerLines(parser, playerId, parts)
    for _, key in ipairs(PLAYER_LISTS) do
        local list = parser[key] or {}
        local first, last = findPlayerSection(list, playerId)
        if first then
            local lines = {}
            for i = 1, first do table.insert(lines, list[i]) end -- header kept as written
            for _, line in ipairs(parts) do table.insert(lines, line) end
            for i = last + 1, #list do table.insert(lines, list[i]) end
            parser[key] = lines
            return
        end
    end
    local lines = {}
    for _, line in ipairs(parser.trailer or {}) do table.insert(lines, line) end
    if #lines > 0 then table.insert(lines, "") end
    table.insert(lines, "player " .. playerId)
    for _, line in ipairs(parts) do table.insert(lines, line) end
    parser.trailer = lines
end

---Writes gamerule values into the `gamerule` section: existing lines get the new value (indentation
---kept), missing rules are added at the end of the section, the section is added when the mod has none.
---The section is its rule lines, blanks and comments after the header (some mods don't indent rules).
---ignores/trailer are replaced with new tables, not modified: history states share them
---@param parser FileParserResult
---@param values table<string, string> rules to write
---@param ruleNames table<string, any> every gamerule name, tells rule lines from what comes after the section
function FileHandler.setGamerules(parser, values, ruleNames)
    local pending = {}
    for name in pairs(values) do table.insert(pending, name) end
    table.sort(pending)

    for _, key in ipairs(PLAYER_LISTS) do
        local list = parser[key] or {}
        local header
        for i, line in ipairs(list) do
            if firstWord(line) == "gamerule" then header = i break end
        end
        if header then
            local lines, last = {}, header
            for i = 1, header do table.insert(lines, list[i]) end
            local written = {}
            local i = header + 1
            while i <= #list do
                local line = list[i]
                local word = firstWord(line)
                if word and not ruleNames[word] and not word:match("^#") and not word:match("^//") then break end
                if word and values[word] ~= nil then
                    line = line:match("^(%s*)") .. word .. " " .. values[word]
                    written[word] = true
                end
                table.insert(lines, line)
                if word then last = #lines end
                i = i + 1
            end
            -- new rules go right after the last rule line, blank lines stay after them
            local added = {}
            for _, name in ipairs(pending) do
                if not written[name] then table.insert(added, indent .. name .. " " .. values[name]) end
            end
            for n, line in ipairs(added) do table.insert(lines, last + n, line) end
            for j = i, #list do table.insert(lines, list[j]) end
            parser[key] = lines
            return
        end
    end

    local lines = {}
    for _, line in ipairs(parser.ignores or {}) do table.insert(lines, line) end
    table.insert(lines, "gamerule")
    for _, name in ipairs(pending) do table.insert(lines, indent .. name .. " " .. values[name]) end
    parser.ignores = lines
end

---Writes the whole mod through file:writeLine (a File, or a collector for modText)
---@param file { writeLine: fun(self, line: string) }
---@param parser FileParserResult
local function writeParser(file, parser)
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
end

---@param parser FileParserResult
---@param path string
---@return boolean
function FileHandler.WriteMod(parser, path)
    local file = Files.Open(path, FILES_MODE_WRITE)
    if not file or not file.data then return false end
    ---@diagnostic disable-next-line: param-type-mismatch
    writeParser(file, parser)
    file:close()
    return true
end

---The mod as WriteMod would write it, without writing anything. Compared with the text of the last
---save to tell whether there are unsaved changes
---@param parser FileParserResult
---@return string
function FileHandler.modText(parser)
    local lines = {}
    writeParser({ writeLine = function(_, line) table.insert(lines, line) end }, parser)
    return table.concat(lines, "\n")
end
