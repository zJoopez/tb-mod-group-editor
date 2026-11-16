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

T.test("rotation turns each piece around its own center, the layout stays", function()
    local Mat3 = MGE.Mat3
    -- a straight line of 3 (2 long) along X, each piece turned 90 degrees around Z: they stand across the
    -- line where they were, 2 apart along X still
    local plain = ShapeGen.plan(3, 0, 0, { 2, 1, 1 }, { 0, 0 }, { align = "center" })
    local pieces, bounds = ShapeGen.plan(3, 0, 0, { 2, 1, 1 }, { 0, 0 },
        { align = "center", rotation = Mat3.rotZ(math.rad(90)) })
    T.near(pieces[2].pos[1] - pieces[1].pos[1], 2, 1e-9, "neighbours still 2 apart along X")
    T.near(pieces[2].pos[2] - pieces[1].pos[2], 0, 1e-9, "not moved along Y")
    T.nearList({ pieces[1].frame[1][1], pieces[1].frame[2][1], pieces[1].frame[3][1] }, { 0, 1, 0 }, 1e-9,
        "each piece's X axis turned to Y")
    T.near(bounds.max[2] - bounds.min[2], 2, 1e-9, "as wide as a piece is long")
    T.near(bounds.min[3], 0, 1e-9, "on the floor")
    T.near((bounds.min[1] + bounds.max[1]) / 2, 0, 1e-9, "centered in x")
    local x, y, z = Mat3.toEulerXYZ(pieces[2].frame)
    T.nearList({ math.deg(x), math.deg(y), math.deg(z) }, { 0, 0, 90 }, 1e-6, "rot line: turned 90 around Z")
    -- no rotation: the plain shape, exactly
    T.nearList(plain[3].pos, ShapeGen.plan(3, 0, 0, { 2, 1, 1 }, { 0, 0 }, { align = "center" })[3].pos, 0,
        "without Rot nothing changes")
end)

T.test("a world turn of the first piece (Rotate gizmo) becomes the pieces' own rotation", function()
    local Mat3 = MGE.Mat3
    -- a bend (90 over 2 pieces): the first piece is tilted, a world turn around Z must turn it around world Z
    local q = Mat3.rotZ(math.rad(30))
    local plain = ShapeGen.plan(2, 0, 90, { 1, 1, 1 }, { 0, 0 })
    local turned = ShapeGen.plan(2, 0, 90, { 1, 1, 1 }, { 0, 0 }, { firstTurn = q })
    local want = Mat3.mul(q, plain[1].frame)
    for r = 1, 3 do
        T.nearList(turned[1].frame[r], want[r], 1e-9, "first piece: world turn applied, row " .. r)
    end
    -- on top of a Rot already there
    local rot = Mat3.rotX(math.rad(20))
    local both = ShapeGen.plan(2, 0, 90, { 1, 1, 1 }, { 0, 0 }, { rotation = rot, firstTurn = q })
    local withRot = ShapeGen.plan(2, 0, 90, { 1, 1, 1 }, { 0, 0 }, { rotation = rot })
    want = Mat3.mul(q, withRot[1].frame)
    for r = 1, 3 do
        T.nearList(both[1].frame[r], want[r], 1e-9, "on top of Rot, row " .. r)
    end
end)
