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
local NUMBER_FORMAT = "%." .. DECIMALS .. "f"
function FileHandler.formatNumber(value)
    -- one pass: "%f" always writes the dot, so the trailing zeros and then the dot go (a release on thousands
    -- of atmo objects formats tens of thousands; two gsubs and a format string built each call were most of it)
    local s = string.format(NUMBER_FORMAT, value):match("^(.-)%.?0*$")
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
---@field atmoName string? an atmo object's name in its .atmo file (utils/atmo.lua), kept for parent lines

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
---@field atmo FileParserEnvObj[]? the atmo layer (utils/atmo_layer.lua, utils/atmo.lua). Kept in the mod's
---.atmo file, never in a .tbm: ParseMod leaves it empty. Ids are their order, 1 up
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
        atmo = {},
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
    if #parser.env_obj == 0 and #parser.env_obj_joint == 0 then
        trimTrailingBlank(parser.ignores)
    end
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

---Last line of the player section whose header is lines[first] (see findPlayerSection)
---@param lines string[]
---@param first integer
---@return integer
local function sectionLast(lines, first)
    local last = first
    for j = first + 1, #lines do
        local l = lines[j]
        if not l:match("^%s*$") then
            local word = firstWord(l) or ""
            if not l:match("^%s") or (SECTION_WORDS[word] and not PLAYER_PART_WORDS[word]) then break end
            last = j
        end
    end
    return last
end

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
            return i, sectionLast(lines, i), id
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

---Renumbers player sections: map[old id] is the new id, false removes the section (with a blank line
---before it, so no double blanks stay), ids not in the map stay. The shared part lines aren't touched.
---ignores/trailer are replaced with new tables, not modified: history states share them
---@param parser FileParserResult
---@param map table<integer, integer|false>
function FileHandler.renumberPlayers(parser, map)
    for _, key in ipairs(PLAYER_LISTS) do
        local list = parser[key]
        if list then
            local lines, i = {}, 1
            while i <= #list do
                local line = list[i]
                local id = tonumber(line:match("^%s*player%s+(%d+)%s*$"))
                if id and map[id] == false then
                    if #lines > 0 and lines[#lines]:match("^%s*$") then table.remove(lines) end
                    i = sectionLast(list, i) + 1
                    if #lines == 0 then -- it was first: its blank after goes instead
                        while list[i] and list[i]:match("^%s*$") do i = i + 1 end
                    end
                else
                    if id and map[id] then line = line:gsub("(player%s+)%d+", "%1" .. map[id], 1) end
                    table.insert(lines, line)
                    i = i + 1
                end
            end
            parser[key] = lines
        end
    end
end

---The list without the body/joint parts outside player sections (what getSharedPlayerLines collects)
---@param list string[]
---@return string[]
local function withoutSharedParts(list)
    local out = {}
    local inPlayer, inPart = false, false
    for _, line in ipairs(list) do
        local word = firstWord(line)
        local keep = true
        if word then
            if inPlayer and (not line:match("^%s") or (SECTION_WORDS[word] and not PLAYER_PART_WORDS[word])) then
                inPlayer = false
            end
            if word == "player" then
                inPlayer, inPart = true, false
            elseif not inPlayer and PLAYER_PART_WORDS[word] then
                inPart, keep = true, false
            elseif SECTION_WORDS[word] or inPlayer then
                inPart = false
            elseif inPart then
                keep = false
            end
        end
        if keep then out[#out + 1] = line end
    end
    return out
end

---A player section's lines as parts: each body / joint header with the lines under it
---@param lines string[]
---@return { key: string, lines: string[] }[]
local function partsOf(lines)
    local parts = {}
    for _, line in ipairs(lines) do
        local word = firstWord(line)
        if word and PLAYER_PART_WORDS[word] then
            parts[#parts + 1] = { key = line:gsub("^%s+", ""):gsub("%s+$", ""), lines = { line } }
        elseif parts[#parts] then
            table.insert(parts[#parts].lines, line)
        end
    end
    return parts
end

-- the mod format version the game's own modmaker writes (data/mod/modmaker.tbm: "version 15")
FileHandler.MOD_VERSION = 15

---Gives a mod without a `version` line the current one (FileHandler.MOD_VERSION), after its "#!" line.
---Mods without it (aikido.tbm, fat.tbm) are read the old way: engageplayerrot did nothing there, the
---same rules in a versioned copy (the modmaker's fat2.tbm, a4_drift_track_one.tbm's version 12) turned
---the players. ignores is replaced with a new table, not modified: history states share it
---@param parser FileParserResult
---@return boolean added
function FileHandler.ensureVersion(parser)
    for _, key in ipairs(PLAYER_LISTS) do
        for _, line in ipairs(parser[key] or {}) do
            if line:match("^%s*version%s+%d+") then return false end
        end
    end
    local old, lines = parser.ignores or {}, {}
    local at = (old[1] and old[1]:match("^#!")) and 2 or 1
    for i = 1, at - 1 do lines[#lines + 1] = old[i] end
    lines[#lines + 1] = "version " .. FileHandler.MOD_VERSION
    for i = at, #old do lines[#lines + 1] = old[i] end
    parser.ignores = lines
    return true
end

---Mods like fatkido.tbm give every player the same model with body/joint parts outside any player section.
---Read: those parts become every player's own section (a player's own parts win over the shared ones for the
---same body part or joint), so every player's model is edited on its own (Reset, Import, the Players panel).
---parser.sharedPlayers remembers the file's way: written back shared while every model is the same
---(writeParser), as full sections for every player once they differ (or a player has none: reset)
---@param parser FileParserResult
---@param playerCount integer
function FileHandler.splitSharedPlayers(parser, playerCount)
    local shared = FileHandler.getSharedPlayerLines(parser)
    if not shared then return end
    for _, key in ipairs(PLAYER_LISTS) do
        if parser[key] then parser[key] = withoutSharedParts(parser[key]) end
    end
    for id = 0, playerCount - 1 do
        local own = FileHandler.getPlayerLines(parser, id)
        local lines = {}
        if own then
            local ownParts, taken = partsOf(own), {}
            for _, part in ipairs(ownParts) do taken[part.key] = true end
            for _, part in ipairs(partsOf(shared)) do
                if not taken[part.key] then
                    for _, line in ipairs(part.lines) do lines[#lines + 1] = line end
                end
            end
            for _, part in ipairs(ownParts) do
                for _, line in ipairs(part.lines) do lines[#lines + 1] = line end
            end
        else
            for i, line in ipairs(shared) do lines[i] = line end
        end
        FileHandler.setPlayerLines(parser, id, lines)
    end
    parser.sharedPlayers = playerCount -- how many got the shared model: written shared only while all still have it
end

---For writing a mod that came with shared parts (splitSharedPlayers): while every player section is the same,
---one copy of it as shared parts in place of the sections, else nil (the sections are written as they are)
---@param parser FileParserResult
---@return string[]? ignores, string[]? trailer
local function collapsedShared(parser)
    if not parser.sharedPlayers then return nil, nil end
    local first, ids = nil, {}
    for _, key in ipairs(PLAYER_LISTS) do
        for _, line in ipairs(parser[key] or {}) do
            local id = tonumber(line:match("^%s*player%s+(%d+)%s*$"))
            if id then ids[#ids + 1] = id end
        end
    end
    -- shared only when every player has a section: a player reset to the default body (its section removed)
    -- would get the model back from shared parts
    if #ids == 0 or #ids < (tonumber(parser.sharedPlayers) or 0) then return nil, nil end
    for _, id in ipairs(ids) do
        local text = table.concat(FileHandler.getPlayerLines(parser, id) or {}, "\n")
        if first == nil then first = text elseif text ~= first then return nil, nil end
    end
    local model = FileHandler.getPlayerLines(parser, ids[1]) or {}
    local copy = { ignores = parser.ignores, trailer = parser.trailer }
    local map = {}
    for _, id in ipairs(ids) do map[id] = false end
    FileHandler.renumberPlayers(copy, map)
    local trailer = {}
    for _, line in ipairs(copy.trailer or {}) do trailer[#trailer + 1] = line end
    if #trailer > 0 and not trailer[#trailer]:match("^%s*$") then trailer[#trailer + 1] = "" end
    -- as in a section (indented parts, their lines indented twice): how fatkido.tbm writes its shared ones
    for _, line in ipairs(model) do trailer[#trailer + 1] = line end
    return copy.ignores, trailer
end

-- numplayers goes first in the section, like in the game's own mods: the game reads the rules in
-- order, and the per-player lists after it (engageplayerpos / engageplayerrot) are read for that many
-- players. Written after them, a one-player mod's 3-number positions were read for two players and lost
local FIRST_RULE = "numplayers"

---Writes gamerule values into the `gamerule` section: existing lines get the new value (indentation
---kept), missing rules are added at the end of the section, the section is added when the mod has none.
---The numplayers line is moved / added right after the header (FIRST_RULE).
---The section is its rule lines, blanks and comments after the header (some mods don't indent rules).
---ignores/trailer are replaced with new tables, not modified: history states share them
---@param parser FileParserResult
---@param values table<string, string> rules to write
---@param ruleNames table<string, any> every gamerule name, tells rule lines from what comes after the section
function FileHandler.setGamerules(parser, values, ruleNames)
    local pending = {}
    for name in pairs(values) do table.insert(pending, name) end
    table.sort(pending, function(a, b)
        if (a == FIRST_RULE) ~= (b == FIRST_RULE) then return a == FIRST_RULE end
        return a < b
    end)

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
            local firstLine -- the numplayers line, put back right after the header at the end
            local i = header + 1
            while i <= #list do
                local line = list[i]
                local word = firstWord(line)
                -- the section ends at the next section (player, env_obj...) or an unindented line that
                -- isn't a rule. Indented words the game's rule list doesn't have (engagespace in some
                -- mods) are still rules: stopping at them left the rules after them unchanged and
                -- added a second line above, the game then read the old value from the later line
                local comment = word and (word:match("^#") or word:match("^//"))
                if word and not comment and (SECTION_WORDS[word] and word ~= "gamerule"
                    or (not ruleNames[word] and not line:match("^%s"))) then break end
                if word and values[word] ~= nil then
                    line = line:match("^(%s*)") .. word .. " " .. values[word]
                    written[word] = true
                end
                if word == FIRST_RULE and not firstLine then
                    firstLine = line
                else
                    table.insert(lines, line)
                    if word then last = #lines end
                end
                i = i + 1
            end
            -- new rules go right after the last rule line, blank lines stay after them
            local added = {}
            for _, name in ipairs(pending) do
                if not written[name] then
                    local line = indent .. name .. " " .. values[name]
                    if name == FIRST_RULE then firstLine = line else table.insert(added, line) end
                end
            end
            for n, line in ipairs(added) do table.insert(lines, last + n, line) end
            if firstLine then table.insert(lines, header + 1, firstLine) end
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
    -- a mod that came with shared player parts goes back that way while every model is the same
    local ignores, trailer = collapsedShared(parser)
    if ignores then parser = { ignores = ignores, trailer = trailer, env_obj = parser.env_obj,
        env_obj_joint = parser.env_obj_joint } end
    -- Write ignored lines first (headers, gamerules, etc.)
    for _, line in ipairs(parser.ignores or {}) do
        file:writeLine(line)
    end

    -- Write env_obj and env_obj_joint blocks in order
    writeParsedEnvObj(file, parser.env_obj or {})
    writeParsedEnvObj(file, parser.env_obj_joint or {})

    -- atmo objects aren't written: they're the atmo layer, kept in the mod's .atmo (utils/atmo.lua)

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
