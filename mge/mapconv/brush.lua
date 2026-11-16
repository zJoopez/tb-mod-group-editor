

MGE.MapConv = MGE.MapConv or {}
local MapConv = MGE.MapConv

local Brush = {}
MapConv.Brush = Brush


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

function Vec.normalize(a)
    local l = Vec.length(a)
    if l < 1e-12 then return nil end
    return { a[1] / l, a[2] / l, a[3] / l }
end

local sub, scale, dot, cross = Vec.sub, Vec.scale, Vec.dot, Vec.cross
local atan2 = math.atan2 or math.atan

local INSIDE_EPS = 0.02
local SAME_EPS = 0.05











function Brush.planeFromPoints(points)
    local p1, p2, p3 = points[1], points[2], points[3]
    local n = Vec.normalize(cross(sub(p3, p1), sub(p2, p1)))
    if not n then return nil end
    return { n = n, d = dot(n, p1) }
end






local function corners(planes)
    local verts = {}
    local count = #planes
    local abs = math.abs
    for i = 1, count - 2 do
        local a = planes[i]
        local a1, a2, a3, ad = a.n[1], a.n[2], a.n[3], a.d
        for j = i + 1, count - 1 do
            local b = planes[j]
            local b1, b2, b3, bd = b.n[1], b.n[2], b.n[3], b.d

            local ab1, ab2, ab3 = a2 * b3 - a3 * b2, a3 * b1 - a1 * b3, a1 * b2 - a2 * b1
            for k = j + 1, count do
                local c = planes[k]
                local c1, c2, c3, cd = c.n[1], c.n[2], c.n[3], c.d
                local bc1, bc2, bc3 = b2 * c3 - b3 * c2, b3 * c1 - b1 * c3, b1 * c2 - b2 * c1
                local det = a1 * bc1 + a2 * bc2 + a3 * bc3
                local p
                if abs(det) >= 1e-9 then
                    local ca1, ca2, ca3 = c2 * a3 - c3 * a2, c3 * a1 - c1 * a3, c1 * a2 - c2 * a1
                    p = {
                        (ad * bc1 + bd * ca1 + cd * ab1) / det,
                        (ad * bc2 + bd * ca2 + cd * ab2) / det,
                        (ad * bc3 + bd * ca3 + cd * ab3) / det,
                    }
                end
                if p then
                    local keep = true
                    local px, py, pz = p[1], p[2], p[3]
                    for q = 1, count do
                        local plane = planes[q]
                        local n = plane.n
                        if n[1] * px + n[2] * py + n[3] * pz > plane.d + INSIDE_EPS then keep = false break end
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



















local function polygonArea(verts, idx)
    local tx, ty, tz = 0, 0, 0
    local v0 = verts[idx[1]]
    local x0, y0, z0 = v0[1], v0[2], v0[3]
    for i = 2, #idx - 1 do
        local p, q = verts[idx[i]], verts[idx[i + 1]]
        local px, py, pz = p[1] - x0, p[2] - y0, p[3] - z0
        local qx, qy, qz = q[1] - x0, q[2] - y0, q[3] - z0
        tx = tx + (py * qz - pz * qy)
        ty = ty + (pz * qx - px * qz)
        tz = tz + (px * qy - py * qx)
    end
    return math.sqrt(tx * tx + ty * ty + tz * tz) / 2
end






local function buildFaces(planes, verts)
    local faces = {}
    local abs, sqrt = math.abs, math.sqrt
    local count = #verts
    local angles = {}
    local function byAngle(a, b) return angles[a] < angles[b] end
    for _, plane in ipairs(planes) do
        local n, d = plane.n, plane.d
        local n1, n2, n3 = n[1], n[2], n[3]
        local idx = {}
        for i = 1, count do
            local v = verts[i]
            if abs(n1 * v[1] + n2 * v[2] + n3 * v[3] - d) < SAME_EPS then idx[#idx + 1] = i end
        end
        if #idx >= 3 then
            local cx, cy, cz = 0, 0, 0
            for _, i in ipairs(idx) do
                local v = verts[i]
                cx, cy, cz = cx + v[1], cy + v[2], cz + v[3]
            end
            local s = 1 / #idx
            cx, cy, cz = cx * s, cy * s, cz * s
            local first = verts[idx[1]]
            local u1, u2, u3 = first[1] - cx, first[2] - cy, first[3] - cz
            local l = sqrt(u1 * u1 + u2 * u2 + u3 * u3)
            if l < 1e-12 then
                u1, u2, u3 = 1, 0, 0
            else
                u1, u2, u3 = u1 / l, u2 / l, u3 / l
            end

            local w1, w2, w3 = n2 * u3 - n3 * u2, n3 * u1 - n1 * u3, n1 * u2 - n2 * u1
            for _, i in ipairs(idx) do
                local v = verts[i]
                local r1, r2, r3 = v[1] - cx, v[2] - cy, v[3] - cz
                angles[i] = atan2(r1 * w1 + r2 * w2 + r3 * w3, r1 * u1 + r2 * u2 + r3 * u3)
            end
            table.sort(idx, byAngle)
            faces[#faces + 1] = { verts = idx, n = n, material = plane.material, area = polygonArea(verts, idx) }
        end
    end
    return faces
end




local function volumeOf(verts, faces)
    local cx, cy, cz = 0, 0, 0
    for _, v in ipairs(verts) do cx, cy, cz = cx + v[1], cy + v[2], cz + v[3] end
    local s = 1 / #verts
    cx, cy, cz = cx * s, cy * s, cz * s
    local total = 0
    for _, face in ipairs(faces) do
        local fv = face.verts
        local p = verts[fv[1]]
        local a1, a2, a3 = p[1] - cx, p[2] - cy, p[3] - cz
        for i = 2, #fv - 1 do
            local q, r = verts[fv[i]], verts[fv[i + 1]]
            local b1, b2, b3 = q[1] - cx, q[2] - cy, q[3] - cz
            local d1, d2, d3 = r[1] - cx, r[2] - cy, r[3] - cz
            total = total + (a1 * (b2 * d3 - b3 * d2) + a2 * (b3 * d1 - b1 * d3) + a3 * (b1 * d2 - b2 * d1)) / 6
        end
    end
    return math.abs(total)
end



local function flipped(planes)
    local out = {}
    for i, p in ipairs(planes) do
        out[i] = { n = scale(p.n, -1), d = -p.d, material = p.material }
    end
    return out
end




function Brush.build(sides)
    local planes = {}
    for _, side in ipairs(sides) do

        local plane = side.plane and { n = side.plane.n, d = side.plane.d } or Brush.planeFromPoints(side.points)
        if plane then
            plane.material = side.material
            planes[#planes + 1] = plane
        end
    end
    if #planes < 4 then return nil end
    local verts = corners(planes)
    if #verts < 4 then
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
