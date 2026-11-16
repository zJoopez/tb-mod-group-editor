



MGE.MapConv = MGE.MapConv or {}
local MapConv = MGE.MapConv

local BoxFit = {}
MapConv.BoxFit = BoxFit

local Vec = MapConv.Vec
local sub, scale, dot, cross = Vec.sub, Vec.scale, Vec.dot, Vec.cross










local function frameFromAxes(a, b)
    local c = cross(a, b)
    return { { a[1], b[1], c[1] }, { a[2], b[2], c[2] }, { a[3], b[3], c[3] } }
end


local function column(m, k) return { m[1][k], m[2][k], m[3][k] } end





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
    box.frame = frameFromAxes(x, cross(z, x))
    box.sides = { box.sides[first], box.sides[second], box.sides[up] }
end





local function boxInFrame(verts, frame)
    local min, max = { math.huge, math.huge, math.huge }, { -math.huge, -math.huge, -math.huge }


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



local function perpendicularTo(a)
    local ref = math.abs(a[3]) < 0.9 and { 0, 0, 1 } or { 1, 0, 0 }
    return Vec.normalize(sub(ref, scale(a, dot(ref, a))))
end




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







local function slab(geometry, face, thickness)
    local n = face.n
    local verts = {}
    for i, idx in ipairs(face.verts) do verts[i] = geometry.verts[idx] end
    local best
    for i = 1, #verts do
        local u = Vec.normalize(sub(verts[i % #verts + 1], verts[i]))
        if u then
            local box = boxInFrame(verts, frameFromAxes(u, cross(n, u)))
            if not best or box.sides[1] * box.sides[2] < best.sides[1] * best.sides[2] then best = box end
        end
    end
    local depth = 0
    for _, v in ipairs(geometry.verts) do depth = math.max(depth, dot(n, sub(verts[1], v))) end
    thickness = math.min(thickness, depth)
    best.sides[3] = thickness
    best.center = sub(best.center, scale(n, thickness / 2))
    best.kind = "slab"
    return best
end






local SLOPE_MIN_Z, SLOPE_MAX_Z = 0.2, 0.98




function BoxFit.fit(geometry, options)
    local frames = { frameFromAxes({ 1, 0, 0 }, { 0, 1, 0 }) }


    local aligned = true
    for _, face in ipairs(geometry.faces) do
        local n = face.n
        local x, y, z = math.abs(n[1]), math.abs(n[2]), math.abs(n[3])
        if not ((x == 1 and y == 0 and z == 0) or (x == 0 and y == 1 and z == 0) or (x == 0 and y == 0 and z == 1)) then
            aligned = false
            break
        end
    end
    local axes = aligned and {} or distinctAxes(geometry.faces)
    for i, a in ipairs(axes) do
        local p = perpendicularTo(a)
        if p then frames[#frames + 1] = frameFromAxes(a, p) end
        for j = i + 1, #axes do
            if math.abs(dot(a, axes[j])) < 1e-3 then frames[#frames + 1] = frameFromAxes(a, axes[j]) end
        end
    end
    local best, bestVolume
    local tried = {}



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
            best.fitError = fitError
        end
    end
    canonicalize(best)
    return best
end








BoxFit.terrainFill = 0.65











function BoxFit.terrain(terrain, options)
    local size, points = terrain.size, terrain.points
    local function at(i, j) return points[i * size + j + 1] end
    local slabs = {}


    local cellArea = {}
    for i = 0, size - 2 do
        for j = 0, size - 2 do
            local p00, p01, p10, p11 = at(i, j), at(i, j + 1), at(i + 1, j), at(i + 1, j + 1)
            local ax, ay, az = p11[1] - p00[1], p11[2] - p00[2], p11[3] - p00[3]
            local bx, by, bz = p01[1] - p10[1], p01[2] - p10[2], p01[3] - p10[3]
            local cx, cy, cz = ay * bz - az * by, az * bx - ax * bz, ax * by - ay * bx
            cellArea[i * size + j + 1] = math.sqrt(cx * cx + cy * cy + cz * cz) / 2
        end
    end
    local function patch(i0, i1, j0, j1)
        local n = Vec.normalize(cross(sub(at(i1, j1), at(i0, j0)), sub(at(i0, j1), at(i1, j0))))
        if not n then return end
        if dot(n, terrain.n) < 0 then n = scale(n, -1) end
        local low, high = math.huge, -math.huge
        local list = {}
        local n1, n2, n3 = n[1], n[2], n[3]
        for i = i0, i1 do
            local row = i * size + 1
            for j = j0, j1 do
                local p = points[row + j]
                list[#list + 1] = p
                local h = n1 * p[1] + n2 * p[2] + n3 * p[3]
                if h < low then low = h end
                if h > high then high = h end
            end
        end
        local function split()
            local im, jm = (i0 + i1) / 2, (j0 + j1) / 2
            patch(i0, im, j0, jm)
            patch(i0, im, jm, j1)
            patch(im, i1, j0, jm)
            patch(im, i1, jm, j1)
        end
        if high - low > options.terrainTolerance and i1 - i0 >= 2 then return split() end



        local box, boxArea
        local tried = {}
        local function try(u)
            if not u then return end
            for _, t in ipairs(tried) do
                local d = math.abs(dot(u, t))
                if d > 1 - 1e-12 or d < 1e-12 then return end
            end
            tried[#tried + 1] = u
            local b = boxInFrame(list, frameFromAxes(u, cross(n, u)))
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
            local covered = 0
            for i = i0, i1 - 1 do
                local row = i * size + 1
                for j = j0, j1 - 1 do covered = covered + cellArea[row + j] end
            end
            if covered < BoxFit.terrainFill * boxArea then return split() end
        end
        local thickness = math.max(options.slabThickness, high - low)

        box.center = Vec.add(box.center, scale(n, (high - thickness / 2) - (low + high) / 2))
        box.sides[3] = thickness
        box.kind, box.fitError = "slab", 0
        canonicalize(box)
        slabs[#slabs + 1] = box
    end
    patch(0, size - 1, 0, size - 1)
    return slabs
end

BoxFit.canonicalize = canonicalize

return BoxFit
