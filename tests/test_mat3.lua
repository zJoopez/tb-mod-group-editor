-- utils/mat3.lua: rotations, products and the Euler angles the rotate tool and mapconv write
local T = ...
local Mat3 = MGE.Mat3

local function nearMat(a, b, eps, message)
    local flat_a, flat_b = {}, {}
    for i = 1, 3 do
        for j = 1, 3 do
            flat_a[#flat_a + 1] = a[i][j]
            flat_b[#flat_b + 1] = b[i][j]
        end
    end
    T.nearList(flat_a, flat_b, eps or 1e-9, message)
end

T.test("rotations", function()
    local h = math.pi / 2
    T.nearList(Mat3.apply(Mat3.rotZ(h), { 1, 0, 0 }), { 0, 1, 0 }, 1e-12, "rotZ 90: x -> y")
    T.nearList(Mat3.apply(Mat3.rotX(h), { 0, 1, 0 }), { 0, 0, 1 }, 1e-12, "rotX 90: y -> z")
    T.nearList(Mat3.apply(Mat3.rotY(h), { 0, 0, 1 }), { 1, 0, 0 }, 1e-12, "rotY 90: z -> x")
end)

T.test("mul and transpose", function()
    local m = Mat3.mul(Mat3.rotX(0.3), Mat3.mul(Mat3.rotY(-1.1), Mat3.rotZ(2.0)))
    nearMat(Mat3.mul(m, Mat3.transpose(m)), Mat3.IDENTITY, 1e-12, "a rotation times its transpose")
    nearMat(Mat3.mul(Mat3.IDENTITY, m), m, 0, "identity")
end)

T.test("toEulerXYZ round trip", function()
    local cases = { { 0.3, -1.1, 2.0 }, { 0, 0, 0 }, { -2.5, 0.7, -0.2 }, { 1, 1.5, 1 } }
    for _, c in ipairs(cases) do
        local m = Mat3.mul(Mat3.rotX(c[1]), Mat3.mul(Mat3.rotY(c[2]), Mat3.rotZ(c[3])))
        local x, y, z = Mat3.toEulerXYZ(m)
        local back = Mat3.mul(Mat3.rotX(x), Mat3.mul(Mat3.rotY(y), Mat3.rotZ(z)))
        nearMat(back, m, 1e-9, string.format("angles %g %g %g", c[1], c[2], c[3]))
    end
end)

T.test("toEulerXYZ gimbal lock", function()
    -- y = 90 degrees: x and z turn around the same axis, all of it goes in x
    local m = Mat3.mul(Mat3.rotX(0.4), Mat3.mul(Mat3.rotY(math.pi / 2), Mat3.rotZ(0.3)))
    local x, y, z = Mat3.toEulerXYZ(m)
    T.near(y, math.pi / 2, 1e-6, "y")
    T.eq(z, 0, "z")
    nearMat(Mat3.mul(Mat3.rotX(x), Mat3.mul(Mat3.rotY(y), Mat3.rotZ(z))), m, 1e-6, "same rotation")
end)
