-- Map converter: joins boxes that make one bigger box, so a map's floors and walls take fewer of the
-- 256 objects. Two boxes join when they have the same axes and role, the same size and position on
-- two of their axes, and touch or overlap on the third (their union is then exactly a box). Floors laid
-- out as grids of brushes or terrain slabs (dust2) shrink a lot. Positions are compared to
-- options.step map units, so float noise from compiled maps doesn't keep neighbours apart
MGE.MapConv = MGE.MapConv or {}
local MapConv = MGE.MapConv

local Merge = {}
MapConv.Merge = Merge

---@param box MapBox
---@param k integer
---@return number[]
local function column(box, k) return { box.frame[1][k], box.frame[2][k], box.frame[3][k] } end

---@param box MapBox
---@return number[] center in the box's own axes
local function localCenter(box)
    local c = {}
    for k = 1, 3 do c[k] = MapConv.Vec.dot(column(box, k), box.center) end
    return c
end

---@param box MapBox
---@return string the axes, rounded
local function frameKey(box)
    local parts = {}
    for r = 1, 3 do
        for c = 1, 3 do parts[#parts + 1] = math.floor(box.frame[r][c] * 1000 + 0.5) end
    end
    return table.concat(parts, ",")
end

---One pass along axis k: neighbours in a row of equal boxes become one
---@param boxes MapConvBox[]
---@param k integer
---@param step number
---@return MapConvBox[] boxes
---@return integer joined boxes that went into another
local function mergeAlong(boxes, k, step)
    local a, b = k % 3 + 1, (k + 1) % 3 + 1
    local function round(v) return math.floor(v / step + 0.5) end
    local groups, order = {}, {}
    for _, box in ipairs(boxes) do
        local c = localCenter(box)
        local key = table.concat({ box.role, frameKey(box), round(c[a]), round(c[b]), round(box.sides[a]), round(box.sides[b]) }, "|")
        if not groups[key] then
            groups[key] = {}
            order[#order + 1] = key -- first seen order, the result doesn't depend on pairs()
        end
        table.insert(groups[key], { box = box, low = c[k] - box.sides[k] / 2, high = c[k] + box.sides[k] / 2, mid = c[k] })
    end
    local out, joined = {}, 0
    for _, key in ipairs(order) do
        local list = groups[key]
        table.sort(list, function(p, q) return p.low < q.low end)
        local current
        local function finish()
            if not current then return end
            local box = current.box
            if current.count > 1 then
                local copy = {}
                for field, value in pairs(box) do copy[field] = value end
                copy.sides = { box.sides[1], box.sides[2], box.sides[3] }
                copy.sides[k] = current.high - current.low
                copy.center = MapConv.Vec.add(box.center, MapConv.Vec.scale(column(box, k), (current.low + current.high) / 2 - current.mid))
                copy.merged = (box.merged or 1) + current.extra
                box = copy
            end
            out[#out + 1] = box
        end
        for _, item in ipairs(list) do
            if current and item.low <= current.high + step then
                current.high = math.max(current.high, item.high)
                current.count = current.count + 1
                current.extra = current.extra + (item.box.merged or 1)
                joined = joined + 1
            else
                finish()
                current = { box = item.box, low = item.low, high = item.high, mid = item.mid, count = 1, extra = 0 }
            end
        end
        finish()
    end
    return out, joined
end

---@class FlatMergeOptions
---@field tolerance number map units the joined box may be thicker than its thickest part (bumps, tilt)
---@field fill number share of the joined box its parts must cover, 0-1 (stops L shapes becoming rectangles)
---@field gap number map units parts may be apart and still join
---@field align number map units edges count as lined up within: what's left open is at most this deep (a
---notch, never a doorway: a lintel differs from the wall beside it by far more)
---@field maxThickness number map units: only slabs this thin or thinner join (floors, walls, terrain)
---@field shell number map units: beams spanning the same length side by side (a ledge's top, face and lip:
---its shell) join into one solid block when it's at most this big across

---A slab's own axes: thin axis (its normal, pointing up or else along the first non-zero world axis)
---and the two in its plane, as frame column indexes and vectors
---@param box MapBox
---@return integer thin, integer a, integer b column indexes
---@return number[] n
local function slabAxes(box)
    local thin = 1
    for k = 2, 3 do
        if box.sides[k] < box.sides[thin] then thin = k end
    end
    local n = column(box, thin)
    return thin, thin % 3 + 1, (thin + 1) % 3 + 1, n
end

---What a flat piece is, it can be both: a beam (rail, curb, trim: thin both ways, long one way) and / or a
---slab (floor, wall, terrain: thin one way, wide both others). Beams get their own rule: which of
---their two thin sides counts as "the" normal is arbitrary, a rail 8 x 16 next to one 16 x 8 would face
---different ways and never join as slabs. A long narrow terrain slab is both, and joins either way
---@param box MapBox
---@param options FlatMergeOptions
---@return table? piece nil when the box is neither (crates, wall blocks)
local function classify(box, options)
    local piece = { box = box }
    local order = { 1, 2, 3 }
    table.sort(order, function(p, q) return box.sides[p] < box.sides[q] end)
    local small, middle, long = order[1], order[2], order[3]
    if box.sides[middle] <= math.max(options.maxThickness, options.shell or 0) and box.sides[long] >= box.sides[middle] * 3 then
        piece.beam = { long = long, cross = { small, middle }, axis = column(box, long) }
        piece.length = box.sides[long]
    end
    local thin, a, b, n = slabAxes(box)
    local t = box.sides[thin]
    if t <= options.maxThickness and box.sides[a] >= t * 2 and box.sides[b] >= t * 2 then
        piece.slab = { thin = thin, a = a, b = b, n = n }
        piece.area = box.sides[a] * box.sides[b]
    end
    if not piece.beam and not piece.slab then return nil end
    piece.size = piece.area or piece.length -- the order slabs grow in: biggest first
    return piece
end

---Ranges of a box's 8 corners along three axes
---@param box MapBox
---@param axes number[][]
---@return number[] min, number[] max
local function ranges(box, axes)
    local min, max = { math.huge, math.huge, math.huge }, { -math.huge, -math.huge, -math.huge }
    local c = box.center
    for _, sa in ipairs({ -1, 1 }) do
        for _, sb in ipairs({ -1, 1 }) do
            for _, sc in ipairs({ -1, 1 }) do
                local p = {}
                for r = 1, 3 do
                    p[r] = c[r] + (box.frame[r][1] * sa * box.sides[1] + box.frame[r][2] * sb * box.sides[2]
                        + box.frame[r][3] * sc * box.sides[3]) / 2
                end
                for k = 1, 3 do
                    local v = MapConv.Vec.dot(axes[k], p)
                    if v < min[k] then min[k] = v end
                    if v > max[k] then max[k] = v end
                end
            end
        end
    end
    return min, max
end

---World xy bounds of a box, for the neighbour grid
local function xyBounds(box)
    local min, max = ranges(box, { { 1, 0, 0 }, { 0, 1, 0 }, { 0, 0, 1 } })
    return min, max
end

---Box from ranges along axes (axes[k] is the box's column columns[k]), the rest copied from like
local function boxFrom(like, axes, min, max, columns)
    local center = { 0, 0, 0 }
    for k = 1, 3 do
        local mid = (min[k] + max[k]) / 2
        for r = 1, 3 do center[r] = center[r] + axes[k][r] * mid end
    end
    local sides = {}
    for k = 1, 3 do sides[columns[k]] = max[k] - min[k] end
    local box = {}
    for field, value in pairs(like) do box[field] = value end
    box.center, box.sides = center, sides
    return box
end

---Two slabs: facing nearly the same way, touching or overlapping in their plane, lined up edge to edge
---(along one axis they reach as far as each other, or one lies within the other: a lintel over a
---doorway never reaches as far as the wall beside it, so the doorway stays open), at most
---options.tolerance thicker than the thickest, options.fill of the joined box covered
---@return MapBox? box, number? area covered
local function slabJoined(a, b, options)
    local s = a.slab
    if math.abs(MapConv.Vec.dot(s.n, b.slab.n)) < 0.95 then return nil end
    local axes = { column(a.box, s.a), column(a.box, s.b), s.n }
    local amin, amax = ranges(a.box, axes)
    local bmin, bmax = ranges(b.box, axes)
    for k = 1, 2 do
        if bmin[k] > amax[k] + options.gap or amin[k] > bmax[k] + options.gap then return nil end
    end
    local function same(k)
        return math.abs(amin[k] - bmin[k]) <= options.align and math.abs(amax[k] - bmax[k]) <= options.align
    end
    local function inside(innerMin, innerMax, outerMin, outerMax, k)
        return innerMin[k] >= outerMin[k] - options.align and innerMax[k] <= outerMax[k] + options.align
    end
    local bInA = inside(bmin, bmax, amin, amax, 1) and inside(bmin, bmax, amin, amax, 2)
    local aInB = inside(amin, amax, bmin, bmax, 1) and inside(amin, amax, bmin, bmax, 2)
    if not (same(1) or same(2) or bInA or aInB) then return nil end
    local min, max = {}, {}
    for k = 1, 3 do min[k], max[k] = math.min(amin[k], bmin[k]), math.max(amax[k], bmax[k]) end
    local thickest = math.max(a.box.sides[s.thin], b.box.sides[b.slab.thin])
    if max[3] - min[3] > thickest + options.tolerance then return nil end
    local area = (max[1] - min[1]) * (max[2] - min[2])
    local covered = a.area + b.area
    if covered < area * options.fill then return nil end
    return boxFrom(a.box, axes, min, max, { s.a, s.b, s.thin }), math.min(covered, area)
end

---Two beams (rails, curbs, trims, ledge strips) running the same way within ~14 degrees, touching or
---overlapping along their length, joined when either
---  end to end: the joined cross-section at most options.tolerance bigger than the thicker one's and
---  options.fill of its length covered (a rail in pieces, a kinked curb)
---  side by side: they span the same length (ends within options.align) and touch across, the joined
---  cross-section at most options.shell on each side (a ledge's top, face and lip are the shell of one
---  solid ledge: its inside can't be reached, filling it saves boxes)
---@return MapBox? box, number? length covered
local function beamJoined(a, b, options)
    local s = a.beam
    if math.abs(MapConv.Vec.dot(s.axis, b.beam.axis)) < 0.97 then return nil end
    local axes = { s.axis, column(a.box, s.cross[1]), column(a.box, s.cross[2]) }
    local amin, amax = ranges(a.box, axes)
    local bmin, bmax = ranges(b.box, axes)
    if bmin[1] > amax[1] + options.gap or amin[1] > bmax[1] + options.gap then return nil end
    local min, max = {}, {}
    for k = 1, 3 do min[k], max[k] = math.min(amin[k], bmin[k]), math.max(amax[k], bmax[k]) end
    local columns = { s.long, s.cross[1], s.cross[2] }
    local length = max[1] - min[1]

    local endToEnd = true
    for k = 2, 3 do
        if max[k] - min[k] > math.max(amax[k] - amin[k], bmax[k] - bmin[k]) + options.tolerance then endToEnd = false end
    end
    if endToEnd then
        local covered = a.length + b.length
        if covered >= length * options.fill then
            return boxFrom(a.box, axes, min, max, columns), math.min(covered, length)
        end
    end

    local shell = options.shell or 0
    if shell <= 0 then return nil end
    if math.abs(amin[1] - bmin[1]) > options.align or math.abs(amax[1] - bmax[1]) > options.align then return nil end
    for k = 2, 3 do
        if bmin[k] > amax[k] + options.gap or amin[k] > bmax[k] + options.gap then return nil end -- not touching
        if max[k] - min[k] > shell then return nil end
    end
    return boxFrom(a.box, axes, min, max, columns), length
end

---Joins nearly flat neighbouring pieces into bigger ones: a terrain floor's tiles (each tilted and
---lifted a little differently), a floor laid out of brushes with small steps (slabJoined), a rail or
---curb in pieces (beamJoined). Pieces of the same role join by whichever rule both fit; the joined box
---keeps the first one's axes, covers both, and is sorted out again (it can be a beam, a slab or both).
---Biggest pieces grow first, greedily, neighbours from a grid tried in a fixed order
---@param boxes MapConvBox[]
---@param options FlatMergeOptions
---@return MapConvBox[] boxes
---@return integer joined how many fewer there are
function Merge.flat(boxes, options)
    local CELL = 256 -- neighbour grid, map units
    -- missing options: the converter's defaults (MapConv.select passes them all)
    local given = options or {}
    options = { tolerance = 12, fill = 0.75, gap = 16, align = 32, maxThickness = 32, shell = 96 }
    for k, v in pairs(given) do options[k] = v end
    local pieces, out = {}, {}
    for _, box in ipairs(boxes) do
        local piece = classify(box, options)
        if piece then pieces[#pieces + 1] = piece else out[#out + 1] = box end
    end
    table.sort(pieces, function(p, q) return p.size > q.size end)
    for i, piece in ipairs(pieces) do piece.index = i end -- a fixed order: the same result on any Lua

    local cells = {}
    local function place(piece)
        local min, max = xyBounds(piece.box)
        piece.keys = {}
        for x = math.floor((min[1] - options.gap) / CELL), math.floor((max[1] + options.gap) / CELL) do
            for y = math.floor((min[2] - options.gap) / CELL), math.floor((max[2] + options.gap) / CELL) do
                local key = x .. "," .. y
                piece.keys[#piece.keys + 1] = key
                cells[key] = cells[key] or {}
                cells[key][piece] = true
            end
        end
    end
    local function unplace(piece)
        for _, key in ipairs(piece.keys or {}) do
            if cells[key] then cells[key][piece] = nil end
        end
    end
    for _, piece in ipairs(pieces) do place(piece) end

    ---a and b joined, or nil: as slabs, else as beams
    local function join(a, b)
        if a.box.role ~= b.box.role then return nil end
        if a.slab and b.slab then
            local box, area = slabJoined(a, b, options)
            if box then return box, "area", area end
        end
        if a.beam and b.beam then
            local box, length = beamJoined(a, b, options)
            if box then return box, "length", length end
        end
        return nil
    end

    local joinedCount = 0
    for _, piece in ipairs(pieces) do
        while not piece.dead do
            -- neighbours from the grid, biggest first (not pairs() order: the same on any Lua)
            local seen, candidates = {}, {}
            for _, key in ipairs(piece.keys) do
                for other in pairs(cells[key] or {}) do
                    if other ~= piece and not other.dead and not seen[other] then
                        seen[other] = true
                        candidates[#candidates + 1] = other
                    end
                end
            end
            table.sort(candidates, function(p, q) return p.index < q.index end)
            local grew = false
            for _, other in ipairs(candidates) do
                local box, measure, covered = join(piece, other)
                if box then
                    box.merged = (piece.box.merged or 1) + (other.box.merged or 1)
                    other.dead = true
                    unplace(other)
                    unplace(piece)
                    -- the joined box is sorted out again; what its parts cover carries over for the rule
                    -- that joined them, the other measure counts as full
                    local again = classify(box, options) or {}
                    piece.box, piece.beam, piece.slab = box, again.beam, again.slab
                    piece.area, piece.length = again.area, again.length
                    if measure == "area" and piece.slab then piece.area = covered end
                    if measure == "length" and piece.beam then piece.length = covered end
                    place(piece)
                    joinedCount = joinedCount + 1
                    grew = true
                    break
                end
            end
            if not grew or not (piece.beam or piece.slab) then break end
        end
    end
    for _, piece in ipairs(pieces) do
        if not piece.dead then out[#out + 1] = piece.box end
    end
    return out, joinedCount
end

---Joins boxes until nothing more joins
---@param boxes MapConvBox[]
---@param step number? map units positions and sizes are compared to, default 1
---@return MapConvBox[] boxes
---@return integer joined how many fewer there are
function Merge.boxes(boxes, step)
    step = step or 1
    local total = 0
    repeat
        local pass = 0
        for k = 1, 3 do
            local joined
            boxes, joined = mergeAlong(boxes, k, step)
            pass = pass + joined
        end
        total = total + pass
    until pass == 0
    return boxes, total
end

return Merge
