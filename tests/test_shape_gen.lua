-- utils/shape_gen.lua: the Generate tab's shapes
local T = ...
local ShapeGen = MGE.ShapeGen

---A closed loop (360 degrees): every piece the same distance from the loop's middle, and lying across the
---line from the middle (its own x axis, frame column 1, square to it), like a tangent
---@param gap number
local function checkLoop(gap)
    local amount, sides = 8, { 1, 1, 1 }
    local pieces = ShapeGen.plan(amount, gap, 360, sides, { 0, 0 }, { align = "center" })
    T.eq(#pieces, amount, "pieces, gap " .. gap)
    local mid = { 0, 0, 0 }
    for _, p in ipairs(pieces) do
        for k = 1, 3 do mid[k] = mid[k] + p.pos[k] / amount end
    end
    local radius
    for i, p in ipairs(pieces) do
        local out = { p.pos[1] - mid[1], p.pos[2] - mid[2], p.pos[3] - mid[3] }
        local r = math.sqrt(out[1] ^ 2 + out[2] ^ 2 + out[3] ^ 2)
        radius = radius or r
        T.near(r, radius, 1e-9, "piece " .. i .. " as far from the middle, gap " .. gap)
        local along = { p.frame[1][1], p.frame[2][1], p.frame[3][1] }
        local dot = (out[1] * along[1] + out[2] * along[2] + out[3] * along[3]) / r
        T.near(dot, 0, 1e-9, "piece " .. i .. " lies across the line from the middle, gap " .. gap)
    end
end

T.test("360 loop without a gap", function() checkLoop(0) end)
-- the pieces sat at the start of their stretch of the line with the whole gap after them: shifted along
-- the loop from where their turn belongs (seen in game 2026-11-15)
T.test("360 loop with a gap", function() checkLoop(1) end)

T.test("gap between neighbours", function()
    -- a straight line: piece centers as far apart as a piece and the gap
    local pieces = ShapeGen.plan(3, 0.5, 0, { 1, 1, 1 }, { 0, 0 }, { align = "center" })
    T.near(pieces[2].pos[1] - pieces[1].pos[1], 1.5, 1e-9, "first to second")
    T.near(pieces[3].pos[1] - pieces[2].pos[1], 1.5, 1e-9, "second to third")
end)
