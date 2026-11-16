




MGE.MapConv = MGE.MapConv or {}
local MapConv = MGE.MapConv

local Merge = {}
MapConv.Merge = Merge




local function column(box, k) return { box.frame[1][k], box.frame[2][k], box.frame[3][k] } end






local function cellKey(x, y) return x * 2097152 + y end
Merge.cellKey = cellKey





local function mergeInfo(cache, box)
    local info = cache[box]
    if info then return info end
    local f, center = box.frame, box.center
    local c, parts = {}, {}
    for k = 1, 3 do c[k] = f[1][k] * center[1] + f[2][k] * center[2] + f[3][k] * center[3] end
    for r = 1, 3 do
        for col = 1, 3 do parts[#parts + 1] = math.floor(f[r][col] * 1000 + 0.5) end
    end
    info = { c = c, prefix = box.role .. "|" .. table.concat(parts, ","), keys = {} }
    cache[box] = info
    return info
end








local function mergeAlong(boxes, k, step, cache)
    local a, b = k % 3 + 1, (k + 1) % 3 + 1
    local function round(v) return math.floor(v / step + 0.5) end
    local groups, order = {}, {}
    for _, box in ipairs(boxes) do
        local info = mergeInfo(cache, box)
        local c = info.c
        local key = info.keys[k]
        if not key then
            key = info.prefix .. "|" .. round(c[a]) .. "|" .. round(c[b]) .. "|" .. round(box.sides[a]) .. "|" .. round(box.sides[b])
            info.keys[k] = key
        end

        local list = groups[key]
        if not list then
            groups[key] = { box }
            order[#order + 1] = key
        else
            list[#list + 1] = box
        end
    end
    local out, joined = {}, 0
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
    local function byLow(p, q) return p.low < q.low end
    for _, key in ipairs(order) do
        local members = groups[key]
        if #members == 1 then
            out[#out + 1] = members[1]
        else
            local list = {}
            for i, box in ipairs(members) do
                local mid = cache[box].c[k]
                list[i] = { box = box, low = mid - box.sides[k] / 2, high = mid + box.sides[k] / 2, mid = mid }
            end
            table.sort(list, byLow)
            current = nil
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
    end
    return out, joined
end














local function slabAxes(box)
    local thin = 1
    for k = 2, 3 do
        if box.sides[k] < box.sides[thin] then thin = k end
    end
    local n = column(box, thin)
    return thin, thin % 3 + 1, (thin + 1) % 3 + 1, n
end








local function classify(box, options)
    local piece = { box = box }
    local order = { 1, 2, 3 }
    table.sort(order, function(p, q) return box.sides[p] < box.sides[q] end)
    local small, middle, long = order[1], order[2], order[3]
    if box.sides[middle] <= options.maxThickness and box.sides[long] >= box.sides[middle] * 3 then
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
    piece.size = piece.area or piece.length
    return piece
end







local function ranges(box, axes)
    local min, max = {}, {}
    local c, f, s = box.center, box.frame, box.sides
    local h1, h2, h3 = s[1] / 2, s[2] / 2, s[3] / 2
    local abs = math.abs
    for k = 1, 3 do
        local ax = axes[k]
        local x, y, z = ax[1], ax[2], ax[3]
        local mid = x * c[1] + y * c[2] + z * c[3]
        local half = abs(x * f[1][1] + y * f[2][1] + z * f[3][1]) * h1
            + abs(x * f[1][2] + y * f[2][2] + z * f[3][2]) * h2
            + abs(x * f[1][3] + y * f[2][3] + z * f[3][3]) * h3
        min[k], max[k] = mid - half, mid + half
    end
    return min, max
end



local function xyBounds(box)
    local min, max = ranges(box, { { 1, 0, 0 }, { 0, 1, 0 }, { 0, 0, 1 } })
    return min, max
end


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






local function slabJoined(a, b, options)
    local s = a.slab
    if math.abs(MapConv.Vec.dot(s.n, b.slab.n)) < 0.95 then return nil end


    if not s.axes then
        s.axes = { column(a.box, s.a), column(a.box, s.b), s.n }
        s.min, s.max = ranges(a.box, s.axes)
    end
    local axes, amin, amax = s.axes, s.min, s.max
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





local function beamJoined(a, b, options)
    local s = a.beam
    if math.abs(MapConv.Vec.dot(s.axis, b.beam.axis)) < 0.97 then return nil end
    if not s.axes then
        s.axes = { s.axis, column(a.box, s.cross[1]), column(a.box, s.cross[2]) }
        s.min, s.max = ranges(a.box, s.axes)
    end
    local axes, amin, amax = s.axes, s.min, s.max
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
    if not endToEnd then return nil end
    local covered = a.length + b.length
    if covered < length * options.fill then return nil end
    return boxFrom(a.box, axes, min, max, columns), math.min(covered, length)
end










function Merge.flat(boxes, options)
    local CELL = 256

    local given = options or {}
    options = { tolerance = 12, fill = 0.75, gap = 16, align = 32, maxThickness = 32 }
    for k, v in pairs(given) do options[k] = v end
    local pieces, out = {}, {}
    for _, box in ipairs(boxes) do
        local piece = classify(box, options)
        if piece then pieces[#pieces + 1] = piece else out[#out + 1] = box end
    end
    table.sort(pieces, function(p, q) return p.size > q.size end)
    for i, piece in ipairs(pieces) do piece.index = i end

    local cells = {}
    local function place(piece)
        local min, max = xyBounds(piece.box)
        piece.keys = {}
        for x = math.floor((min[1] - options.gap) / CELL), math.floor((max[1] + options.gap) / CELL) do
            for y = math.floor((min[2] - options.gap) / CELL), math.floor((max[2] + options.gap) / CELL) do
                local key = cellKey(x, y)
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



    local abs, dot = math.abs, MapConv.Vec.dot
    local function mayJoin(piece, other)
        if piece.box.role ~= other.box.role then return false end
        if piece.slab and other.slab and abs(dot(piece.slab.n, other.slab.n)) >= 0.95 then return true end
        return piece.beam ~= nil and other.beam ~= nil and abs(dot(piece.beam.axis, other.beam.axis)) >= 0.97
    end
    local function byIndex(p, q) return p.index < q.index end

    local joinedCount = 0
    for _, piece in ipairs(pieces) do
        while not piece.dead do

            local seen, candidates = {}, {}
            for _, key in ipairs(piece.keys) do
                for other in pairs(cells[key] or {}) do
                    if other ~= piece and not other.dead and not seen[other] then
                        seen[other] = true
                        if mayJoin(piece, other) then candidates[#candidates + 1] = other end
                    end
                end
            end
            table.sort(candidates, byIndex)
            local grew = false
            for _, other in ipairs(candidates) do
                local box, measure, covered = join(piece, other)
                if box then
                    box.merged = (piece.box.merged or 1) + (other.box.merged or 1)
                    other.dead = true
                    unplace(other)
                    unplace(piece)


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






function Merge.boxes(boxes, step)
    step = step or 1
    local total = 0
    local cache = setmetatable({}, { __mode = "k" })
    repeat
        local pass = 0
        for k = 1, 3 do
            local joined
            boxes, joined = mergeAlong(boxes, k, step, cache)
            pass = pass + joined
        end
        total = total + pass
    until pass == 0
    return boxes, total
end



local HIDDEN_PAD, HIDDEN_CELL, COVER_SAMPLES = 1, 256, 5




local function aabb(box)
    local min, max = {}, {}
    for k = 1, 3 do
        local half = 0
        for j = 1, 3 do half = half + math.abs(box.frame[k][j]) * box.sides[j] / 2 end
        min[k], max[k] = box.center[k] - half, box.center[k] + half
    end
    return min, max
end






local function holds(box, x, y, z, pad)
    local center, f, sides = box.center, box.frame, box.sides
    local dx, dy, dz = x - center[1], y - center[2], z - center[3]
    for c = 1, 3 do
        local d = dx * f[1][c] + dy * f[2][c] + dz * f[3][c]
        if math.abs(d) > sides[c] / 2 + pad then return false end
    end
    return true
end




local function pointAt(box, fx, fy, fz)
    local sides, center, f = box.sides, box.center, box.frame
    local s1, s2, s3 = fx * sides[1], fy * sides[2], fz * sides[3]
    return center[1] + f[1][1] * s1 + f[1][2] * s2 + f[1][3] * s3,
        center[2] + f[2][1] * s1 + f[2][2] * s2 + f[2][3] * s3,
        center[3] + f[3][1] * s1 + f[3][2] * s2 + f[3][3] * s3
end

local CORNERS = { { -1, -1, -1 }, { -1, -1, 1 }, { -1, 1, -1 }, { -1, 1, 1 },
    { 1, -1, -1 }, { 1, -1, 1 }, { 1, 1, -1 }, { 1, 1, 1 } }










function Merge.hidden(boxes, cover)
    cover = cover or 0
    local items, cells = {}, {}
    for i, box in ipairs(boxes) do
        local min, max = aabb(box)
        local item = { box = box, min = min, max = max, index = i, volume = box.sides[1] * box.sides[2] * box.sides[3] }
        items[i] = item
        for x = math.floor(min[1] / HIDDEN_CELL), math.floor(max[1] / HIDDEN_CELL) do
            for y = math.floor(min[2] / HIDDEN_CELL), math.floor(max[2] / HIDDEN_CELL) do
                local key = cellKey(x, y)
                cells[key] = cells[key] or {}
                table.insert(cells[key], item)
            end
        end
    end

    local function neighbours(item)
        local found, seen = {}, {}
        for x = math.floor(item.min[1] / HIDDEN_CELL), math.floor(item.max[1] / HIDDEN_CELL) do
            for y = math.floor(item.min[2] / HIDDEN_CELL), math.floor(item.max[2] / HIDDEN_CELL) do
                for _, other in ipairs(cells[cellKey(x, y)] or {}) do
                    if other ~= item and not other.dropped and not seen[other] then
                        seen[other] = true
                        local overlaps = true
                        for k = 1, 3 do
                            if other.min[k] > item.max[k] + HIDDEN_PAD or other.max[k] < item.min[k] - HIDDEN_PAD then
                                overlaps = false
                                break
                            end
                        end
                        if overlaps then found[#found + 1] = other end
                    end
                end
            end
        end
        table.sort(found, function(a, b) return a.index < b.index end)
        return found
    end

    local order = {}
    for i, item in ipairs(items) do order[i] = item end
    table.sort(order, function(a, b)
        if a.volume ~= b.volume then return a.volume < b.volume end
        return a.index < b.index
    end)
    local hidden, covered = 0, 0
    for _, item in ipairs(order) do
        local others = neighbours(item)

        for _, other in ipairs(others) do
            local inBounds = true
            for k = 1, 3 do
                if item.min[k] < other.min[k] - HIDDEN_PAD or item.max[k] > other.max[k] + HIDDEN_PAD then
                    inBounds = false
                    break
                end
            end
            if inBounds then
                local all = true
                for _, f in ipairs(CORNERS) do
                    local x, y, z = pointAt(item.box, f[1] / 2, f[2] / 2, f[3] / 2)
                    if not holds(other.box, x, y, z, HIDDEN_PAD) then
                        all = false
                        break
                    end
                end
                if all then
                    item.dropped = true
                    hidden = hidden + 1
                    break
                end
            end
        end

        if not item.dropped and cover > 0 and #others > 0 then
            local n = COVER_SAMPLES
            local allowedOut = n ^ 3 - math.ceil(n ^ 3 * cover)
            local out = 0
            for i = 1, n do
                for j = 1, n do
                    for k = 1, n do
                        local x, y, z = pointAt(item.box, (i - 0.5) / n - 0.5, (j - 0.5) / n - 0.5, (k - 0.5) / n - 0.5)
                        local held = false
                        for _, other in ipairs(others) do
                            if holds(other.box, x, y, z, HIDDEN_PAD) then
                                held = true
                                break
                            end
                        end
                        if not held then out = out + 1 end
                        if out > allowedOut then break end
                    end
                    if out > allowedOut then break end
                end
                if out > allowedOut then break end
            end
            if out <= allowedOut then
                item.dropped = true
                covered = covered + 1
            end
        end
    end
    local kept = {}
    for _, item in ipairs(items) do
        if not item.dropped then kept[#kept + 1] = item.box end
    end
    return kept, hidden, covered
end

return Merge
