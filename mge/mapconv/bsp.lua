-- Map converter: reads compiled Source engine maps (.bsp, VBSP versions 19-21: CS:S, CS:GO, TF2, HL2,
-- Garry's Mod...) straight into the brushes and entities vmf.lua gives, no decompiler needed. A
-- compiled map keeps its brushes for collision: planes per side, and contents flags that say what is
-- solid for players (walls, floors, grates, glass) and what is a player clip. Which entity a brush
-- belongs to comes from the BSP tree of each brush model (*1, *2... in the entities' "model" key).
-- Terrain (displacements) has no brushes: its grids of points come as map.terrain, boxfit.lua turns
-- them into slabs. Only the lumps used are read (a map file is mostly packed textures: dust2 is 325 MB,
-- 9 MB of it is read). Reference: developer.valvesoftware.com/wiki/BSP_(Source)
MGE.MapConv = MGE.MapConv or {}
local MapConv = MGE.MapConv

local Bsp = {}
MapConv.Bsp = Bsp

local LUMP = {
    ENTITIES = 0, PLANES = 1, TEXDATA = 2, VERTEXES = 3, NODES = 5, TEXINFO = 6, FACES = 7, LEAFS = 10,
    EDGES = 12, SURFEDGES = 13, MODELS = 14, LEAFBRUSHES = 17, BRUSHES = 18, BRUSHSIDES = 19,
    DISPINFO = 26, DISP_VERTS = 33, TEXDATA_STRING_DATA = 43, TEXDATA_STRING_TABLE = 44,
    GAME_LUMP = 35, PAKFILE = 40,
}
local HEADER_LUMPS = 64
local HEADER_SIZE = 8 + HEADER_LUMPS * 16 + 4

-- contents flags (bspflags.h)
local CONTENTS = {
    SOLID = 0x1, WINDOW = 0x2, GRATE = 0x8, MOVEABLE = 0x4000, PLAYERCLIP = 0x10000,
}
-- surface flags of a side's texinfo
local SURF_SKY2D, SURF_SKY = 0x2, 0x4

---@param flags integer
---@param bits integer
---@return boolean
local function has(flags, bits)
    return flags % (bits * 2) >= bits -- plain math: the command line tool runs without the bit library
end

-- little endian readers on a lump's bytes, pos counts from 1 like string.byte
local function u16(s, pos)
    local a, b = s:byte(pos, pos + 1)
    return a + b * 256
end
local function i16(s, pos)
    local v = u16(s, pos)
    return v >= 32768 and v - 65536 or v
end
local function i32(s, pos)
    local a, b, c, d = s:byte(pos, pos + 3)
    local v = a + b * 256 + c * 65536 + d * 16777216
    return v >= 2147483648 and v - 4294967296 or v
end
---IEEE 754 single precision
local function f32(s, pos)
    local a, b, c, d = s:byte(pos, pos + 3)
    local sign = d >= 128 and -1 or 1
    local exponent = (d % 128) * 2 + math.floor(c / 128)
    local mantissa = (c % 128) * 65536 + b * 256 + a
    if exponent == 0 then return sign * mantissa * 2 ^ -149 end -- zero and denormals
    if exponent == 255 then return mantissa == 0 and sign * math.huge or 0 / 0 end
    return sign * (1 + mantissa / 8388608) * 2 ^ (exponent - 127)
end
Bsp.f32 = f32 -- also props.lua, the offline tests
Bsp.u16, Bsp.i16, Bsp.i32 = u16, i16, i32
local function vec3(s, pos) return { f32(s, pos), f32(s, pos + 4), f32(s, pos + 8) } end

---@alias BspReader fun(offset: integer, length: integer): string bytes from offset (0-based) on

---Reader over a whole file in a string
---@param data string
---@return BspReader, integer size
function Bsp.stringReader(data)
    return function(offset, length) return data:sub(offset + 1, offset + length) end, #data
end

---Reader over an open file (io.open, binary mode), reads only what's asked for
---@param file any an io.open file
---@return BspReader, integer size
function Bsp.fileReader(file)
    local size = file:seek("end")
    return function(offset, length)
        file:seek("set", offset)
        return file:read(length) or ""
    end, size
end

---@class BspLumps
---@field version fun(index: integer): integer
---@field offset fun(index: integer): integer from the file's start
---@field length fun(index: integer): integer
---@field get fun(index: integer, size: integer): string, integer bytes, record count

---Lump directory, lumps are read when first asked for
---@param read BspReader
---@param fileSize integer
---@return BspLumps
local function openLumps(read, fileSize)
    local header = read(0, HEADER_SIZE)
    if #header < HEADER_SIZE then error("too short for a map file") end
    if header:sub(1, 4) ~= "VBSP" then
        local magic = header:sub(1, 4)
        if magic == "\30\0\0\0" or magic == "\29\0\0\0" then
            error("GoldSrc map (Half-Life, CS 1.6): no brushes in these, only .vmf / Source .bsp work")
        end
        error("not a Source map (no VBSP header)")
    end
    local version = i32(header, 5)
    if version < 19 or version > 21 then error("BSP version " .. version .. ", only 19-21 (Source 1) work") end
    -- offset, length, version per lump. Left 4 Dead 2 and some others write version, offset, length:
    -- the order that fits the file is used
    local function readDirectory(o, l, v)
        local dir = {}
        for i = 0, HEADER_LUMPS - 1 do
            local pos = 9 + i * 16
            local lump = { offset = i32(header, pos + o), length = i32(header, pos + l), version = i32(header, pos + v) }
            if lump.length < 0 or (lump.length > 0 and (lump.offset < HEADER_SIZE or lump.offset + lump.length > fileSize)) then
                return nil
            end
            dir[i] = lump
        end
        return dir
    end
    local dir = readDirectory(0, 4, 8) or readDirectory(4, 8, 0)
    if not dir then error("lump directory doesn't fit the file (damaged or unknown BSP variant)") end

    local cache = {}
    return {
        version = function(index) return dir[index].version end,
        offset = function(index) return dir[index].offset end,
        length = function(index) return dir[index].length end,
        get = function(index, size)
            local bytes = cache[index]
            if not bytes then
                bytes = read(dir[index].offset, dir[index].length)
                if #bytes > 0 and bytes:sub(1, 4) == "LZMA" then
                    error("compressed lump " .. index .. ", decompress the map first (e.g. bspzip -repack)")
                end
                cache[index] = bytes
            end
            return bytes, math.floor(#bytes / size)
        end,
    }
end

---Material name and surface flags by texinfo index
local function readTexinfo(lumps)
    local tableBytes, tableCount = lumps.get(LUMP.TEXDATA_STRING_TABLE, 4)
    local strings = lumps.get(LUMP.TEXDATA_STRING_DATA, 1)
    local names = {}
    for i = 0, tableCount - 1 do
        local start = i32(tableBytes, 1 + i * 4) + 1
        local stop = strings:find("\0", start, true) or #strings + 1
        names[i] = strings:sub(start, stop - 1)
    end
    local texdata, texdataCount = lumps.get(LUMP.TEXDATA, 32)
    local texdataNames = {}
    for i = 0, texdataCount - 1 do texdataNames[i] = names[i32(texdata, 1 + i * 32 + 12)] or "" end
    local bytes, count = lumps.get(LUMP.TEXINFO, 72)
    local texinfo = {}
    for i = 0, count - 1 do
        local pos = 1 + i * 72
        texinfo[i] = { flags = i32(bytes, pos + 64), material = texdataNames[i32(bytes, pos + 68)] or "" }
    end
    return texinfo
end

---Brush model index (0 world, 1 = "*1"...) of every brush reachable from its tree
---@return table<integer, integer> brush index (from 0) -> model index
local function brushModels(lumps)
    local models, modelCount = lumps.get(LUMP.MODELS, 48)
    local nodes, nodeCount = lumps.get(LUMP.NODES, 32)
    -- leaf records: 56 bytes in lump version 0 (with ambient lighting), 32 after
    local leafSize = lumps.version(LUMP.LEAFS) == 0 and 56 or 32
    local leafs, leafCount = lumps.get(LUMP.LEAFS, leafSize)
    local leafBrushes = lumps.get(LUMP.LEAFBRUSHES, 2)

    local owner = {}
    -- entity models first, the world last: a brush in both trees counts for its entity
    for model = modelCount - 1, 0, -1 do
        local stack = { i32(models, 1 + model * 48 + 36) } -- headnode
        local seen = 0
        while #stack > 0 do
            local node = table.remove(stack)
            seen = seen + 1
            if seen > nodeCount + leafCount + 1 then error("BSP tree loops") end
            if node >= 0 then
                if node >= nodeCount then error("bad node " .. node) end
                local pos = 1 + node * 32
                stack[#stack + 1] = i32(nodes, pos + 4)
                stack[#stack + 1] = i32(nodes, pos + 8)
            else
                local leaf = -1 - node
                if leaf < leafCount then
                    local pos = 1 + leaf * leafSize
                    local first, count = u16(leafs, pos + 24), u16(leafs, pos + 26)
                    for k = first, first + count - 1 do
                        local brush = u16(leafBrushes, 1 + k * 2)
                        if owner[brush] == nil then owner[brush] = model end
                    end
                end
            end
        end
    end
    return owner
end

---@class MapTerrain a displacement: a grid of points over a 4 sided face
---@field id string
---@field size integer points per row (2^power + 1)
---@field points number[][] size * size, row by row
---@field n number[] the face's outward normal, the solid side is behind it
---@field material string

---Terrain grids, built like the compiler does (CCoreDispInfo::GenerateDispSurf): the face's corners
---start at the one nearest the displacement's start position, row i runs from corner 1 to 2 (between
---the 1-2 and 4-3 edges), point j along the row, then each point moves by its offset vector * distance
---@return MapTerrain[]
local function readTerrain(lumps, planes, texinfo)
    local infos, infoCount = lumps.get(LUMP.DISPINFO, 176)
    if infoCount == 0 then return {} end
    local faces = lumps.get(LUMP.FACES, 56)
    local vertexes = lumps.get(LUMP.VERTEXES, 12)
    local edges = lumps.get(LUMP.EDGES, 4)
    local surfedges = lumps.get(LUMP.SURFEDGES, 4)
    local dispVerts = lumps.get(LUMP.DISP_VERTS, 20)
    local terrain = {}
    for d = 0, infoCount - 1 do
        local info = 1 + d * 176
        local start = vec3(infos, info)
        local firstVert, power, contents, faceIndex = i32(infos, info + 12), i32(infos, info + 20), i32(infos, info + 32), u16(infos, info + 36)
        local face = 1 + faceIndex * 56
        local firstEdge, edgeCount = i32(faces, face + 4), i16(faces, face + 8)
        if edgeCount == 4 and has(contents, CONTENTS.SOLID) and power >= 1 and power <= 4 then
            local corners = {}
            for k = 0, 3 do
                local se = i32(surfedges, 1 + (firstEdge + k) * 4)
                local e = 1 + math.abs(se) * 4
                corners[k + 1] = vec3(vertexes, 1 + (se >= 0 and u16(edges, e) or u16(edges, e + 2)) * 12)
            end
            local first, best = 1, math.huge
            for k = 1, 4 do
                local dx, dy, dz = corners[k][1] - start[1], corners[k][2] - start[2], corners[k][3] - start[3]
                local dist = dx * dx + dy * dy + dz * dz
                if dist < best then first, best = k, dist end
            end
            local p = {}
            for k = 0, 3 do p[k] = corners[(first - 1 + k) % 4 + 1] end
            local size = 2 ^ power + 1
            local points = {}
            for i = 0, size - 1 do
                local t = i / (size - 1)
                local a, b = {}, {}
                for k = 1, 3 do
                    a[k] = p[0][k] + (p[1][k] - p[0][k]) * t
                    b[k] = p[3][k] + (p[2][k] - p[3][k]) * t
                end
                for j = 0, size - 1 do
                    local s = j / (size - 1)
                    local v = 1 + (firstVert + i * size + j) * 20
                    local offset, dist = vec3(dispVerts, v), f32(dispVerts, v + 12)
                    local q = {}
                    for k = 1, 3 do q[k] = a[k] + (b[k] - a[k]) * s + offset[k] * dist end
                    points[#points + 1] = q
                end
            end
            local plane = planes[u16(faces, face)]
            local n = plane and plane.n or { 0, 0, 1 }
            if faces:byte(face + 2) ~= 0 then n = { -n[1], -n[2], -n[3] } end -- face on the plane's back side
            local info2 = texinfo[i16(faces, face + 10)]
            terrain[#terrain + 1] = { id = "disp " .. d, size = size, points = points, n = n, material = info2 and info2.material or "" }
        end
    end
    return terrain
end

---@param read BspReader see Bsp.stringReader, Bsp.fileReader
---@param fileSize integer
---@return MapFile map brushes come with their role set (MapBrush.role, see MapConv.brushRole),
---terrain grids in map.terrain
function Bsp.parse(read, fileSize)
    local lumps = openLumps(read, fileSize)
    local map = { brushes = {}, entities = {} }

    -- entities: KeyValues blocks without names
    local text = lumps.get(LUMP.ENTITIES, 1):gsub("%z.*$", "")
    local modelClass = { [0] = "worldspawn" }
    for _, block in ipairs(MapConv.Vmf.parseTree(text).children) do
        local props = block.props
        local classname = props.classname or ""
        table.insert(map.entities, { classname = classname, origin = MapConv.Vmf.readVector(props.origin), props = props })
        local model = tonumber((props.model or ""):match("^%*(%d+)$"))
        if model then modelClass[model] = classname end
    end

    local planeBytes, planeCount = lumps.get(LUMP.PLANES, 20)
    local planes = {}
    for i = 0, planeCount - 1 do
        local pos = 1 + i * 20
        planes[i] = { n = vec3(planeBytes, pos), d = f32(planeBytes, pos + 12) }
    end
    local texinfo = readTexinfo(lumps)
    local owner = brushModels(lumps)

    local brushes, brushCount = lumps.get(LUMP.BRUSHES, 12)
    local sides, sideCount = lumps.get(LUMP.BRUSHSIDES, 8)
    for b = 0, brushCount - 1 do
        local pos = 1 + b * 12
        local firstSide, numSides, contents = i32(brushes, pos), i32(brushes, pos + 4), i32(brushes, pos + 8)
        local brush = { id = tostring(b), entity = modelClass[owner[b] or 0] or "worldspawn", sides = {} }
        local sky = false
        for s = firstSide, math.min(firstSide + numSides, sideCount) - 1 do
            local sp = 1 + s * 8
            local plane = planes[u16(sides, sp)]
            local info = texinfo[i16(sides, sp + 2)]
            local bevel = sides:byte(sp + 6) ~= 0 -- extra planes the compiler adds for collision, not faces
            if info and (has(info.flags, SURF_SKY) or has(info.flags, SURF_SKY2D)) then sky = true end
            if plane and not bevel then
                table.insert(brush.sides, { plane = plane, material = info and info.material or "", displacement = false })
            end
        end
        if sky then
            brush.role, brush.reason = "drop", "tool"
        elseif has(contents, CONTENTS.SOLID) or has(contents, CONTENTS.WINDOW) or has(contents, CONTENTS.GRATE)
            or has(contents, CONTENTS.MOVEABLE) then
            brush.role = "solid"
        elseif has(contents, CONTENTS.PLAYERCLIP) then
            brush.role = "clip"
        else
            brush.role, brush.reason = "drop", "tool" -- triggers, hints, water, npc clips...
        end
        map.brushes[#map.brushes + 1] = brush
    end

    map.terrain = readTerrain(lumps, planes, texinfo)
    -- models placed in the map (crates, doors, cars): their list, the sizes come from the model files
    -- (props.lua). The map's own packed files (a zip) may have custom models
    map.props = MapConv.Props.staticProps(read, lumps.get(LUMP.GAME_LUMP, 1))
    if lumps.length(LUMP.PAKFILE) > 0 then
        map.pakfile = { offset = lumps.offset(LUMP.PAKFILE), length = lumps.length(LUMP.PAKFILE) }
    end
    return map
end

return Bsp
