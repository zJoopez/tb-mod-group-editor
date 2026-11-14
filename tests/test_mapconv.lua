-- mapconv/*.lua: hand-written .vmf maps through the whole conversion (what tools/mapconv.lua and the
-- Convert Map overlay run), checked against the boxes they should give
local T = ...
local MapConv = MGE.MapConv
local FileHandler = MGE.FileHandler
local SCALE = MapConv.DEFAULTS.scale
local ORIGIN = MGE.POS_ORIGIN

---Hammer's six planes for an axis-aligned box, outward like Hammer writes them
---@param id string|number
---@param min number[]
---@param max number[]
---@param material string|table? one for all sides, or a table: { top=, bottom=, ..., default= }
---@param skip table<string, boolean>? side names left out
local function solid(id, min, max, material, skip)
    local x0, y0, z0, x1, y1, z1 = min[1], min[2], min[3], max[1], max[2], max[3]
    local function p(x, y, z) return string.format("(%g %g %g)", x, y, z) end
    local planes = {
        { "top", p(x0, y1, z1) .. " " .. p(x1, y1, z1) .. " " .. p(x1, y0, z1) },
        { "bottom", p(x0, y0, z0) .. " " .. p(x1, y0, z0) .. " " .. p(x1, y1, z0) },
        { "west", p(x0, y1, z1) .. " " .. p(x0, y0, z1) .. " " .. p(x0, y0, z0) },
        { "east", p(x1, y1, z0) .. " " .. p(x1, y0, z0) .. " " .. p(x1, y0, z1) },
        { "north", p(x1, y1, z1) .. " " .. p(x0, y1, z1) .. " " .. p(x0, y1, z0) },
        { "south", p(x1, y0, z0) .. " " .. p(x0, y0, z0) .. " " .. p(x0, y0, z1) },
    }
    local out = { "solid", "{", '"id" "' .. id .. '"' }
    for i, plane in ipairs(planes) do
        if not (skip and skip[plane[1]]) then
            local m = type(material) == "table" and (material[plane[1]] or material.default) or material or "DEV/DEV_MEASUREGENERIC01"
            out[#out + 1] = 'side { "id" "' .. i .. '" "plane" "' .. plane[2] .. '" "material" "' .. m .. '" }'
        end
    end
    out[#out + 1] = "}"
    return table.concat(out, "\n")
end

---A .vmf: world solids, then entity blocks { classname=, origin=, solids= }
local function vmf(worldSolids, entities)
    local out = { 'world', '{', '"id" "1"', '"classname" "worldspawn"' }
    for _, s in ipairs(worldSolids) do out[#out + 1] = s end
    out[#out + 1] = "}"
    for i, e in ipairs(entities or {}) do
        out[#out + 1] = 'entity\n{\n"id" "' .. (100 + i) .. '"\n"classname" "' .. e.classname .. '"'
        if e.origin then out[#out + 1] = '"origin" "' .. e.origin .. '"' end
        for _, s in ipairs(e.solids or {}) do out[#out + 1] = s end
        out[#out + 1] = "}"
    end
    return table.concat(out, "\n")
end

local function convert(text, options)
    options = options or {}
    return MapConv.convert(MapConv.parse(text, "test.vmf"), options)
end

local function numbers(s)
    local out = {}
    for n in s:gmatch("%S+") do out[#out + 1] = tonumber(n) end
    return out
end

T.test("one box", function()
    local r = convert(vmf({ solid(1, { -64, -64, 0 }, { 64, 64, 64 }) }))
    T.eq(#r.objects, 1, "objects")
    local p = r.objects[1].props
    T.eq(p.shape, "box", "shape")
    T.nearList(p.sides, { 128 * SCALE, 128 * SCALE, 64 * SCALE }, 1e-6, "sides scaled")
    -- no anchor entity: the middle of the boxes at their lowest point goes to the dojo center, on the ground
    T.nearList(p.pos, { ORIGIN[1], ORIGIN[2], 32 * SCALE }, 1e-6, "pos")
    T.nearList(p.rot, { 0, 0, 0 }, 1e-6, "rot")
    T.eq(p.flag, tostring(MGE.FLAGS.STATIC), "static")
    T.eq(r.report.anchorFrom, "lowest point", "anchor from")
    T.eq(r.report.belowGround, 0, "nothing under the ground")
end)

T.test("ungrippable flag", function()
    local r = convert(vmf({ solid(1, { 0, 0, 0 }, { 64, 64, 64 }) }), { ungrippable = true })
    T.eq(r.objects[1].props.flag, tostring(MGE.FLAGS.STATIC + MGE.FLAGS.UNGRIPPABLE), "static + ungrippable")
end)

T.test("asset text keeps its position on import", function()
    local r = convert(vmf({ solid(1, { 0, 0, 0 }, { 64, 64, 64 }), solid(2, { 0, 200, 0 }, { 64, 264, 64 }) }),
        { source = "test.vmf" })
    T.files["map.tbm"] = MapConv.toText(r)
    local parsed = FileHandler.ParseMod("map.tbm")
    T.eq(#parsed.env_obj, 2, "objects read back")
    -- the check ui/assets.lua makes before Import
    local keep = false
    for _, line in ipairs(parsed.ignores) do
        if line:match("^%s*(%S+)") == MGE.KEEP_POSITION_TAG then keep = true end
    end
    T.ok(keep, "keep-position tag in the header")
    T.ok(parsed.ignores[1]:find("from test.vmf", 1, true), "source in the header")
    T.eq(parsed.env_obj[2].props.sides, r.objects[2].props.sides, "values survive the round trip")
end)

T.test("merge", function()
    local map = vmf({ solid(1, { 0, 0, 0 }, { 64, 64, 64 }), solid(2, { 64, 0, 0 }, { 128, 64, 64 }) })
    local r = convert(map)
    T.eq(#r.objects, 1, "touching boxes join")
    T.nearList(r.objects[1].props.sides, { 128 * SCALE, 64 * SCALE, 64 * SCALE }, 1e-6, "joined size")
    T.eq(r.report.merged, 1, "merged count")
    r = convert(map, { merge = false, simplify = false })
    T.eq(#r.objects, 2, "--no-merge keeps both")
end)

T.test("filtering", function()
    local box = function(id, material) return solid(id, { 0, 0, 0 }, { 64, 64, 64 }, material) end
    local r = convert(vmf({ box(1, { top = "TOOLS/TOOLSTRIGGER", default = "DEV/FLOOR" }) }))
    T.eq(#r.objects, 0, "a trigger face drops the brush")
    T.eq(r.report.dropped.tool, 1, "counted as tool")

    r = convert(vmf({}, { { classname = "func_buyzone", solids = { box(1) } } }))
    T.eq(r.report.dropped.entity, 1, "buy zone dropped")
    r = convert(vmf({}, { { classname = "trigger_hurt", solids = { box(1) } } }))
    T.eq(r.report.dropped.entity, 1, "trigger_ prefix dropped")
    r = convert(vmf({}, { { classname = "func_detail", solids = { box(1) } } }))
    T.eq(#r.objects, 1, "func_detail kept")

    r = convert(vmf({ box(1, "TOOLS/TOOLSNODRAW") }))
    T.eq(r.report.dropped.invisible, 1, "all nodraw: invisible, dropped")
    r = convert(vmf({ box(1, "TOOLS/TOOLSNODRAW") }), { invisible = true })
    T.eq(#r.objects, 1, "--invisible keeps it")

    r = convert(vmf({ box(1, "TOOLS/TOOLSPLAYERCLIP") }))
    T.eq(#r.objects, 1, "clips on by default")
    T.near(numbers(r.objects[1].props.color)[4], 1, 1e-9, "clips are solid")
    r = convert(vmf({ box(1, "TOOLS/TOOLSPLAYERCLIP") }), { clips = false })
    T.eq(r.report.dropped.clip, 1, "--no-clips leaves it out")

    r = convert(vmf({ box(1, "TOOLS/TOOLSSKIP") }))
    T.eq(r.report.dropped.tool, 1, "all skip: not solid")
end)

T.test("sky clips", function()
    local CLIP, SKY = "TOOLS/TOOLSPLAYERCLIP", "TOOLS/TOOLSSKYBOX"
    local sky = solid(90, { -2000, -2000, 700 }, { 2000, 2000, 764 }, SKY)
    local floor = solid(1, { -1000, -1000, -16 }, { 1000, 1000, 0 })
    local lid = solid(2, { -500, -500, 448 }, { 500, 500, 576 }, CLIP)          -- 124 under the sky
    local wall = solid(3, { 600, -500, 0 }, { 616, 500, 700 }, CLIP)            -- thin, up to the sky
    local block = solid(4, { -900, -900, 300 }, { -700, -700, 700 }, CLIP)      -- taller than wide
    local ramp = solid(5, { -500, 600, 0 }, { 0, 900, 24 }, CLIP)               -- wide and flat, far below

    local r = convert(vmf({ sky, floor, lid, wall, block, ramp }), { clips = true, merge = false, simplify = false })
    T.eq(r.report.dropped.skyClip, 1, "the lid is a sky clip")
    T.eq(#r.objects, 4, "floor, wall, block and ramp kept")
    for _, obj in ipairs(r.objects) do T.ok(not obj.lines[1].raw:find("brush 2 "), "lid not written") end

    r = convert(vmf({ sky, floor, lid }), { clips = true, skyClips = true, merge = false, simplify = false })
    T.eq(#r.objects, 2, "--sky-clips keeps it")

    -- the same lid with no sky over it (a clip under a roof): kept
    r = convert(vmf({ floor, lid }), { clips = true, merge = false, simplify = false })
    T.eq(r.report.dropped.skyClip, 0, "no sky over it: not a sky clip")

    -- sky far above (office, nuke: thin sheets up to 1150 under the sky): still a lid
    local highSky = solid(91, { -2000, -2000, 2000 }, { 2000, 2000, 2064 }, SKY)
    local sheet = solid(6, { -500, -500, 448 }, { 500, 500, 464 }, CLIP)
    r = convert(vmf({ highSky, floor, sheet }), { clips = true, merge = false, simplify = false })
    T.eq(r.report.dropped.skyClip, 1, "a thin sheet far under the sky: a lid")

    -- sky over only a corner of it: kept
    local cornerSky = solid(92, { 300, 300, 700 }, { 2000, 2000, 764 }, SKY)
    r = convert(vmf({ cornerSky, floor, lid }), { clips = true, merge = false, simplify = false })
    T.eq(r.report.dropped.skyClip, 0, "sky over 4% of it: kept")

    -- the sheet far under the sky, with something in the way (the floating rule alone decides)
    -- a roof between it and the sky (a ceiling clip): kept
    local roof = solid(7, { -600, -600, 600 }, { 600, 600, 640 })
    r = convert(vmf({ highSky, floor, sheet, roof }), { clips = true, merge = false, simplify = false })
    T.eq(r.report.dropped.skyClip, 0, "under a roof: kept")

    -- something to stand on right under it (a clip over stairs, a ledge): kept
    local ledge = solid(8, { -500, -500, 400 }, { 500, 500, 440 })
    r = convert(vmf({ highSky, floor, sheet, ledge }), { clips = true, merge = false, simplify = false })
    T.eq(r.report.dropped.skyClip, 0, "lies on a ledge: kept")

    -- standing on something under more than half of it: kept, under less: a lid
    local half = solid(9, { -500, -500, 400 }, { 100, 500, 440 })  -- 60% of the footprint
    r = convert(vmf({ highSky, floor, sheet, half }), { clips = true, merge = false, simplify = false })
    T.eq(r.report.dropped.skyClip, 0, "something under 60% of it: kept")
    local strip = solid(10, { -500, -500, 400 }, { -200, 500, 440 }) -- 30%
    r = convert(vmf({ highSky, floor, sheet, strip }), { clips = true, merge = false, simplify = false })
    T.eq(r.report.dropped.skyClip, 1, "something under 30% of it: a lid")

    -- a roof cap: a block on a roof filling the air up to the sky (inferno), close under the sky
    local cap = solid(11, { -500, -500, 440 }, { 500, 500, 680 }, CLIP)
    r = convert(vmf({ sky, floor, ledge, cap }), { clips = true, merge = false, simplify = false })
    T.eq(r.report.dropped.skyClip, 1, "on a roof, 20 under the sky: a lid")
end)

T.test("terrain slabs follow the outline", function()
    local BoxFit = MapConv.BoxFit
    local opts = { slabThickness = 8, terrainTolerance = 8 }
    ---A 5 x 5 terrain grid from a point function
    local function grid(n, fn)
        local points = {}
        for i = 0, 4 do
            for j = 0, 4 do points[#points + 1] = fn(i, j) end
        end
        return { id = "disp 1", material = "X", size = 5, n = n, points = points }
    end
    local function upright(box)
        for k = 1, 3 do
            if math.abs(box.frame[3][k]) > 0.999 then return true end
        end
        return false
    end
    local function area(slabs)
        local sum = 0
        for _, s in ipairs(slabs) do sum = sum + s.sides[1] * s.sides[2] * s.sides[3] / math.min(s.sides[1], s.sides[2], s.sides[3]) end
        return sum
    end

    -- a plain wall: one upright slab
    local slabs = BoxFit.terrain(grid({ 1, 0, 0 }, function(i, j) return { 0, j * 64, i * 64 } end), opts)
    T.eq(#slabs, 1, "flat wall: one slab")
    T.ok(upright(slabs[1]), "flat wall: upright")

    -- dust2's wall under a staircase: a trapezoid, its left edge slanted 45 degrees. Was one slab
    -- turned 45 degrees along that edge (a diamond sticking out over the stairs)
    local wall = grid({ 1, 0, 0 }, function(i, j)
        local left = i * 45
        return { 0, left + (256 - left) * j / 4, i * 45 }
    end)
    slabs = BoxFit.terrain(wall, opts)
    T.ok(#slabs > 1, "trapezoid wall: split")
    local trapezoid = (256 + 76) / 2 * 180
    -- cells along the slant are parallelograms, their boxes stick out up to half a cell: 1.42 now,
    -- the old diamond was 1.89
    T.ok(area(slabs) < 1.5 * trapezoid, "trapezoid wall: slabs cover little more than its own area")
    for _, s in ipairs(slabs) do
        if not upright(s) then T.ok(s.sides[1] * s.sides[2] * s.sides[3] / 8 < 64 * 100, "only small cells along the slant are turned") end
    end

    -- a floor grid turned 30 degrees: one slab along its edges, not a bigger world-aligned one
    local c, s = math.cos(math.rad(30)), math.sin(math.rad(30))
    slabs = BoxFit.terrain(grid({ 0, 0, 1 }, function(i, j)
        local x, y = i * 64, j * 64
        return { x * c - y * s, x * s + y * c, 0 }
    end), opts)
    T.eq(#slabs, 1, "turned floor: one slab")
    T.ok(math.abs(slabs[1].sides[1] * slabs[1].sides[2] - 256 * 256) < 1, "turned floor: along its edges")
end)

T.test("sky clips: clip ceiling", function()
    -- Italy: clips fill the air from the roofs up to one height (z 512), far under the sky, a roof
    -- poking through. Each sits on its house (not floating), the sky is 1488 over them (not close)
    local CLIP, SKY = "TOOLS/TOOLSPLAYERCLIP", "TOOLS/TOOLSSKYBOX"
    local id = 100
    local function add(list, min, max, material)
        id = id + 1
        list[#list + 1] = solid(id, min, max, material)
    end
    local function town(clipCount, extra)
        local list = {}
        add(list, { -2000, -2000, 2000 }, { 2000, 2000, 2064 }, SKY)
        add(list, { -1000, -1000, -16 }, { 1000, 1000, 0 })
        for i = 0, 5 do add(list, { -900 + i * 100, -900, 0 }, { -860 + i * 100, -860, 40 }) end -- rocks
        for i = 0, 7 do
            local x = -800 + i * 220
            add(list, { x, 0, 0 }, { x + 200, 200, 400 }) -- house
            if i < clipCount then add(list, { x, 0, 400 }, { x + 200, 200, 512 }, CLIP) end
        end
        add(list, { -800, 0, 380 }, { -600, 200, 560 }) -- a roof poking through the first clip
        for _, e in ipairs(extra or {}) do add(list, e[1], e[2], e[3]) end
        return vmf(list)
    end
    local opts = { clips = true, merge = false, simplify = false }
    local r = convert(town(8), opts)
    T.eq(r.report.dropped.skyClip, 8, "8 clips sharing z 512 over nearly everything: lids")
    r = convert(town(7), opts)
    T.eq(r.report.dropped.skyClip, 0, "7 share it: not a ceiling")
    -- a thick invisible wall from the ground up to the ceiling: kept
    r = convert(town(8, { { { -1000, -1000, 0 }, { -860, -700, 512 }, CLIP } }), opts)
    T.eq(r.report.dropped.skyClip, 8, "a tall wall up to the ceiling stays")
    -- a roof wholly over the clips (indoor, nuke): kept
    r = convert(town(8, { { { -1000, -100, 600 }, { 1000, 300, 640 } } }), opts)
    T.eq(r.report.dropped.skyClip, 0, "under a roof: kept")
    -- most solids above the shared height (a floor level, water): not a ceiling
    local high = {}
    for i = 0, 9 do high[#high + 1] = { { -900 + i * 100, 600, 600 }, { -860 + i * 100, 640, 700 } } end
    r = convert(town(8, high), opts)
    T.eq(r.report.dropped.skyClip, 0, "solids above it: not a ceiling")
end)

T.test("clip colors", function()
    local CLIP = "TOOLS/TOOLSPLAYERCLIP"
    local sand = solid(1, { -500, -500, -64 }, { 500, 500, 0 }, "DE_DUST/SAND_01")
    local brick = solid(2, { 600, -500, 0 }, { 700, 500, 300 }, "DE_DUST/BRICK_WALL")
    local ramp = solid(3, { -200, -200, 0 }, { 200, 200, 32 }, CLIP)   -- lies on the sand
    local corner = solid(4, { 580, -100, 0 }, { 596, 100, 200 }, CLIP) -- 4 from the brick wall
    local alone = solid(5, { 3000, 3000, 0 }, { 3100, 3100, 100 }, CLIP)
    local map = vmf({ sand, brick, ramp, corner, alone })
    local base = { clips = true, merge = false, simplify = false }
    local function colorOf(r, id)
        for _, obj in ipairs(r.objects) do
            if obj.lines[1].raw:find("brush " .. id .. " ", 1, true) then return numbers(obj.props.color) end
        end
    end

    local r = convert(map, base)
    T.nearList(colorOf(r, 3), MapConv.colorFor("DE_DUST/SAND_01"), 1e-9, "ramp colored like the sand under it")
    T.nearList(colorOf(r, 4), MapConv.colorFor("DE_DUST/BRICK_WALL"), 1e-9, "a clip along a wall takes the wall's")
    T.nearList(colorOf(r, 5), MapConv.colorFor(""), 1e-9, "touching nothing: plain grey")
    T.eq(colorOf(r, 5)[4], 1, "solid")
    local line
    for _, obj in ipairs(r.objects) do
        if obj.lines[1].raw:find("brush 3 ", 1, true) then line = obj.lines[1].raw end
    end
    T.ok(line and line:find("clip by DE_DUST/SAND_01", 1, true), "the borrowed material is in the comment")
end)

T.test("hidden and covered boxes", function()
    local Merge = MapConv.Merge
    local I = MGE.Mat3.IDENTITY
    local function box(id, center, sides, frame) return { id = id, center = center, sides = sides, frame = frame or I } end
    local function ids(list)
        local out = {}
        for _, b in ipairs(list) do out[#out + 1] = b.id end
        table.sort(out)
        return table.concat(out, ",")
    end

    local big = box("big", { 0, 0, 0 }, { 100, 100, 100 })
    local small = box("small", { 10, 10, 10 }, { 20, 20, 20 })
    local out = box("out", { 45, 0, 0 }, { 20, 20, 20 }) -- sticks 5 out of big
    local kept, hidden = Merge.hidden({ big, small, out })
    T.eq(ids(kept), "big,out", "the box inside goes, the one sticking out stays")
    T.eq(hidden, 1, "hidden count")

    -- inside a turned box: a 45 degree diamond holds a small box at its middle, not one at its bounds' corner
    local diamond = box("diamond", { 0, 0, 0 }, { 100, 100, 20 }, MGE.Mat3.rotZ(math.pi / 4))
    local middle = box("middle", { 0, 0, 0 }, { 30, 30, 10 })
    local corner = box("corner", { 60, 60, 0 }, { 10, 10, 10 }) -- inside the diamond's bounds, outside it
    kept = Merge.hidden({ diamond, middle, corner })
    T.eq(ids(kept), "corner,diamond", "turned containers are tested in their own axes")

    kept = Merge.hidden({ box("a", { 0, 0, 0 }, { 10, 10, 10 }), box("b", { 0, 0, 0 }, { 10, 10, 10 }) })
    T.eq(#kept, 1, "of two identical boxes one stays")

    -- covered by two halves together, inside neither
    local left, right = box("left", { -25, 0, 0 }, { 50, 100, 100 }), box("right", { 25, 0, 0 }, { 50, 100, 100 })
    local across = box("across", { 0, 0, 0 }, { 60, 20, 20 })
    kept = Merge.hidden({ left, right, across })
    T.eq(ids(kept), "across,left,right", "cover 0: only boxes inside one other go")
    local covered
    kept, hidden, covered = Merge.hidden({ left, right, across }, 0.95)
    T.eq(ids(kept), "left,right", "cover 0.95: covered by the two together")
    T.eq(covered, 1, "covered count")

    -- two boxes 70% inside each other (80% of the sample points): one goes, then the other has nobody
    -- left to be covered by and stays
    local p, q = box("p", { 0, 0, 0 }, { 100, 100, 100 }), box("q", { 30, 0, 0 }, { 100, 100, 100 })
    kept = Merge.hidden({ p, q }, 0.75)
    T.eq(ids(kept), "q", "over the share: the first goes, the other stays")
    kept = Merge.hidden({ p, q }, 0.95)
    T.eq(#kept, 2, "below the share: both stay")
end)

T.test("hidden boxes in a conversion", function()
    -- a step under its ramp clip, and a far box: budget 2 fits both kept boxes because the step is gone first
    local clip = solid(1, { 0, 0, 0 }, { 128, 128, 64 }, "TOOLS/TOOLSPLAYERCLIP")
    local step = solid(2, { 32, 32, 0 }, { 96, 96, 32 }, "DE_DUST/STONE")
    local far = solid(3, { 1000, 0, 0 }, { 1032, 32, 32 }, "DE_DUST/STONE")
    local base = { merge = false, simplify = false, budget = 2 }
    local r = convert(vmf({ clip, step, far }), base)
    T.eq(#r.objects, 2, "clip and far box")
    T.eq(r.report.dropped.hidden, 1, "the step is hidden")
    T.eq(r.report.dropped.budget, 0, "nothing over the budget")
    T.ok(table.concat(MapConv.reportLines(r.report), "\n"):find("1 boxes left out inside other boxes", 1, true), "reported")

    base.dropHidden = false
    r = convert(vmf({ clip, step, far }), base)
    T.eq(r.report.dropped.budget, 1, "kept, it takes a budget place")
end)

T.test("broken brush", function()
    -- only top and bottom: not closed, no geometry
    local open = solid(1, { 0, 0, 0 }, { 64, 64, 64 }, nil, { west = true, east = true, north = true, south = true })
    local r = convert(vmf({ open, solid(2, { 200, 0, 0 }, { 264, 64, 64 }) }))
    T.eq(r.report.dropped.broken, 1, "dropped as broken")
    T.eq(#r.objects, 1, "the good one still converts")
end)

T.test("small, budget, region", function()
    local map = vmf({
        solid(1, { 0, 0, 0 }, { 512, 512, 16 }),       -- big floor
        solid(2, { 1000, 0, 0 }, { 1128, 128, 128 }),  -- crate
        solid(3, { 2000, 0, 0 }, { 2064, 64, 64 }),    -- small crate
        solid(4, { 3000, 0, 0 }, { 3002, 2, 2 }),      -- under minSize (4) on every side
    })
    local r = convert(map)
    T.eq(#r.objects, 3, "all but the tiny one")
    T.eq(r.report.dropped.small, 1, "tiny one dropped as small")

    r = convert(map, { budget = 2 })
    T.eq(#r.objects, 2, "budget")
    T.eq(r.report.dropped.budget, 1, "over the budget")
    local kept = {}
    for _, obj in ipairs(r.objects) do kept[obj.lines[1].raw:match("brush (%d+)")] = true end
    T.ok(kept["1"] and kept["2"], "the biggest are kept")

    r = convert(map, { region = { min = { 900, -100, -100 }, max = { 1200, 200, 200 } } })
    T.eq(#r.objects, 1, "region keeps what's centered inside")
    T.eq(r.report.dropped.region, 3, "the rest dropped as outside")
end)

T.test("anchor and yaw", function()
    local map = vmf({ solid(1, { 64, -32, 0 }, { 128, 32, 64 }) },
        { { classname = "info_player_terrorist", origin = "0 0 0" } })
    local r = convert(map)
    T.eq(r.report.anchorFrom, "info_player_terrorist", "anchor entity found")
    T.nearList(r.objects[1].props.pos, { ORIGIN[1] + 96 * SCALE, ORIGIN[2], 32 * SCALE }, 1e-6, "placed from the entity")

    r = convert(map, { yaw = 90 })
    T.nearList(r.objects[1].props.pos, { ORIGIN[1], ORIGIN[2] + 96 * SCALE, 32 * SCALE }, 1e-6, "turned 90 around the anchor")

    r = convert(map, { anchor = { 96, 0, 0 } })
    T.eq(r.report.anchorFrom, "given", "a given anchor wins")
    T.nearList(r.objects[1].props.pos, { ORIGIN[1], ORIGIN[2], 32 * SCALE }, 1e-6, "given anchor at the dojo center")

    r = convert(map, { scale = 0.1, anchor = { 96, 0, 0 } })
    T.nearList(r.objects[1].props.sides, { 6.4, 6.4, 6.4 }, 1e-6, "scale")
end)

T.test("toWorld / toMap", function()
    local options = { scale = 0.05, yaw = 30 }
    local anchor = { 10, -20, 5 }
    local box = { center = { 110, 40, 69 }, sides = { 1, 1, 1 }, frame = MGE.Mat3.IDENTITY }
    local pos = MapConv.toWorld(box, anchor, options)
    T.nearList(MapConv.toMap(pos, anchor, options), box.center, 1e-9, "toMap undoes toWorld")
end)

T.test("wedge becomes a ramp slab", function()
    -- a 128 long ramp rising 64: the top face slopes up from x0 at the bottom to x1 at the top
    local text = table.concat({
        "solid", "{", '"id" "7"',
        'side { "id" "1" "plane" "(0 64 0) (128 64 64) (128 0 64)" "material" "DEV/FLOOR" }',
        'side { "id" "2" "plane" "(0 0 0) (128 0 0) (128 64 0)" "material" "DEV/FLOOR" }',
        'side { "id" "3" "plane" "(128 64 0) (128 0 0) (128 0 64)" "material" "DEV/FLOOR" }',
        'side { "id" "4" "plane" "(128 64 64) (0 64 64) (0 64 0)" "material" "DEV/FLOOR" }',
        'side { "id" "5" "plane" "(128 0 0) (0 0 0) (0 0 64)" "material" "DEV/FLOOR" }',
        "}",
    }, "\n")
    local r = convert(vmf({ text }))
    T.eq(#r.objects, 1, "one object")
    T.eq(r.report.slabs, 1, "as a slab")
    local rot = numbers(r.objects[1].props.rot)
    T.near(math.abs(rot[2]), math.deg(math.atan(64 / 128)), 1e-3, "tilted with the slope")
end)

T.test("vmf reader", function()
    local map = MapConv.Vmf.parse(vmf({ solid(5, { 0, 0, 0 }, { 8, 8, 8 }) },
        { { classname = "info_player_counterterrorist", origin = "1 2 3" } }))
    T.eq(#map.brushes, 1, "brushes")
    T.eq(map.brushes[1].id, "5", "brush id")
    T.eq(#map.brushes[1].sides, 6, "sides")
    T.eq(map.entities[1].classname, "info_player_counterterrorist", "entity class")
    T.nearList(map.entities[1].origin, { 1, 2, 3 }, 0, "entity origin")
    -- hidden blocks still compile into the map
    local hidden = 'world\n{\n"classname" "worldspawn"\nhidden\n{\n' .. solid(9, { 0, 0, 0 }, { 8, 8, 8 }) .. "\n}\n}"
    T.eq(#MapConv.Vmf.parse(hidden).brushes, 1, "hidden solid kept")
end)
