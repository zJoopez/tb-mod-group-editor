local ShapeGen = {}
MGE.ShapeGen = ShapeGen

local RotatingOld = dofile(MGE.scriptPath .. "utils/rotating.lua")
local Mat3 = MGE.Mat3

-- Shape generator (Generate tab): a chain of boxes along X that bends up (toward Z) as it goes.
-- Angle is how far it turns in total: 0 is a straight line, 90 a quarter pipe, 360 a closed loop.
-- The pieces are chords of that arc, they touch on the inside of the bend (a ramp's riding surface
-- stays smooth) and Gap is the space between them along that edge.

---Rotation by t radians around the unit vector u (Rodrigues)
---@param u number[]
---@param t number
---@return number[][]
local function rotationAbout(u, t)
    local c, s = math.cos(t), math.sin(t)
    local k = 1 - c
    local x, y, z = u[1], u[2], u[3]
    return {
        { c + x * x * k, x * y * k - z * s, x * z * k + y * s },
        { y * x * k + z * s, c + y * y * k, y * z * k - x * s },
        { z * x * k - y * s, z * y * k + x * s, c + z * z * k },
    }
end

---@class GeneratePiece
---@field pos number[]
---@field rot number[] degrees, as written in the file
---@field frame number[][] MGE's rotation record (#mge_frame), see rotBy

---Where the pieces go: the shape's lowest point at z 0, centered on `center` in x and y
---@param amount integer
---@param gap number
---@param angle number degrees turned in total
---@param sides number[] box sides of every piece: length (x), width (y), thickness (z)
---@param center number[] x y
---@return GeneratePiece[]
local function planGenerate(amount, gap, angle, sides, center)
    local step = math.rad(angle) / amount
    local axis = { 0, -1, 0 } -- turning around -Y tilts X up toward Z
    local length, half = sides[1], sides[3] / 2
    local vertex = { 0, 0, half } -- inner (top) edge of the chain, each piece starts where it is
    local pieces = {}
    local min, max = { math.huge, math.huge, math.huge }, { -math.huge, -math.huge, -math.huge }
    for i = 0, amount - 1 do
        local turn = rotationAbout(axis, step * (i + 0.5))
        local dir, up = Mat3.apply(turn, { 1, 0, 0 }), Mat3.apply(turn, { 0, 0, 1 })
        local pos = {}
        for k = 1, 3 do pos[k] = vertex[k] + dir[k] * length / 2 - up[k] * half end
        -- box corners, for the shape's bounds
        for cx = -1, 1, 2 do
            for cy = -1, 1, 2 do
                for cz = -1, 1, 2 do
                    local corner = Mat3.apply(turn, { cx * sides[1] / 2, cy * sides[2] / 2, cz * sides[3] / 2 })
                    for k = 1, 3 do
                        min[k] = math.min(min[k], pos[k] + corner[k])
                        max[k] = math.max(max[k], pos[k] + corner[k])
                    end
                end
            end
        end
        local offsets = { Mat3.toEulerXYZ(turn) }
        table.insert(pieces, {
            pos = pos,
            rot = RotatingOld.SetRotOffset(0, 0, 0, offsets[1], offsets[2], offsets[3]),
            frame = turn,
        })
        for k = 1, 3 do vertex[k] = vertex[k] + dir[k] * (length + gap) end
    end
    local shift = { center[1] - (min[1] + max[1]) / 2, center[2] - (min[2] + max[2]) / 2, -min[3] }
    for _, piece in ipairs(pieces) do
        for k = 1, 3 do piece.pos[k] = piece.pos[k] + shift[k] end
    end
    return pieces
end


ShapeGen.plan = planGenerate

return ShapeGen
