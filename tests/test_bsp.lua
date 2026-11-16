-- mapconv/bsp.lua: the .bsp reader. Uses tf2_test2.bsp from mge/mge/assets/maps when it's there
-- (assets aren't in the repo: bsp_tool's tests/maps/Team Fortress 2/test2.bsp, GPL-3.0), the error
-- checks need no file
local T = ...
local MapConv = MGE.MapConv
local Bsp = MapConv.Bsp

T.test("broken input", function()
    T.throws(function() MapConv.parse("not a map at all", "junk.bsp") end, nil, "junk .bsp")
    T.throws(function()
        local read, size = Bsp.stringReader("VBSP" .. string.char(25, 0, 0, 0) .. string.rep("\0", 2000))
        Bsp.parse(read, size)
    end, nil, "unsupported version (v25, Momentum)")
    T.throws(function()
        local read, size = Bsp.stringReader("VBSP" .. string.char(20, 0, 0, 0) .. string.rep("\0", 40))
        Bsp.parse(read, size)
    end, nil, "cut-off file")
end)

local path = MGE.scriptPath .. "assets/maps/tf2_test2.bsp"
local file = io.open(path, "rb")
if not file then
    print("  (skipped tf2_test2.bsp: not in assets/maps)")
    return
end
local data = file:read("*a")
file:close()

T.test("tf2_test2.bsp", function()
    local map = MapConv.parse(data, "tf2_test2.bsp")
    -- Valve's vbspinfo: 75 brushes, 3 displacements
    T.eq(#map.brushes, 75, "brushes")
    T.eq(#(map.terrain or {}), 3, "displacements")
    for _, brush in ipairs(map.brushes) do
        local role = MapConv.brushRole(brush, { clips = true })
        if role ~= "drop" and not MapConv.Brush.build(brush.sides) then
            T.ok(false, "kept brush " .. tostring(brush.id) .. " doesn't build")
        end
    end
    local r = MapConv.convert(map)
    T.ok(#r.objects > 0, "converts to boxes")
    T.ok(#r.objects <= MapConv.DEFAULTS.budget, "within the budget")
end)

-- a brush entity's model is stored around its own origin: its origin and angles keys place it in the map
-- (de_train's train cars, func_brush, all sat at the map's 0 0 0 before)
T.test("brush entity models placed by origin and angles", function()
    T.eq(Bsp.placeModel({}), nil, "no keys: stays")
    T.eq(Bsp.placeModel({ origin = "0 0 0", angles = "0 0 0" }), nil, "zero keys: stays")
    -- the local +x face of a box 32 wide (x = 16)
    local face = { n = { 1, 0, 0 }, d = 16 }
    local moved = Bsp.placePlane(face, Bsp.placeModel({ origin = "100 -50 8" }))
    T.nearList(moved.n, { 1, 0, 0 }, 1e-12, "moved: same normal")
    T.near(moved.d, 116, 1e-9, "moved: x = 116")
    -- Source's angles: yaw turns forward (+x) toward +y
    local yawed = Bsp.placePlane(face, Bsp.placeModel({ angles = "0 90 0" }))
    T.nearList(yawed.n, { 0, 1, 0 }, 1e-9, "yaw 90: +x faces +y")
    T.near(yawed.d, 16, 1e-9, "yaw 90: still 16 out")
    -- positive pitch points forward down
    local pitched = Bsp.placePlane(face, Bsp.placeModel({ angles = "90 0 0" }))
    T.nearList(pitched.n, { 0, 0, -1 }, 1e-9, "pitch 90: +x faces down")
    -- roll turns +y toward +z
    local side = Bsp.placePlane({ n = { 0, 1, 0 }, d = 4 }, Bsp.placeModel({ angles = "0 0 90" }))
    T.nearList(side.n, { 0, 0, 1 }, 1e-9, "roll 90: +y faces up")
    -- turned, then moved: the move counts along the turned normal
    local both = Bsp.placePlane(face, Bsp.placeModel({ origin = "10 20 30", angles = "0 90 0" }))
    T.near(both.d, 16 + 20, 1e-9, "yaw 90 then origin: y = 36")
end)

-- brush entities players don't bump into in normal play: Retakes walls (start disabled) and never-solid
-- func_brush (de_train's A site floor piece, trims, area portal fades) aren't boxes
T.test("non-solid brush entities are dropped", function()
    local Vmf = MapConv.Vmf
    T.eq(Vmf.nonSolidEntity({ classname = "func_brush", StartDisabled = "1", Solidity = "0" }), true, "starts disabled")
    T.eq(Vmf.nonSolidEntity({ classname = "func_wall_toggle", StartDisabled = "1" }), true, "any class starting disabled")
    T.eq(Vmf.nonSolidEntity({ classname = "func_brush", StartDisabled = "0", Solidity = "1" }), true, "never solid")
    T.eq(Vmf.nonSolidEntity({ classname = "func_brush", StartDisabled = "0", Solidity = "0" }), false, "toggle, enabled")
    T.eq(Vmf.nonSolidEntity({ classname = "func_brush", Solidity = "2" }), false, "always solid")
    T.eq(Vmf.nonSolidEntity({ classname = "func_breakable" }), false, "no keys")
    local box = { entity = "func_brush", role = "clip", sides = { { material = "TOOLS/TOOLSCLIP" } } }
    T.eq(MapConv.brushRole(box), "clip", "a clip")
    box.nonSolid = true
    local role, reason = MapConv.brushRole(box)
    T.eq(role, "drop", "its entity isn't solid: dropped")
    T.eq(reason, "entity", "counted with the non-solid entities")
    -- a .vmf entity block gives its solids the flag
    local map = Vmf.parse([[
entity
{
    "classname" "func_brush"
    "StartDisabled" "1"
    solid
    {
        "id" "7"
        side { "plane" "(0 0 16) (16 0 16) (16 16 16)" "material" "TOOLS/TOOLSCLIP" }
    }
}
]])
    T.eq(map.brushes[1] and map.brushes[1].nonSolid, true, ".vmf: flagged")
end)
