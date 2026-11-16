








local GizmoMath = {}
MGE.GizmoMath = GizmoMath

local function sub(a, b) return { a[1] - b[1], a[2] - b[2], a[3] - b[3] } end
local function add(a, b) return { a[1] + b[1], a[2] + b[2], a[3] + b[3] } end
local function scale(a, s) return { a[1] * s, a[2] * s, a[3] * s } end
local function dot(a, b) return a[1] * b[1] + a[2] * b[2] + a[3] * b[3] end
local function length(a) return math.sqrt(dot(a, a)) end
GizmoMath.sub, GizmoMath.add, GizmoMath.scale, GizmoMath.dot, GizmoMath.length = sub, add, scale, dot, length

GizmoMath.AXES = { { 1, 0, 0 }, { 0, 1, 0 }, { 0, 0, 1 } }



local EDGE_ON_AXIS = math.cos(math.rad(10))
local EDGE_ON_PLANE = math.sin(math.rad(10))




GizmoMath.SHAPE = {
    tipRadius = 0.072,
    pickRadius = 0.08,
    planeOffset = 0.3,
    planeHalf = 0.11,
    planeThick = 0.03,
    ringRadius = 0.85,
    uniformOffset = 0.45,
}

















function GizmoMath.moveHandles(center, size, viewDir)
    local S = GizmoMath.SHAPE
    local handles = {}
    for i, a in ipairs(GizmoMath.AXES) do
        table.insert(handles, { kind = "axis", index = i, dir = a, from = center, to = add(center, scale(a, size)),
            enabled = math.abs(dot(a, viewDir)) < EDGE_ON_AXIS })
    end
    for i, n in ipairs(GizmoMath.AXES) do
        local u, v = i % 3 + 1, (i + 1) % 3 + 1
        local c, half = { center[1], center[2], center[3] }, {}
        for _, k in ipairs({ u, v }) do c[k] = c[k] + S.planeOffset * size end
        for k = 1, 3 do half[k] = (k == i and S.planeThick or S.planeHalf) * size end
        table.insert(handles, { kind = "plane", index = i, normal = n, center = c, half = half,
            enabled = math.abs(dot(n, viewDir)) > EDGE_ON_PLANE })
    end
    return handles
end



function GizmoMath.closestOnLine(o, d, p, u)
    local w = sub(p, o)
    local b = dot(u, d)
    local denom = 1 - b * b
    if denom < 1e-9 then return nil end
    return (b * dot(d, w) - dot(u, w)) / denom
end



function GizmoMath.rayPlane(o, d, p, n)
    local dn = dot(d, n)
    if math.abs(dn) < 1e-9 then return nil end
    local t = dot(sub(p, o), n) / dn
    if t < 0 then return nil end
    return add(o, scale(d, t))
end




function GizmoMath.snap(value, step)
    return math.floor(value / step + 0.5) * step
end





function GizmoMath.dragStart(handle, center, o, d)
    if handle.kind == "axis" then return GizmoMath.closestOnLine(o, d, center, handle.dir) end
    return GizmoMath.rayPlane(o, d, center, handle.normal)
end







function GizmoMath.dragOffset(handle, center, grab, o, d, step)
    if handle.kind == "axis" then
        local s = GizmoMath.closestOnLine(o, d, center, handle.dir)
        if not s then return nil end
        local delta = s - grab
        if step then delta = GizmoMath.snap(delta, step) end
        return scale(handle.dir, delta)
    end
    local hit = GizmoMath.rayPlane(o, d, center, handle.normal)
    if not hit then return nil end
    local offset = sub(hit, grab)
    for k = 1, 3 do
        if k == handle.index then
            offset[k] = 0
        elseif step then
            offset[k] = GizmoMath.snap(offset[k], step)
        end
    end
    return offset
end








local function cross(a, b) return { a[2] * b[3] - a[3] * b[2], a[3] * b[1] - a[1] * b[3], a[1] * b[2] - a[2] * b[1] } end
local function normalize(a)
    local l = length(a)
    if l < 1e-12 then return nil end
    return scale(a, 1 / l)
end
GizmoMath.cross, GizmoMath.normalize = cross, normalize
local atan2 = math.atan2 or math.atan

GizmoMath.RING_SEGMENTS = 64

GizmoMath.RING_PLANE_LIMIT = 0.3





function GizmoMath.rotationAbout(u, t)
    local c, s = math.cos(t), math.sin(t)
    local k = 1 - c
    local x, y, z = u[1], u[2], u[3]
    return {
        { c + x * x * k, x * y * k - z * s, x * z * k + y * s },
        { y * x * k + z * s, c + y * y * k, y * z * k - x * s },
        { z * x * k - y * s, z * y * k + x * s, c + z * z * k },
    }
end












function GizmoMath.ringHandles(center, frame, radius)
    local cols = {
        { frame[1][1], frame[2][1], frame[3][1] },
        { frame[1][2], frame[2][2], frame[3][2] },
        { frame[1][3], frame[2][3], frame[3][3] },
    }
    local handles = {}
    for i = 1, 3 do
        local u, v = cols[i % 3 + 1], cols[(i + 1) % 3 + 1]
        local points = {}
        for k = 0, GizmoMath.RING_SEGMENTS do
            local a = 2 * math.pi * k / GizmoMath.RING_SEGMENTS
            points[k + 1] = add(center, add(scale(u, radius * math.cos(a)), scale(v, radius * math.sin(a))))
        end
        table.insert(handles, { kind = "ring", index = i, normal = cols[i], center = center, radius = radius,
            u = u, v = v, points = points, enabled = true })
    end
    return handles
end

















function GizmoMath.ringGrab(ring, o, d, t, viewDir)
    local n, c = ring.normal, ring.center
    local q = sub(add(o, scale(d, t)), c)
    q = sub(q, scale(n, dot(q, n)))
    local dirOut = normalize(q)
    if not dirOut then return nil end
    local point = add(c, scale(dirOut, ring.radius))
    if math.abs(dot(n, viewDir)) >= GizmoMath.RING_PLANE_LIMIT then
        local hit = GizmoMath.rayPlane(o, d, c, n)
        local from = hit and sub(hit, c)
        if from and length(from) > 1e-9 then
            return { method = "plane", point = point, from = from, raw = 0, angle = 0 }
        end
    end
    local tangent = cross(n, dirOut)
    local s0 = GizmoMath.closestOnLine(o, d, point, tangent)
    if not s0 then return nil end
    return { method = "tangent", point = point, tangent = tangent, s0 = s0, angle = 0 }
end






function GizmoMath.ringAngle(ring, grab, o, d, step)
    if grab.method == "plane" then
        local hit = GizmoMath.rayPlane(o, d, ring.center, ring.normal)
        local to = hit and sub(hit, ring.center)
        if not to or length(to) < 1e-9 then return nil end
        local raw = atan2(dot(ring.normal, cross(grab.from, to)), dot(grab.from, to))

        local delta = raw - grab.raw
        if delta > math.pi then delta = delta - 2 * math.pi elseif delta < -math.pi then delta = delta + 2 * math.pi end
        grab.raw, grab.angle = raw, grab.angle + delta
    else
        local s = GizmoMath.closestOnLine(o, d, grab.point, grab.tangent)
        if not s then return nil end
        grab.angle = (s - grab.s0) / ring.radius
    end
    if step then return GizmoMath.snap(grab.angle, step) end
    return grab.angle
end









GizmoMath.SCALE_PER_SIZE = 5
GizmoMath.MIN_FACTOR, GizmoMath.MAX_FACTOR = 1e-3, 1e4















function GizmoMath.scaleHandles(center, axes, tips, corner, viewDir)
    local handles = {}
    for i = 1, 3 do
        local a = axes[i]
        table.insert(handles, { kind = "scale", index = i, dir = a, from = center, to = add(center, scale(a, tips[i])),
            axes = axes, enabled = math.abs(dot(a, viewDir)) < EDGE_ON_AXIS })
    end
    local toCorner = { 0, 0, 0 }
    for i = 1, 3 do toCorner = add(toCorner, scale(axes[i], corner[i])) end
    local dir = normalize(toCorner) or axes[1]
    table.insert(handles, { kind = "uniform", index = 4, dir = dir, from = center, to = add(center, toCorner),
        axes = axes, enabled = math.abs(dot(dir, viewDir)) < EDGE_ON_AXIS })
    return handles
end




function GizmoMath.scaleStart(handle, o, d)
    return GizmoMath.closestOnLine(o, d, handle.from, handle.dir)
end






function GizmoMath.scaleFactor(travel, size, step)
    local f = GizmoMath.SCALE_PER_SIZE ^ (travel / size)
    if step then f = math.max(GizmoMath.snap(f, step), step) end
    return math.min(math.max(f, GizmoMath.MIN_FACTOR), GizmoMath.MAX_FACTOR)
end








function GizmoMath.scaleFactors(handle, s0, o, d, size, step)
    local s = GizmoMath.closestOnLine(o, d, handle.from, handle.dir)
    if not s then return nil end
    local f = GizmoMath.scaleFactor(s - s0, size, step)
    if handle.kind == "uniform" then return { f, f, f }, s - s0 end

    local factors = { 1, 1, 1 }
    factors[handle.index] = f
    return factors, s - s0
end

return GizmoMath
