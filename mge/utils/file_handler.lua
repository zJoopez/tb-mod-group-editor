local FileHandler = {}
MGE.FileHandler = FileHandler




local DECIMALS = 10





local NUMBER_FORMAT = "%." .. DECIMALS .. "f"
function FileHandler.formatNumber(value)


    local s = string.format(NUMBER_FORMAT, value):match("^(.-)%.?0*$")
    if s == "-0" then s = "0" end
    return s
end



function FileHandler.formatNumbers(...)
    local parts = {}
    for i, v in ipairs({ ... }) do parts[i] = FileHandler.formatNumber(v) end
    return table.concat(parts, " ")
end































local indent = "   "


local SECTION_WORDS = {
    gamerule = true,
    body = true,
    joint = true,
    player = true,
    env_obj = true,
    env_obj_joint = true,
}


local KEY_ORDER = {
    "shape", "pos", "rot", "sides", "color", "flag", "material", "mass", "bounce", "friction",
    "force", "hardness", "visible", "thrust", "model_name", "use_model",
}
local KEY_RANK = {}
for i, key in ipairs(KEY_ORDER) do KEY_RANK[key] = i end



local FRAME_TAG = "#mge_frame"



local function firstWord(line)
    return line:match("^%s*(%S+)")
end



local function getBlockKind(line)
    local word = firstWord(line)
    if (word == "env_obj" or word == "env_obj_joint") and line:match("^%s*%S+%s+%d") then
        return word
    end
end



local function isSectionHeader(line)
    return SECTION_WORDS[firstWord(line) or ""] == true
end



local function trimTrailingBlank(list)
    while #list > 0 and list[#list]:match("^%s*$") do
        table.remove(list)
    end
end



function FileHandler.ParseMod(path)
    local file = Files.Open(path, FILES_MODE_READONLY)


    local parser = {
        env_obj = {},
        env_obj_joint = {},
        atmo = {},
        ignores = {},
        trailer = {},
    }

    if not file or not file.data then return parser end

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

            if obj.props[key] == nil then table.insert(obj.lines, { key = key }) end
            obj.props[key] = value
        elseif key == FRAME_TAG then

        else

            table.insert(obj.lines, { raw = (line:gsub("^%s+", ""):gsub("%s+$", "")) })
        end
    end

    return obj
end


local function buildHeader(obj)
    if not obj then return "" end
    if obj.kind == "env_obj_joint" then
        return string.format("%s %d %d %d", obj.kind, obj.id or 0, obj.obj1 or 0, obj.obj2 or 0)
    end
    return string.format("%s %d", obj.kind, obj.id or 0)
end




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


local PLAYER_PART_WORDS = { body = true, joint = true }





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








local function findPlayerSection(lines, playerId)
    for i, line in ipairs(lines) do
        local id = tonumber(line:match("^%s*player%s+(%d+)%s*$"))
        if id and (playerId == nil or id == playerId) then
            return i, sectionLast(lines, i), id
        end
    end
    return nil, nil, nil
end


local PLAYER_LISTS = { "ignores", "trailer" }






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





function FileHandler.getSharedPlayerLines(parser)
    local parts = {}
    for _, key in ipairs(PLAYER_LISTS) do
        local inPlayer, inPart = false, false
        for _, line in ipairs(parser[key] or {}) do
            local word = firstWord(line)
            if word then

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






function FileHandler.setPlayerLines(parser, playerId, parts)
    for _, key in ipairs(PLAYER_LISTS) do
        local list = parser[key] or {}
        local first, last = findPlayerSection(list, playerId)
        if first then
            local lines = {}
            for i = 1, first do table.insert(lines, list[i]) end
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
                    if #lines == 0 then
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


FileHandler.MOD_VERSION = 15







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
    parser.sharedPlayers = playerCount
end





local function collapsedShared(parser)
    if not parser.sharedPlayers then return nil, nil end
    local first, ids = nil, {}
    for _, key in ipairs(PLAYER_LISTS) do
        for _, line in ipairs(parser[key] or {}) do
            local id = tonumber(line:match("^%s*player%s+(%d+)%s*$"))
            if id then ids[#ids + 1] = id end
        end
    end


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

    for _, line in ipairs(model) do trailer[#trailer + 1] = line end
    return copy.ignores, trailer
end




local FIRST_RULE = "numplayers"









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
            local firstLine
            local i = header + 1
            while i <= #list do
                local line = list[i]
                local word = firstWord(line)




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




local function writeParser(file, parser)

    local ignores, trailer = collapsedShared(parser)
    if ignores then parser = { ignores = ignores, trailer = trailer, env_obj = parser.env_obj,
        env_obj_joint = parser.env_obj_joint } end

    for _, line in ipairs(parser.ignores or {}) do
        file:writeLine(line)
    end


    writeParsedEnvObj(file, parser.env_obj or {})
    writeParsedEnvObj(file, parser.env_obj_joint or {})




    for _, line in ipairs(parser.trailer or {}) do
        file:writeLine(line)
    end
end




function FileHandler.WriteMod(parser, path)
    local file = Files.Open(path, FILES_MODE_WRITE)
    if not file or not file.data then return false end

    writeParser(file, parser)
    file:close()
    return true
end





function FileHandler.modText(parser)
    local lines = {}
    writeParser({ writeLine = function(_, line) table.insert(lines, line) end }, parser)
    return table.concat(lines, "\n")
end
