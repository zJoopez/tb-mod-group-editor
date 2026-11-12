-- Map converter: props, the models placed in a map (crates, doors, cars, railings). A map only says
-- which model goes where (position, angles, solid or not), the model's size is in its .mdl file:
-- in the map's own packed files (a zip in the .bsp, custom maps) or in the game's archives (.vpk, e.g.
-- Counter-Strike Global Offensive/csgo/pak01_dir.vpk). Each solid prop becomes one box: the model's
-- bounds (its .mdl header), turned and scaled like the prop. Found sizes are kept in a cache file next
-- to the map (Props.cacheText / readCache), so the archives are read once, and a cache made by the
-- command line tool works in game too.
-- Lists come from a .bsp's static prop lump (bsp.lua) and from prop entities (.vmf and .bsp)
MGE.MapConv = MGE.MapConv or {}
local MapConv = MGE.MapConv

local Props = {}
MapConv.Props = Props

local Bsp = MapConv.Bsp
local u16, i32, f32 = Bsp.u16, Bsp.i32, Bsp.f32

---@class MapProp
---@field id string "prop 12" (static) or "entity 3"
---@field model string path in the game's files, lower case, "/" separated, e.g. "models/props/crate.mdl"
---@field origin number[] map units
---@field angles number[] pitch, yaw, roll in degrees (Source order)
---@field scale number
---@field solid boolean
---@field mins number[]? model bounds, set by Props.resolve
---@field maxs number[]?

-- props left out even when solid: their box would be a block where there's mostly air (a palm tree's
-- canopy, a cable's sag). Matched in the lower case model path. "autocombine": CS:GO's compiler merges
-- scattered small props (curbs, trims, window frames) into one model, its box spans whole streets.
-- Frames, arches and column pairs: their box fills the opening they frame (dust2's tunnel entrances,
-- doorways, the passages under arches)
Props.SKIP = { "foliage", "tree", "palm", "bush", "plant", "grass", "flower", "vine", "wire", "cable", "antenna", "rope",
    "autocombine", "frame", "arch", "doorway", "columns" }

-- prop entities with a model of their own (doors, physics crates). prop_static is an entity only in .vmf
local ENTITY_CLASSES = {
    prop_static = true, prop_dynamic = true, prop_dynamic_override = true, prop_physics = true,
    prop_physics_override = true, prop_physics_multiplayer = true, prop_door_rotating = true,
}

---@param name string
---@return string lower case, "/" separated
local function normalize(name)
    return (name:gsub("\\", "/"):gsub("^/+", ""):lower())
end
Props.normalize = normalize

---Static props of a .bsp: the game lump "sprp" (ids are stored backwards: "prps"). Records grow with
---the lump version, their size is worked out from the lump; position, angles, model and solid come
---first in every version, newer ones (11+, CS:GO) end with a scale
---@param read BspReader
---@param gameLump string the game lump directory
---@return MapProp[]
function Props.staticProps(read, gameLump)
    local props = {}
    if #gameLump < 4 then return props end
    for i = 0, i32(gameLump, 1) - 1 do
        local p = 5 + i * 16
        if gameLump:sub(p, p + 3) == "prps" then
            local flags, version = u16(gameLump, p + 4), u16(gameLump, p + 6)
            local offset, length = i32(gameLump, p + 8), i32(gameLump, p + 12)
            if flags % 2 == 1 then return props end -- compressed (consoles), not read
            local data = read(offset, length)
            local names = {}
            local count = i32(data, 1)
            for n = 0, count - 1 do
                names[n] = normalize((data:sub(5 + n * 128, 4 + (n + 1) * 128):gsub("%z.*$", "")))
            end
            local q = 5 + count * 128
            q = q + 4 + i32(data, q) * 2 -- leaf list
            local propCount = i32(data, q)
            q = q + 4
            if propCount <= 0 then return props end
            local size = (#data - q + 1) / propCount
            if size ~= math.floor(size) or size < 32 then return props end -- unknown layout
            for n = 0, propCount - 1 do
                local r = q + n * size
                local model = names[u16(data, r + 24)]
                if model then
                    local scale = 1
                    if version >= 11 and size >= 80 then
                        scale = f32(data, r + size - 4)
                        if not (scale > 0) then scale = 1 end
                    end
                    props[#props + 1] = {
                        id = "prop " .. n,
                        model = model,
                        origin = { f32(data, r), f32(data, r + 4), f32(data, r + 8) },
                        angles = { f32(data, r + 12), f32(data, r + 16), f32(data, r + 20) },
                        scale = scale,
                        solid = data:byte(r + 30) ~= 0, -- 0: not solid
                    }
                end
            end
            return props
        end
    end
    return props
end

---Prop entities of the map (its "model", "origin", "angles" and "solid" keys) added to map.props
---@param map MapFile
function Props.addEntityProps(map)
    map.props = map.props or {}
    for i, entity in ipairs(map.entities) do
        local p = entity.props
        if ENTITY_CLASSES[entity.classname] and p.model and p.model:lower():find("%.mdl$") and entity.origin then
            local angles = MapConv.Vmf.readVector(p.angles) or { 0, 0, 0 }
            table.insert(map.props, {
                id = "entity " .. i,
                model = normalize(p.model),
                origin = entity.origin,
                angles = angles,
                scale = tonumber(p.modelscale) or 1,
                solid = p.solid ~= "0",
            })
        end
    end
end

---@alias PropSource fun(model: string, length: integer): string? the model file's first bytes, nil when it isn't there

local HEADER_SIZE = 152 -- studiohdr_t up to view_bbmax

---Bounds from a .mdl header: the hull, or the view box when the hull is empty
---@param header string
---@return number[]? mins, number[]? maxs
function Props.boundsFromHeader(header)
    if #header < HEADER_SIZE or header:sub(1, 4) ~= "IDST" then return nil end
    local function vec(pos) return { f32(header, pos), f32(header, pos + 4), f32(header, pos + 8) } end
    for _, at in ipairs({ 105, 129 }) do -- hull_min / hull_max, view_bbmin / view_bbmax
        local mins, maxs = vec(at), vec(at + 12)
        local ok = true
        for k = 1, 3 do
            if not (maxs[k] - mins[k] > 0.01) or math.abs(mins[k]) > 1e5 or math.abs(maxs[k]) > 1e5 then ok = false end
        end
        if ok then return mins, maxs end
    end
    return nil
end

---Files in a zip (a .bsp's packed files), stored ones only (how maps pack them; others are skipped)
---@param read BspReader the .bsp
---@param offset integer where the zip starts in the .bsp
---@param length integer
---@return PropSource?
function Props.zipSource(read, offset, length)
    local tailLength = math.min(length, 65536 + 22)
    local tail = read(offset + length - tailLength, tailLength)
    local eocd
    local from = 1
    while true do -- the last end-of-directory record
        local at = tail:find("PK\5\6", from, true)
        if not at then break end
        eocd, from = at, at + 1
    end
    if not eocd then return nil end
    local entries, dirSize, dirOffset = u16(tail, eocd + 10), i32(tail, eocd + 12), i32(tail, eocd + 16)
    local dir = read(offset + dirOffset, dirSize)
    local files = {}
    local p = 1
    for _ = 1, entries do
        if dir:sub(p, p + 3) ~= "PK\1\2" then break end
        local method, size = u16(dir, p + 10), i32(dir, p + 20)
        local nameLength, extraLength, commentLength = u16(dir, p + 28), u16(dir, p + 30), u16(dir, p + 32)
        local name = normalize(dir:sub(p + 46, p + 45 + nameLength))
        if method == 0 and name:find("%.mdl$") then
            files[name] = { size = size, localOffset = i32(dir, p + 42) }
        end
        p = p + 46 + nameLength + extraLength + commentLength
    end
    return function(model, want)
        local entry = files[model]
        if not entry then return nil end
        local localHeader = read(offset + entry.localOffset, 30)
        if localHeader:sub(1, 4) ~= "PK\3\4" then return nil end
        local start = offset + entry.localOffset + 30 + u16(localHeader, 27) + u16(localHeader, 29)
        return read(start, math.min(want, entry.size))
    end
end

---Files in a game archive: the _dir.vpk (v1 or v2) and its numbered parts (_000.vpk...). Only .mdl
---entries are indexed. Parts are opened when a model in them is read, closed by the source's close()
---@param dirPath string path of the _dir.vpk, as open takes it
---@param open fun(path: string): any? opens a file in binary mode (io.open, the game's with root)
---@return PropSource? source, fun()? close
function Props.vpkSource(dirPath, open)
    local file = open(dirPath)
    if not file then return nil end
    local head = file:read(28) or ""
    if #head < 12 or i32(head, 1) ~= 0x55aa1234 then
        file:close()
        return nil
    end
    local version, treeSize = i32(head, 5), i32(head, 9)
    local headerSize = version == 2 and 28 or 12
    file:seek("set", headerSize)
    local tree = file:read(treeSize) or ""
    local entries = {}
    local p = 1
    local function text()
        local stop = tree:find("\0", p, true)
        if not stop then return nil end
        local s = tree:sub(p, stop - 1)
        p = stop + 1
        return s
    end
    while true do
        local ext = text()
        if not ext or ext == "" then break end
        local wanted = ext:lower() == "mdl"
        while true do
            local path = text()
            if not path or path == "" then break end
            while true do
                local name = text()
                if not name or name == "" then break end
                local preload, archive = u16(tree, p + 4), u16(tree, p + 6)
                if wanted then
                    local full = normalize((path == " " and "" or path .. "/") .. name .. "." .. ext)
                    entries[full] = {
                        archive = archive,
                        offset = i32(tree, p + 8),
                        length = i32(tree, p + 12),
                        preload = preload > 0 and tree:sub(p + 18, p + 17 + preload) or "",
                    }
                end
                p = p + 18 + preload
            end
        end
    end
    local parts = {}
    local base = dirPath:gsub("_dir%.vpk$", "")
    local function close()
        for _, part in pairs(parts) do if part then part:close() end end
        parts = {}
        if file then file:close() end
        file = nil
    end
    local dataStart = headerSize + treeSize -- archive 0x7fff: the data is in the _dir.vpk after the tree
    return function(model, want)
        local entry = entries[model]
        if not entry then return nil end
        local bytes = entry.preload
        if #bytes >= want or entry.length == 0 then return bytes:sub(1, want) end
        local part, at
        if entry.archive == 0x7fff then
            part, at = file, dataStart + entry.offset
        else
            if parts[entry.archive] == nil then
                parts[entry.archive] = open(string.format("%s_%03d.vpk", base, entry.archive)) or false
            end
            part, at = parts[entry.archive], entry.offset
        end
        if not part then return nil end
        part:seek("set", at)
        return bytes .. (part:read(math.min(want - #bytes, entry.length)) or "")
    end, close
end

-- where games keep their archives, from the folder that holds the game folders (Steam's "common")
Props.GAME_ARCHIVES = {
    "Counter-Strike Global Offensive/csgo/pak01_dir.vpk",
    "Counter-Strike Source/cstrike/cstrike_pak_dir.vpk",
    "Team Fortress 2/tf/tf2_misc_dir.vpk",
    "GarrysMod/garrysmod/garrysmod_dir.vpk",
    "Half-Life 2/hl2/hl2_misc_dir.vpk",
    "Half-Life 2/hl2/hl2_textures_dir.vpk",
}

---Cache file text: one model a line, "model minx miny minz maxx maxy maxz", or "model -" when no file had it
---@param bounds table<string, { mins: number[], maxs: number[] }|false>
---@return string
function Props.cacheText(bounds)
    local names = {}
    for name in pairs(bounds) do names[#names + 1] = name end
    table.sort(names)
    local lines = { "# MGE mapconv model sizes: model mins maxs (map units), - when not found" }
    for _, name in ipairs(names) do
        local b = bounds[name]
        -- 17 digits read back as the same number exactly: the cache gives the same boxes as the files
        lines[#lines + 1] = b and string.format("%s %.17g %.17g %.17g %.17g %.17g %.17g", name, b.mins[1], b.mins[2], b.mins[3],
            b.maxs[1], b.maxs[2], b.maxs[3]) or (name .. " -")
    end
    return table.concat(lines, "\n") .. "\n"
end

---@param text string? a cache file's text
---@return table<string, { mins: number[], maxs: number[] }|false>
function Props.readCache(text)
    local bounds = {}
    for line in tostring(text or ""):gmatch("[^\r\n]+") do
        local name, rest = line:match("^(%S+)%s+(.+)$")
        if name and not name:find("^#") then
            local v = {}
            for n in rest:gmatch("%S+") do v[#v + 1] = tonumber(n) end
            if #v == 6 then
                bounds[name] = { mins = { v[1], v[2], v[3] }, maxs = { v[4], v[5], v[6] } }
            elseif rest == "-" then
                bounds[name] = false
            end
        end
    end
    return bounds
end

---@class PropResolveResult
---@field found integer models with a size
---@field missing integer models no source had
---@field read boolean a source was read (the cache should be written again)

---Sets mins / maxs on the props: from the cache, else from the sources (makeSources is called only
---when the cache doesn't have every model, it's the slow part). The cache table gets what was found
---@param props MapProp[]
---@param cache table<string, { mins: number[], maxs: number[] }|false> filled in
---@param makeSources fun(): PropSource[], fun()? sources and a close for them
---@return PropResolveResult
function Props.resolve(props, cache, makeSources)
    local needed = {}
    for _, prop in ipairs(props) do
        if prop.solid and cache[prop.model] == nil then needed[prop.model] = true end
    end
    local result = { found = 0, missing = 0, read = false }
    if next(needed) then
        local sources, close = makeSources()
        for model in pairs(needed) do
            local mins, maxs
            for _, source in ipairs(sources) do
                local header = source(model, HEADER_SIZE)
                if header then mins, maxs = Props.boundsFromHeader(header) end
                if mins then break end
            end
            cache[model] = mins and { mins = mins, maxs = maxs } or false
        end
        if close then close() end
        result.read = true
    end
    local counted = {}
    for _, prop in ipairs(props) do
        local b = cache[prop.model]
        if b then prop.mins, prop.maxs = b.mins, b.maxs end
        if prop.solid and not counted[prop.model] then
            counted[prop.model] = true
            if b then result.found = result.found + 1 else result.missing = result.missing + 1 end
        end
    end
    return result
end

---Whether a prop is left out for its model (Props.SKIP)
---@param model string
---@return boolean
function Props.skipped(model)
    for _, word in ipairs(Props.SKIP) do
        if model:find(word, 1, true) then return true end
    end
    return false
end

---A prop's box: the model's bounds, scaled, turned by the prop's angles (Source: yaw around z, then
---pitch around y, then roll around x: R = Rz(yaw) Ry(pitch) Rx(roll)), at its origin
---@param prop MapProp with mins / maxs
---@return MapBox
function Props.box(prop)
    local Mat3 = MGE.Mat3
    local a = prop.angles
    local turn = Mat3.mul(Mat3.rotZ(math.rad(a[2])), Mat3.mul(Mat3.rotY(math.rad(a[1])), Mat3.rotX(math.rad(a[3]))))
    local s = prop.scale or 1
    local mid, sides = {}, {}
    for k = 1, 3 do
        mid[k] = (prop.mins[k] + prop.maxs[k]) / 2 * s
        sides[k] = (prop.maxs[k] - prop.mins[k]) * s
    end
    local center = MapConv.Vec.add(prop.origin, Mat3.apply(turn, mid))
    local box = { center = center, frame = turn, sides = sides, kind = "box", fitError = 0 }
    MapConv.BoxFit.canonicalize(box)
    return box
end

return Props
