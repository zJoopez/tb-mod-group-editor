-- Map converter baseline: what the converter keeps and drops on every map in mge/assets/maps, recorded
-- once and checked after a change, so a rule tuned for one map can't quietly change another (the sky
-- clip rules removed dust2's walls that way). Clips are on, the rest are the converter's defaults.
--
--   lua5.1 tools/mapconv_baseline.lua record [filter]   writes mge/assets/maps/baseline.txt
--   lua5.1 tools/mapconv_baseline.lua check [filter]    compares with it (exit code 1 on a difference)
--
-- filter: only maps whose file name contains it (record then keeps the other maps' entries). Per map
-- it keeps the brush and piece counts by role, every dropped reason's count, and the brush ids of the
-- clips kept: a check names the clips a change now drops or keeps. The maps and the baseline are local
-- (assets/ is gitignored): record again after a change you've checked in game. Takes a few minutes for
-- all of them, the big .bsp files take seconds each.
local mode, filter = arg[1], arg[2]
if mode ~= "record" and mode ~= "check" then
    print("usage: lua5.1 tools/mapconv_baseline.lua record|check [filter]")
    os.exit(2)
end

local root = (arg[0]:match("^(.*[/\\])") or "./") .. "../"
MGE = { scriptPath = root .. "mge/" }
for _, m in ipairs({ "utils/mat3.lua", "utils/file_handler.lua", "utils/mod_export.lua" }) do
    dofile(MGE.scriptPath .. m)
end
for _, m in ipairs(dofile(MGE.scriptPath .. "mapconv/modules.lua")) do dofile(MGE.scriptPath .. m) end
local MapConv = MGE.MapConv
local mapDir = MGE.scriptPath .. "assets/maps/"
local baselinePath = mapDir .. "baseline.txt"

---Map file names in the folder, sorted
---@return string[]
local function listMaps()
    local names = {}
    local windows = package.config:sub(1, 1) == "\\"
    local cmd = windows and ('dir /b "' .. mapDir:gsub("/", "\\") .. '" 2>nul') or ('ls "' .. mapDir .. '" 2>/dev/null')
    local pipe = io.popen(cmd)
    if pipe then
        for name in pipe:lines() do
            if name:match("%.bsp$") or name:match("%.vmf$") then names[#names + 1] = name end
        end
        pipe:close()
    end
    table.sort(names)
    return names
end

---One map's entry: "key value" counts and the kept clips' brush ids
---@param name string
---@return { counts: table<string, number>, clips: integer[] }
local function measure(name)
    local f = assert(io.open(mapDir .. name, "rb"))
    local map = MapConv.parse(f, name)
    f:close()
    local pieces, report = MapConv.pieces(map, MapConv.withDefaults({ clips = true }))
    local counts = { brushes = report.brushes or #map.brushes, pieces = #pieces, roofs = report.roofs or 0 }
    for reason, n in pairs(report.dropped) do counts["dropped." .. reason] = n end
    local clipSet = {}
    for _, p in ipairs(pieces) do
        local key = "role." .. tostring(p.role or "solid")
        counts[key] = (counts[key] or 0) + 1
        if p.role == "clip" and p.brushId then clipSet[p.brushId] = true end
    end
    local clips = {}
    for id in pairs(clipSet) do clips[#clips + 1] = id end
    table.sort(clips, function(a, b) return tostring(a) < tostring(b) end)
    return { counts = counts, clips = clips }
end

---Entries by map name, and the names in file order
---@return table<string, { counts: table<string, number>, clips: string[] }>
---@return string[]
local function readBaseline()
    local entries, order = {}, {}
    local f = io.open(baselinePath, "r")
    if not f then return entries, order end
    local current
    for line in f:lines() do
        local map = line:match("^map (.+)$")
        if map then
            current = { counts = {}, clips = {} }
            entries[map] = current
            order[#order + 1] = map
        elseif current then
            local key, value = line:match("^  (%S+) (%S+)$")
            if key then current.counts[key] = tonumber(value) end
            local ids = line:match("^  clips:(.*)$")
            if ids then for id in ids:gmatch("%S+") do current.clips[#current.clips + 1] = id end end
        end
    end
    f:close()
    return entries, order
end

---@param entries table
---@param order string[]
local function writeBaseline(entries, order)
    local f = assert(io.open(baselinePath, "w"))
    f:write("# map converter baseline (tools/mapconv_baseline.lua), clips on, written ", os.date("%Y-%m-%d"), "\n")
    for _, name in ipairs(order) do
        local e = entries[name]
        f:write("map ", name, "\n")
        local keys = {}
        for k in pairs(e.counts) do keys[#keys + 1] = k end
        table.sort(keys)
        for _, k in ipairs(keys) do f:write("  ", k, " ", tostring(e.counts[k]), "\n") end
        local ids = {}
        for i, id in ipairs(e.clips) do ids[i] = tostring(id) end
        f:write("  clips:", #ids > 0 and (" " .. table.concat(ids, " ")) or "", "\n")
    end
    f:close()
end

---@param list string[]
---@return string
local function shortList(list)
    if #list <= 12 then return table.concat(list, " ") end
    local first = {}
    for i = 1, 12 do first[i] = list[i] end
    return table.concat(first, " ") .. " ... (" .. #list .. ")"
end

local baseline, order = readBaseline()
if mode == "check" and not next(baseline) then
    print("no baseline at " .. baselinePath .. ": run record first")
    os.exit(2)
end

local differences, checked = 0, 0
for _, name in ipairs(listMaps()) do
    if not filter or name:find(filter, 1, true) then
        local started = os.clock()
        local ok, result = pcall(measure, name)
        local took = string.format("%.1f s", os.clock() - started)
        if not ok then
            print(name .. ": FAILED " .. tostring(result))
            differences = differences + 1
        elseif mode == "record" then
            if not baseline[name] then order[#order + 1] = name end
            local ids = {}
            for i, id in ipairs(result.clips) do ids[i] = tostring(id) end
            baseline[name] = { counts = result.counts, clips = ids }
            print(string.format("%-22s recorded, %d clips kept (%s)", name, #ids, took))
        else
            checked = checked + 1
            local old = baseline[name]
            if not old then
                print(name .. ": not in the baseline (record it)")
            else
                local lines = {}
                local keys = {}
                for k in pairs(old.counts) do keys[k] = true end
                for k in pairs(result.counts) do keys[k] = true end
                local sorted = {}
                for k in pairs(keys) do sorted[#sorted + 1] = k end
                table.sort(sorted)
                for _, k in ipairs(sorted) do
                    local a, b = old.counts[k] or 0, result.counts[k] or 0
                    if a ~= b then lines[#lines + 1] = string.format("    %s %d -> %d", k, a, b) end
                end
                local was, now = {}, {}
                for _, id in ipairs(old.clips) do was[id] = true end
                for _, id in ipairs(result.clips) do now[tostring(id)] = true end
                local dropped, kept = {}, {}
                for _, id in ipairs(old.clips) do if not now[id] then dropped[#dropped + 1] = id end end
                for id in pairs(now) do if not was[id] then kept[#kept + 1] = id end end
                table.sort(kept)
                if #dropped > 0 then lines[#lines + 1] = "    clips now dropped (brush ids): " .. shortList(dropped) end
                if #kept > 0 then lines[#lines + 1] = "    clips now kept (brush ids): " .. shortList(kept) end
                if #lines == 0 then
                    print(string.format("%-22s same (%s)", name, took))
                else
                    differences = differences + 1
                    print(string.format("%-22s CHANGED (%s)", name, took))
                    for _, l in ipairs(lines) do print(l) end
                end
            end
        end
    end
end

if mode == "record" then
    writeBaseline(baseline, order)
    print("written " .. baselinePath)
else
    print(string.format("%d maps checked, %d changed", checked, differences))
    os.exit(differences > 0 and 1 or 0)
end
