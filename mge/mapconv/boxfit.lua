-- Map converter: one box per brush. Most map brushes are boxes (walls, floors, crates), those come out
-- exact. Other shapes get the smallest box around them, except ramps: a box around a wedge would be a
-- block in the way, so a brush with a walkable slope that fits badly becomes a thin slab under its
-- slope instead
MGE.MapConv = MGE.MapConv or {}
local MapConv = MGE.MapConv

local BoxFit = {}
MapConv.BoxFit = BoxFit

local Vec = MapConv.Vec
local sub, scale, dot, cross = Vec.sub, Vec.scale, Vec.dot, Vec.cross

---@class MapBox
---@field center number[] map units
---@field frame number[][] row-major rotation, its columns are the box's axes in world space
---@field sides number[] along the frame's columns
---@field fitError number 0 exact, otherwise 1 - brush volume / box volume
---@field kind "box"|"slab"

---Rotation matrix with columns a, b and a x b (a, b unit and perpendicular)
---@return number[][]
local function frameFromAxes(a, b)
    local c = cross(a, b)
    return { { a[1], b[1], c[1] }, { a[2], b[2], c[2] }, { a[3], b[3], c[3] } }
end

---@return number[] column k of m
local function column(m, k) return { m[1][k], m[2][k], m[3][k] } end

---Same box, axes reordered and turned so the one closest to world Z is the third (pointing up) and
---the one closest to world X the first: an axis aligned brush gets rot 0 0 0, a turned wall only a Z
---angle, which reads well in the editor's Rot row
---@param box MapBox
local function canonicalize(box)
    local cols = { column(box.frame, 1), column(box.frame, 2), column(box.frame, 3) }
    local up = 1
    for k = 2, 3 do
        if math.abs(cols[k][3]) > math.abs(cols[up][3]) then up = k end
    end
    local first
    for k = 1, 3 do
        if k ~= up and (not first or math.abs(cols[k][1]) > math.abs(cols[first][1]) + 1e-9) then first = k end
    end
    local second = 6 - up - first
    local z = cols[up][3] < 0 and scale(cols[up], -1) or cols[up]
    local x = cols[first]
    if x[1] < -1e-9 or (math.abs(x[1]) <= 1e-9 and x[2] < 0) then x = scale(x, -1) end
    box.frame = frameFromAxes(x, cross(z, x)) -- columns x, z x x, z: right-handed
    box.sides = { box.sides[first], box.sides[second], box.sides[up] }
end

---Smallest box with these axes around the corners
---@param verts number[][]
---@param frame number[][]
---@return MapBox
local function boxInFrame(verts, frame)
    local min, max = { math.huge, math.huge, math.huge }, { -math.huge, -math.huge, -math.huge }
    -- the frame's numbers in locals once (this runs for every vertex of every fit): same sums as
    -- frame[r][k] * v[r] added up in row order
    local r1, r2, r3 = frame[1], frame[2], frame[3]
    for k = 1, 3 do
        local a, b, c = r1[k], r2[k], r3[k]
        local lo, hi = math.huge, -math.huge
        for i = 1, #verts do
            local v = verts[i]
            local t = a * v[1] + b * v[2] + c * v[3]
            if t < lo then lo = t end
            if t > hi then hi = t end
        end
        min[k], max[k] = lo, hi
    end
    local center = { 0, 0, 0 }
    for k = 1, 3 do
        local mid = (min[k] + max[k]) / 2
        for r = 1, 3 do center[r] = center[r] + frame[r][k] * mid end
    end
    return { center = center, frame = frame, sides = { max[1] - min[1], max[2] - min[2], max[3] - min[3] }, kind = "box" }
end

---Unit vector perpendicular to a: world Z flattened onto a's plane (X for a near Z), keeps boxes
---around walls upright
local function perpendicularTo(a)
    local ref = math.abs(a[3]) < 0.9 and { 0, 0, 1 } or { 1, 0, 0 }
    return Vec.normalize(sub(ref, scale(a, dot(ref, a))))
end

---Face normals, one per direction (n and -n count once)
---@param faces MapFace[]
---@return number[][]
local function distinctAxes(faces)
    local axes = {}
    for _, face in ipairs(faces) do
        local known = false
        for _, a in ipairs(axes) do
            if math.abs(dot(a, face.n)) > 0.9999 then known = true break end
        end
        if not known then axes[#axes + 1] = face.n end
    end
    return axes
end

---Thin box under a face: the face's smallest rectangle (tried along each of its edges), thickness
---going into the brush
---@param geometry MapGeometry
---@param face MapFace
---@param thickness number map units, less when the brush is thinner
---@return MapBox
local function slab(geometry, face, thickness)
    local n = face.n
    local verts = {}
    for i, idx in ipairs(face.verts) do verts[i] = geometry.verts[idx] end
    local best
    for i = 1, #verts do
        local u = Vec.normalize(sub(verts[i % #verts + 1], verts[i]))
        if u then
            local box = boxInFrame(verts, frameFromAxes(u, cross(n, u))) -- columns u, n x u, n
            if not best or box.sides[1] * box.sides[2] < best.sides[1] * best.sides[2] then best = box end
        end
    end
    local depth = 0 -- how far the brush goes below the face
    for _, v in ipairs(geometry.verts) do depth = math.max(depth, dot(n, sub(verts[1], v))) end
    thickness = math.min(thickness, depth)
    best.sides[3] = thickness
    best.center = sub(best.center, scale(n, thickness / 2))
    best.kind = "slab"
    return best
end

---@class BoxFitOptions
---@field slabError number fit error above which a brush with a walkable slope becomes a slab
---@field slabThickness number map units

-- normal Z range of a walkable slope: steeper is a wall, flatter is a floor (boxes fit floors)
local SLOPE_MIN_Z, SLOPE_MAX_Z = 0.2, 0.98

---@param geometry MapGeometry
---@param options BoxFitOptions
---@return MapBox
function BoxFit.fit(geometry, options)
    local axes = distinctAxes(geometry.faces)
    local frames = { frameFromAxes({ 1, 0, 0 }, { 0, 1, 0 }) } -- first: equal volumes keep world axes
    for i, a in ipairs(axes) do
        local p = perpendicularTo(a)
        if p then frames[#frames + 1] = frameFromAxes(a, p) end
        for j = i + 1, #axes do
            if math.abs(dot(a, axes[j])) < 1e-3 then frames[#frames + 1] = frameFromAxes(a, axes[j]) end
        end
    end
    local best, bestVolume
    local tried = {}
    ---column k of frame is column j of t, either way round (to 1e-12 per number: compiled brushes'
    ---faces are often only nearly perpendicular, their frames aren't quite orthonormal, a dot product
    ---test called those the same)
    local abs = math.abs
    local function sameColumn(frame, k, t, j)
        local same, flipped = true, true
        for r = 1, 3 do
            local x, y = frame[r][k], t[r][j]
            if abs(x - y) > 1e-12 then same = false end
            if abs(x + y) > 1e-12 then flipped = false end
        end
        return same or flipped
    end
    for _, frame in ipairs(frames) do
        -- the same three axes as a frame tried already (in another order or direction: a box brush
        -- gives its axes in up to 7 frames) fit the same box, which never beats the first by 1e-6
        local repeated = false
        for _, t in ipairs(tried) do
            local all = true
            for k = 1, 3 do
                local found = false
                for j = 1, 3 do
                    if sameColumn(frame, k, t, j) then
                        found = true
                        break
                    end
                end
                if not found then all = false break end
            end
            if all then repeated = true break end
        end
        if not repeated then
            tried[#tried + 1] = frame
            local box = boxInFrame(geometry.verts, frame)
            local volume = box.sides[1] * box.sides[2] * box.sides[3]
            if not best or volume < bestVolume * (1 - 1e-6) then best, bestVolume = box, volume end
        end
    end
    best.fitError = bestVolume > 0 and math.max(0, 1 - geometry.volume / bestVolume) or 0

    if best.fitError > options.slabError then
        local slope
        for _, face in ipairs(geometry.faces) do
            if face.n[3] > SLOPE_MIN_Z and face.n[3] < SLOPE_MAX_Z and (not slope or face.area > slope.area) then
                slope = face
            end
        end
        if slope then
            local fitError = best.fitError
            best = slab(geometry, slope, options.slabThickness)
            best.fitError = fitError -- of the brush as a box, the reason it's a slab
        end
    end
    canonicalize(best)
    return best
end

---@class TerrainFitOptions
---@field slabThickness number map units
---@field terrainTolerance number map units a patch may be bumpy and still be one slab

-- a patch whose slab is filled less than this by the patch itself is split (down to single cells):
-- a displacement isn't always a rectangle, the wall under a staircase (dust2) is a trapezoid with a
-- slanted edge, one slab over it sticks out over the stairs
BoxFit.terrainFill = 0.65

---Slabs for a terrain grid (bsp.lua's MapTerrain). A patch flat within terrainTolerance becomes one
---slab: its top on the patch's highest point, slabThickness deep behind it (more when a single cell is
---bumpier). Bumpier patches are split in four, down to single cells, and so are patches their slab
---barely covers (BoxFit.terrainFill). A slab's sides follow the world (walls upright, floors along x
---and y) unless one of the patch's edges gives a smaller one (a turned grid): a slanted edge would
---turn it (dust2's stair walls came out as diamonds). Slabs of a flat floor all get the same thickness
---and height, so merge.lua can join neighbours
---@param terrain MapTerrain
---@param options TerrainFitOptions
---@return MapBox[]
function BoxFit.terrain(terrain, options)
    local size, points = terrain.size, terrain.points
    local function at(i, j) return points[i * size + j + 1] end
    local slabs = {}
    local function patch(i0, i1, j0, j1)
        local n = Vec.normalize(cross(sub(at(i1, j1), at(i0, j0)), sub(at(i0, j1), at(i1, j0))))
        if not n then return end -- collapsed patch, nothing to stand on
        if dot(n, terrain.n) < 0 then n = scale(n, -1) end
        local low, high = math.huge, -math.huge
        local list = {}
        for i = i0, i1 do
            for j = j0, j1 do
                local p = at(i, j)
                list[#list + 1] = p
                local h = dot(n, p)
                if h < low then low = h end
                if h > high then high = h end
            end
        end
        local function split()
            local im, jm = (i0 + i1) / 2, (j0 + j1) / 2 -- grids are 2^k + 1 points: halves stay whole
            patch(i0, im, j0, jm)
            patch(i0, im, jm, j1)
            patch(im, i1, j0, jm)
            patch(im, i1, jm, j1)
        end
        if high - low > options.terrainTolerance and i1 - i0 >= 2 then return split() end
        -- the slab's sides: the world's directions first, a patch edge only when its box is smaller.
        -- A direction along or across one already tried gives the same box (its sides swapped): not
        -- fitted again (on most grids the edges run along the world's axes)
        local box, boxArea
        local tried = {}
        local function try(u)
            if not u then return end -- a collapsed edge
            for _, t in ipairs(tried) do
                local d = math.abs(dot(u, t))
                if d > 1 - 1e-12 or d < 1e-12 then return end
            end
            tried[#tried + 1] = u
            local b = boxInFrame(list, frameFromAxes(u, cross(n, u))) -- columns u, n x u, n
            local area = b.sides[1] * b.sides[2]
            if not box or area < boxArea * 0.99 then box, boxArea = b, area end
        end
        local function edge(p, q)
            local e = sub(q, p)
            return Vec.normalize(sub(e, scale(n, dot(e, n))))
        end
        try(perpendicularTo(n))
        try(edge(at(i0, j0), at(i1, j0)))
        try(edge(at(i0, j0), at(i0, j1)))
        try(edge(at(i0, j1), at(i1, j1)))
        try(edge(at(i1, j0), at(i1, j1)))
        if not box then return end
        if i1 - i0 >= 2 and boxArea > 0 then
            local covered = 0 -- the patch's own area, cell by cell (each split along its diagonals)
            for i = i0, i1 - 1 do
                for j = j0, j1 - 1 do
                    local p00, p01, p10, p11 = at(i, j), at(i, j + 1), at(i + 1, j), at(i + 1, j + 1)
                    local ax, ay, az = p11[1] - p00[1], p11[2] - p00[2], p11[3] - p00[3]
                    local bx, by, bz = p01[1] - p10[1], p01[2] - p10[2], p01[3] - p10[3]
                    local cx, cy, cz = ay * bz - az * by, az * bx - ax * bz, ax * by - ay * bx
                    covered = covered + math.sqrt(cx * cx + cy * cy + cz * cz) / 2
                end
            end
            if covered < BoxFit.terrainFill * boxArea then return split() end
        end
        local thickness = math.max(options.slabThickness, high - low)
        -- top on the highest point: the center moves from the middle of the points along n
        box.center = Vec.add(box.center, scale(n, (high - thickness / 2) - (low + high) / 2))
        box.sides[3] = thickness
        box.kind, box.fitError = "slab", 0
        canonicalize(box)
        slabs[#slabs + 1] = box
    end
    patch(0, size - 1, 0, size - 1)
    return slabs
end

BoxFit.canonicalize = canonicalize -- for the offline tests

return BoxFit
