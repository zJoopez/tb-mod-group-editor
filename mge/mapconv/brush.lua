-- Map converter: brush geometry. A brush is the convex space inside all of its planes; this finds its
-- corners, face polygons and volume. Units are the map's own (Source: inches)
MGE.MapConv = MGE.MapConv or {}
local MapConv = MGE.MapConv

local Brush = {}
MapConv.Brush = Brush

-- small vector helpers, shared with boxfit.lua and convert.lua
local Vec = {}
MapConv.Vec = Vec

function Vec.add(a, b) return { a[1] + b[1], a[2] + b[2], a[3] + b[3] } end
function Vec.sub(a, b) return { a[1] - b[1], a[2] - b[2], a[3] - b[3] } end
function Vec.scale(a, s) return { a[1] * s, a[2] * s, a[3] * s } end
function Vec.dot(a, b) return a[1] * b[1] + a[2] * b[2] + a[3] * b[3] end
function Vec.cross(a, b)
    return { a[2] * b[3] - a[3] * b[2], a[3] * b[1] - a[1] * b[3], a[1] * b[2] - a[2] * b[1] }
end
function Vec.length(a) return math.sqrt(Vec.dot(a, a)) end
---@return number[]? nil for a zero vector
function Vec.normalize(a)
    local l = Vec.length(a)
    if l < 1e-12 then return nil end
    return { a[1] / l, a[2] / l, a[3] / l }
end

local add, sub, scale, dot, cross = Vec.add, Vec.sub, Vec.scale, Vec.dot, Vec.cross
local atan2 = math.atan2 or math.atan -- newer Lua takes two arguments in atan

local INSIDE_EPS = 0.02 -- how far outside a plane a corner may be and still count (map units)
local SAME_EPS = 0.05 -- corners closer than this are the same corner

---@class MapPlane
---@field n number[] unit normal, pointing out of the brush
---@field d number n . p = d on the plane, smaller inside
---@field material string

---Plane through three points the way Hammer writes them, clockwise seen from outside: then
---(p3 - p1) x (p2 - p1) points out. Brush.build tries a brush flipped when it comes out empty, so a
---file with the other winding still works
---@param points number[][]
---@return MapPlane? nil when the points are on one line
function Brush.planeFromPoints(points)
    local p1, p2, p3 = points[1], points[2], points[3]
    local n = Vec.normalize(cross(sub(p3, p1), sub(p2, p1)))
    if not n then return nil end
    return { n = n, d = dot(n, p1) }
end

---Point on all three planes, nil when two of them are parallel
local function intersect3(a, b, c)
    local bc = cross(b.n, c.n)
    local det = dot(a.n, bc)
    if math.abs(det) < 1e-9 then return nil end
    local ca, ab = cross(c.n, a.n), cross(a.n, b.n)
    return {
        (a.d * bc[1] + b.d * ca[1] + c.d * ab[1]) / det,
        (a.d * bc[2] + b.d * ca[2] + c.d * ab[2]) / det,
        (a.d * bc[3] + b.d * ca[3] + c.d * ab[3]) / det,
    }
end

---@param planes MapPlane[]
---@return number[][] corners
local function corners(planes)
    local verts = {}
    local count = #planes
    for i = 1, count - 2 do
        for j = i + 1, count - 1 do
            for k = j + 1, count do
                local p = intersect3(planes[i], planes[j], planes[k])
                if p then
                    local keep = true
                    for _, plane in ipairs(planes) do
                        if dot(plane.n, p) > plane.d + INSIDE_EPS then keep = false break end
                    end
                    if keep then
                        for _, v in ipairs(verts) do
                            if math.abs(v[1] - p[1]) < SAME_EPS and math.abs(v[2] - p[2]) < SAME_EPS
                                and math.abs(v[3] - p[3]) < SAME_EPS then
                                keep = false
                                break
                            end
                        end
                    end
                    if keep then verts[#verts + 1] = p end
                end
            end
        end
    end
    return verts
end

---@class MapFace
---@field verts integer[] corner indexes, counterclockwise seen from outside
---@field n number[] outward unit normal
---@field material string
---@field area number

---@class MapGeometry
---@field verts number[][]
---@field faces MapFace[]
---@field volume number
---@field min number[] bounding box
---@field max number[]

---Area of a face polygon
local function polygonArea(verts, idx)
    local total = { 0, 0, 0 }
    local v0 = verts[idx[1]]
    for i = 2, #idx - 1 do
        total = add(total, cross(sub(verts[idx[i]], v0), sub(verts[idx[i + 1]], v0)))
    end
    return Vec.length(total) / 2
end

---Faces from the corners on each plane, sorted around their middle. Planes with fewer than 3 corners
---don't touch the brush (redundant sides) and are left out
---@param planes MapPlane[]
---@param verts number[][]
---@return MapFace[]
local function buildFaces(planes, verts)
    local faces = {}
    for _, plane in ipairs(planes) do
        local idx = {}
        for i, v in ipairs(verts) do
            if math.abs(dot(plane.n, v) - plane.d) < SAME_EPS then idx[#idx + 1] = i end
        end
        if #idx >= 3 then
            local c = { 0, 0, 0 }
            for _, i in ipairs(idx) do c = add(c, verts[i]) end
            c = scale(c, 1 / #idx)
            local u = Vec.normalize(sub(verts[idx[1]], c)) or { 1, 0, 0 }
            local w = cross(plane.n, u) -- u to w turns counterclockwise seen from outside
            local angles = {}
            for _, i in ipairs(idx) do
                local r = sub(verts[i], c)
                angles[i] = atan2(dot(r, w), dot(r, u))
            end
            table.sort(idx, function(a, b) return angles[a] < angles[b] end)
            faces[#faces + 1] = { verts = idx, n = plane.n, material = plane.material, area = polygonArea(verts, idx) }
        end
    end
    return faces
end

---@param verts number[][]
---@param faces MapFace[]
---@return number
local function volumeOf(verts, faces)
    local c = { 0, 0, 0 }
    for _, v in ipairs(verts) do c = add(c, v) end
    c = scale(c, 1 / #verts)
    local total = 0
    for _, face in ipairs(faces) do
        local a = sub(verts[face.verts[1]], c)
        for i = 2, #face.verts - 1 do
            local b, d = sub(verts[face.verts[i]], c), sub(verts[face.verts[i + 1]], c)
            total = total + dot(a, cross(b, d)) / 6
        end
    end
    return math.abs(total)
end

---@param planes MapPlane[]
---@return MapPlane[]
local function flipped(planes)
    local out = {}
    for i, p in ipairs(planes) do
        out[i] = { n = scale(p.n, -1), d = -p.d, material = p.material }
    end
    return out
end

---Corners, faces and volume of a brush
---@param sides MapSide[]
---@return MapGeometry? geometry nil when the planes don't close a space
function Brush.build(sides)
    local planes = {}
    for _, side in ipairs(sides) do
        -- .vmf sides have three points, .bsp sides their plane already
        local plane = side.plane and { n = side.plane.n, d = side.plane.d } or Brush.planeFromPoints(side.points)
        if plane then
            plane.material = side.material
            planes[#planes + 1] = plane
        end
    end
    if #planes < 4 then return nil end
    local verts = corners(planes)
    if #verts < 4 then -- the other winding
        planes = flipped(planes)
        verts = corners(planes)
        if #verts < 4 then return nil end
    end
    local faces = buildFaces(planes, verts)
    if #faces < 4 then return nil end
    local min, max = { math.huge, math.huge, math.huge }, { -math.huge, -math.huge, -math.huge }
    for _, v in ipairs(verts) do
        for k = 1, 3 do
            if v[k] < min[k] then min[k] = v[k] end
            if v[k] > max[k] then max[k] = v[k] end
        end
    end
    return { verts = verts, faces = faces, volume = volumeOf(verts, faces), min = min, max = max }
end

return Brush
