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
