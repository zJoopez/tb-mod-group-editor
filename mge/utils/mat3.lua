-- Minimal 3x3 matrix helpers (row-major number[][]), standard right-handed rotations

---@class Mat3
local Mat3 = {
    IDENTITY = { { 1, 0, 0 }, { 0, 1, 0 }, { 0, 0, 1 } },
}

---@param a number[][]
---@param b number[][]
---@return number[][]
function Mat3.mul(a, b)
    local r = {}
    for i = 1, 3 do
        r[i] = {}
        for j = 1, 3 do
            r[i][j] = a[i][1] * b[1][j] + a[i][2] * b[2][j] + a[i][3] * b[3][j]
        end
    end
    return r
end

---@param a number[][]
---@return number[][]
function Mat3.transpose(a)
    return {
        { a[1][1], a[2][1], a[3][1] },
        { a[1][2], a[2][2], a[3][2] },
        { a[1][3], a[2][3], a[3][3] },
    }
end

---@param m number[][]
---@param v number[]
---@return number[]
function Mat3.apply(m, v)
    return {
        m[1][1] * v[1] + m[1][2] * v[2] + m[1][3] * v[3],
        m[2][1] * v[1] + m[2][2] * v[2] + m[2][3] * v[3],
        m[3][1] * v[1] + m[3][2] * v[2] + m[3][3] * v[3],
    }
end

---@param t number radians
function Mat3.rotX(t)
    local c, s = math.cos(t), math.sin(t)
    return { { 1, 0, 0 }, { 0, c, -s }, { 0, s, c } }
end

---@param t number radians
function Mat3.rotY(t)
    local c, s = math.cos(t), math.sin(t)
    return { { c, 0, s }, { 0, 1, 0 }, { -s, 0, c } }
end

---@param t number radians
function Mat3.rotZ(t)
    local c, s = math.cos(t), math.sin(t)
    return { { c, -s, 0 }, { s, c, 0 }, { 0, 0, 1 } }
end

MGE.Mat3 = Mat3
