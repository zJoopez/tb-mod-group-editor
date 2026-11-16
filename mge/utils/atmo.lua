














local FileHandler = MGE.FileHandler
local ModData = MGE.ModData


local Atmo = {
    folder = "../data/atmospheres/",
    prefix = "MGE - ",


    state = { header = {} },


    headerVersion = 0,
}
MGE.Atmo = Atmo

local indent = "   "








function Atmo.parse(lines)
    local file = { header = {}, objects = {}, trailer = {} }
    local i = 1
    while i <= #lines and not lines[i]:match("^%s*env_obj%s") do
        file.header[#file.header + 1] = lines[i]
        i = i + 1
    end
    while i <= #lines do
        local name = lines[i]:match("^%s*env_obj%s+(.-)%s*$")
        if name then
            local block = { kind = "env_obj", header = "env_obj 0", lines = {} }
            i = i + 1
            while i <= #lines and not lines[i]:match("^%s*env_obj%s") and not lines[i]:match("^%s*player%s") do
                if not lines[i]:match("^%s*$") then block.lines[#block.lines + 1] = lines[i] end
                i = i + 1
            end
            local obj = FileHandler.parseBlock(block)

            if obj.props.size ~= nil then
                obj.props.sides = obj.props.sides or obj.props.size
                obj.props.size = nil
                for _, entry in ipairs(obj.lines) do
                    if entry.key == "size" then entry.key = "sides" end
                end
            end
            obj.atmoName, obj.kind = name, "atmo"
            file.objects[#file.objects + 1] = obj
            obj.id = #file.objects
        else

            file.trailer[#file.trailer + 1] = lines[i]
            i = i + 1
        end
    end
    while #file.header > 0 and file.header[#file.header]:match("^%s*$") do table.remove(file.header) end
    while #file.trailer > 0 and file.trailer[#file.trailer]:match("^%s*$") do table.remove(file.trailer) end
    return file
end


local KEY_ORDER = { "shape", "pos", "rot", "sides", "color" }
local KEY_RANK = {}
for i, key in ipairs(KEY_ORDER) do KEY_RANK[key] = i end



local function fileKey(key) return key == "sides" and "size" or key end




function Atmo.text(file)
    local lines = {}
    for _, line in ipairs(file.header or {}) do lines[#lines + 1] = line end
    if #lines > 0 then lines[#lines + 1] = "" end

    local used = {}
    for _, obj in ipairs(file.objects) do
        if obj.atmoName then used[obj.atmoName] = true end
    end
    local next = 0
    for _, obj in ipairs(file.objects) do
        local name = obj.atmoName
        if not name then
            repeat
                next = next + 1
                name = "mge_" .. next
            until not used[name]
            used[name] = true
        end
        lines[#lines + 1] = "env_obj " .. name
        local props, written = obj.props or {}, {}
        for _, entry in ipairs(obj.lines or {}) do
            if entry.raw then
                lines[#lines + 1] = indent .. entry.raw
            elseif props[entry.key] ~= nil and not written[entry.key] then
                written[entry.key] = true
                lines[#lines + 1] = indent .. fileKey(entry.key) .. " " .. props[entry.key]
            end
        end
        local rest = {}
        for key in pairs(props) do
            if not written[key] then rest[#rest + 1] = key end
        end
        table.sort(rest, function(a, b)
            local ra, rb = KEY_RANK[a] or math.huge, KEY_RANK[b] or math.huge
            if ra ~= rb then return ra < rb end
            return a < b
        end)
        for _, key in ipairs(rest) do lines[#lines + 1] = indent .. fileKey(key) .. " " .. props[key] end
        lines[#lines + 1] = ""
    end
    for _, line in ipairs(file.trailer or {}) do lines[#lines + 1] = line end
    return table.concat(lines, "\n")
end






function Atmo.fromMod(obj)
    local c = obj.props.color
    if not c then return end
    local n = {}
    for v in c:gmatch("%S+") do n[#n + 1] = tonumber(v) or 1 end
    local over = false
    for k = 1, 4 do
        local v = n[k] or 1
        local clamped = math.min(math.max(v, 0), k == 4 and 1 or 2)
        if clamped ~= v then over = true end
        n[k] = clamped
    end
    if over then obj.props.color = FileHandler.formatNumbers(n[1], n[2], n[3], n[4]) end
end




function Atmo.fileName(modPath)
    local name = tostring(modPath or ""):gsub("^.*[/\\]", ""):gsub("%.tbm$", "")
    if name == "" then return nil end
    return Atmo.prefix .. name .. ".atmo"
end








function Atmo.saveAction(text, count, target, saved, exists)
    if exists and saved.name == target and saved.text == text then return "none" end
    if count == 0 then return exists and "empty" or "none" end
    return "write"
end




function Atmo.contentCount()
    local count = #(ModData.parsed.atmo or {})
    for _, line in ipairs(Atmo.state.header) do
        if line:match("^%s*shader%s+%S") then return count + 1 end
    end
    return count
end



function Atmo.currentText()
    return Atmo.text({ header = Atmo.state.header, objects = ModData.parsed.atmo or {} })
end



function Atmo.hasChanges()
    if Atmo.state.text == nil then return Atmo.contentCount() > 0 end
    return Atmo.currentText() ~= Atmo.state.text
end



local function readLines(name)
    local file = Files.Open(Atmo.folder .. name, FILES_MODE_READONLY)
    if not file or not file.data then return nil end
    local lines = file:readAll()
    file:close()
    return lines
end








MGE_SHADER_BEFORE = MGE_SHADER_BEFORE


function Atmo.rememberShader()
    if MGE_SHADER_BEFORE or not get_shader_name then return end
    MGE_SHADER_BEFORE = (tostring(get_shader_name() or ""):gsub("^data/shader/", ""))
end


function Atmo.shaderName()
    for _, line in ipairs(Atmo.state.header or {}) do
        local name = line:match("^%s*shader%s+(.-)%s*$")
        if name and name ~= "" then return name end
    end
    return nil
end



function Atmo.applyShader(restore)
    if not runCmd then return end
    local name = not restore and Atmo.shaderName() or nil
    local file
    if name then
        file = name:find("%.inc$") and name or (name .. ".inc")
    else
        file = (MGE_SHADER_BEFORE and MGE_SHADER_BEFORE ~= "") and MGE_SHADER_BEFORE or "default.inc"
    end
    if file == Atmo.appliedShader then return end
    Atmo.appliedShader = file
    runCmd("lws " .. file)
end

function Atmo.load(modPath)
    local name = Atmo.fileName(modPath)
    local lines = name and readLines(name)
    if not lines then
        ModData.parsed.atmo = {}
        Atmo.state = { name = name, text = nil, header = {} }
        return
    end
    local file = Atmo.parse(lines)
    ModData.parsed.atmo = file.objects
    Atmo.state = { name = name, header = file.header }
    Atmo.state.text = Atmo.currentText()
    MGE.say("atmo: " .. #file.objects .. " objects from data/atmospheres/" .. name)
end



local function exists(name)
    return Files.Exists(Atmo.folder .. name)
end





local function write(name, text)
    local file = Files.Open(Atmo.folder .. name, FILES_MODE_WRITE)
    if not file or not file.data then
        MGE.say("couldn't write data/atmospheres/" .. name)
        return false
    end
    for line in (text .. "\n"):gmatch("(.-)\n") do file:writeLine(line) end
    file:close()
    return true
end




function Atmo.saveFor(modPath)
    local name = Atmo.fileName(modPath)
    if not name then return end
    local atmoObjs = ModData.parsed.atmo or {}
    local text = Atmo.currentText()
    local action = Atmo.saveAction(text, Atmo.contentCount(), name, Atmo.state, exists(name))
    if action == "write" then
        if write(name, text) then
            Atmo.state.name, Atmo.state.text = name, text
            MGE.say("saved data/atmospheres/" .. name .. " (" .. #atmoObjs .. " atmo objects)")
        end
    elseif action == "empty" then
        MGE.confirm("No atmo objects left. Empty data/atmospheres/" .. name .. "?", function()
            if write(name, text) then
                Atmo.state.name, Atmo.state.text = name, text
                MGE.say("emptied data/atmospheres/" .. name .. " (scripts can't delete files: delete it by hand if you like)")
            end
        end)
    else
        Atmo.state.name = name
    end
end

return Atmo
